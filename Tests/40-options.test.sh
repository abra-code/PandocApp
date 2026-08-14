#!/bin/sh
# Tests/40-options.test.sh - the option controls that react to each other.
#
# Three handlers live here that nothing else in the suite dispatches, and one of
# them guards a whole feature: choosing a flavor is what makes the difference
# between GitHub markdown and strict markdown, or HTML 4 and HTML 5, and that
# choice reaches pandoc only through resolve_output_format. Gutting that function
# left the rest of the suite entirely green, which is how this file came to be
# written.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.doctodoc.sh"

section "preconditions"
check_preconditions

article="$(fixture_copy article.md)"

new_destination() { # -> path
    local dir
    dir="$(/usr/bin/mktemp -d "$OMCTEST_WORK/dest.XXXXXX")"
    printf '%s' "$dir"
}

load_documents() { # <path ...>
    reset_window
    omc_run doctodoc.init
    omc_dialog_answer choose_object "$(printf '%s\n' "$@")"
    run_with_list doctodoc.add.files
}

# --------------------------------------------------------------------------
section "a format with flavors offers them; one without puts the picker away"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init

omc_fire doctodoc.format.changed "$FORMAT_PICKER_ID" markdown
check_status "the handler succeeded" 0
check "the flavor picker is showing" "false" "$(ui_prop "$FLAVOR_PICKER_ID" hidden)"
flavors="$(ui_prop "$FLAVOR_PICKER_ID" options)"
check "GitHub markdown is offered" "yes" "$(contains "$flavors" '"tag": "gfm"')"
check "and strict markdown too"    "yes" "$(contains "$flavors" '"tag": "markdown_strict"')"

omc_fire doctodoc.format.changed "$FORMAT_PICKER_ID" html
check "html offers its own flavors" "false" "$(ui_prop "$FLAVOR_PICKER_ID" hidden)"
check "html 5 among them" "yes" "$(contains "$(ui_prop "$FLAVOR_PICKER_ID" options)" '"tag": "html5"')"

# docx has one form only, so the picker must go away rather than sit there empty
# showing the previous format's flavors.
omc_fire doctodoc.format.changed "$FORMAT_PICKER_ID" docx
check "a format with no flavors hides the picker" "true" \
    "$(ui_prop "$FLAVOR_PICKER_ID" hidden)"

# --------------------------------------------------------------------------
section "the contents toggle appears only for formats that can carry one"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init

for _format in html docx odt epub pptx; do
    omc_fire doctodoc.format.changed "$FORMAT_PICKER_ID" "$_format"
    check "$_format can carry a contents list" "false" "$(ui_prop "$TOC_TOGGLE_ID" hidden)"
done

for _format in plain latex rtf markdown; do
    omc_fire doctodoc.format.changed "$FORMAT_PICKER_ID" "$_format"
    check "$_format cannot, so the toggle is hidden" "true" "$(ui_prop "$TOC_TOGGLE_ID" hidden)"
done

# --------------------------------------------------------------------------
section "turning the contents list on turns standalone on with it"
# --------------------------------------------------------------------------
# pandoc puts the contents list in the document template, so --toc without
# --standalone produces a fragment with no contents list at all. The applet
# resolves that for the user rather than letting them ask for something that
# cannot work.
reset_window
omc_run doctodoc.init
omc_control "$STANDALONE_TOGGLE_ID" false

omc_fire doctodoc.toc.changed "$TOC_TOGGLE_ID" true
check_status "the handler succeeded" 0
check "standalone was switched on" "true" "$(ui_value "$STANDALONE_TOGGLE_ID")"

# Turning the contents list off must not switch standalone back off - the user
# may want a whole document for its own sake.
ui_reset
omc_fire doctodoc.toc.changed "$TOC_TOGGLE_ID" false
check "turning it off leaves standalone alone" "" "$(ui_value "$STANDALONE_TOGGLE_ID")"

# --------------------------------------------------------------------------
section "the chosen flavor is what reaches pandoc"
# --------------------------------------------------------------------------
# The picker's value overrides the main format. Without this the flavor list is
# decoration: every conversion would use the base format and the user's choice
# between GFM and strict markdown would go nowhere.
check "a flavor overrides the main format" "gfm" \
    "$(doctodoc_call resolve_output_format markdown gfm)"
check "and with no flavor the main format stands" "markdown" \
    "$(doctodoc_call resolve_output_format markdown "")"

load_documents "$article"
omc_control "$FORMAT_PICKER_ID" markdown
omc_control "$FLAVOR_PICKER_ID" gfm
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
record_pandoc_calls
run_with_list doctodoc.start.batch
use_real_pandoc

check "pandoc was asked for the flavor, not the base format" "yes" \
    "$(contains "$(pandoc_call_for article.md)" "--to=gfm")"
check "and not for the base format" "no" \
    "$(contains "$(pandoc_call_for article.md)" "--to=markdown ")"

# The control for the pair above: with the flavor picker left alone, the same
# batch must ask for the base format - otherwise "gfm reached pandoc" could be
# true of every run regardless of the picker.
load_documents "$article"
omc_control "$FORMAT_PICKER_ID" markdown
omc_control "$FLAVOR_PICKER_ID" ""
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
record_pandoc_calls
run_with_list doctodoc.start.batch
use_real_pandoc
check "with no flavor chosen the base format is used" "yes" \
    "$(contains "$(pandoc_call_for article.md)" "--to=markdown")"

# --------------------------------------------------------------------------
section "a flavor really changes the output"
# --------------------------------------------------------------------------
# The argv assertions above prove the applet asked. This proves the asking
# matters: GitHub markdown writes a fenced code block where strict markdown
# indents one, so the two flavors produce visibly different files.
fenced="$OMCTEST_WORK/fenced.md"
{
    printf 'Some text.\n\n'
    printf '``` sh\n'
    printf 'echo hello\n'
    printf '```\n'
} > "$fenced"

load_documents "$fenced"
omc_control "$FORMAT_PICKER_ID" markdown
omc_control "$FLAVOR_PICKER_ID" gfm
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "GitHub markdown keeps the fence" "yes" \
    "$([ "$(count_matches '```' "$destination/fenced.md")" -ge 1 ] && echo yes || echo no)"

load_documents "$fenced"
omc_control "$FORMAT_PICKER_ID" markdown
omc_control "$FLAVOR_PICKER_ID" markdown_strict
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "strict markdown has no fences to keep" "0" \
    "$(count_matches '```' "$destination/fenced.md")"
check "but the code survived, indented" "yes" \
    "$([ "$(count_matches 'echo hello' "$destination/fenced.md")" -ge 1 ] && echo yes || echo no)"

# --------------------------------------------------------------------------
section "cumulative: the last section's window writes were all declared"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
