#!/bin/sh
# Tests/30-batch.test.sh - the Convert run, end to end against the bundled
# pandoc.
#
# Real documents in, real documents out, with the results read back. Naming a
# file correctly is not the same as converting it, and only reading the output
# can tell the two apart.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.doctodoc.sh"

section "preconditions"
check_preconditions

article="$(fixture_copy article.md)"
page="$(fixture_copy page.html)"
notes="$(fixture_copy notes.txt)"

# Convert into a fresh empty folder each time, so "the file is there" cannot be
# satisfied by something an earlier section left behind.
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
section "pressing Convert with an empty list says so"
# --------------------------------------------------------------------------
# The window now opens empty, so Convert is reachable with nothing to convert.
# It used to exit silently, which returned the user from the destination panel
# to a screen where nothing had changed.
reset_window
omc_run doctodoc.init
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check_status "the handler succeeded" 0
check "the info pane explains the empty list" "yes" \
    "$(contains "$(info_text)" "Nothing to convert")"
check "and nothing was written to the destination" "0" \
    "$(/usr/bin/find "$destination" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# --------------------------------------------------------------------------
section "markdown to html really produces html"
# --------------------------------------------------------------------------
load_documents "$article"
omc_control "$FORMAT_PICKER_ID" html
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check_status "the batch succeeded" 0

check "the output carries the format's extension" "yes" \
    "$([ -f "$destination/article.html" ] && echo yes || echo no)"
check "the heading became a real html heading" "1" \
    "$(count_matches '<h1' "$destination/article.html")"
check "the body text came through" "1" \
    "$(count_matches 'MARKER-MD' "$destination/article.html")"
check "the info pane reports the success" "yes" "$(contains "$(info_text)" "1 succeeded")"
check "and names the format it used"      "yes" "$(contains "$(info_text)" "Format: html")"

# --------------------------------------------------------------------------
section "the extension follows the format, not the format's name"
# --------------------------------------------------------------------------
# A handful of pandoc formats write a file whose extension is nothing like the
# format name. Getting this wrong produces files no other app will open.
check "plain writes .txt"     "txt" "$(doctodoc_call output_format_to_extension plain)"
check "latex writes .tex"     "tex" "$(doctodoc_call output_format_to_extension latex)"
check "markdown writes .md"   "md"  "$(doctodoc_call output_format_to_extension markdown)"
check "docbook writes .xml"   "xml" "$(doctodoc_call output_format_to_extension docbook)"
# The fallthrough: a format with no special case keeps its own name.
check "and anything else keeps its name" "docx" \
    "$(doctodoc_call output_format_to_extension docx)"

load_documents "$article"
omc_control "$FORMAT_PICKER_ID" plain
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "converting to plain really wrote a .txt" "yes" \
    "$([ -f "$destination/article.txt" ] && echo yes || echo no)"
check "and the markdown syntax is gone from it" "0" \
    "$(count_matches '^# ' "$destination/article.txt")"

# --------------------------------------------------------------------------
section "standalone asks pandoc for a whole document"
# --------------------------------------------------------------------------
# Without it pandoc emits a fragment. The difference is a real one for html: a
# fragment has no <head>, so nothing downstream can style or open it properly.
load_documents "$article"
omc_control "$FORMAT_PICKER_ID" html
omc_control "$STANDALONE_TOGGLE_ID" false
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "a fragment has no head element" "0" \
    "$(count_matches '<head>' "$destination/article.html")"

load_documents "$article"
omc_control "$FORMAT_PICKER_ID" html
omc_control "$STANDALONE_TOGGLE_ID" true
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "standalone produces a whole document" "1" \
    "$(count_matches '<head>' "$destination/article.html")"

# --------------------------------------------------------------------------
section "the table of contents is only requested where it means something"
# --------------------------------------------------------------------------
# --toc against a document with no headings produces an empty contents list,
# so the applet asks per input file rather than once for the batch.
check "a markdown file can have headings" "yes" \
    "$(doctodoc_call input_extension_has_headings "$article" && echo yes || echo no)"
check "a plain text file cannot"          "no" \
    "$(doctodoc_call input_extension_has_headings "$notes" && echo yes || echo no)"

load_documents "$article"
omc_control "$FORMAT_PICKER_ID" html
omc_control "$STANDALONE_TOGGLE_ID" true
omc_control "$TOC_TOGGLE_ID" true
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "the contents list was built" "1" \
    "$(count_matches '<nav id="TOC"' "$destination/article.html")"
check "and it lists the document's headings" "1" \
    "$(count_matches 'toc-a-subheading' "$destination/article.html")"

# The negative control, without which the check above is satisfied by a
# standalone document that always carries a contents list.
load_documents "$article"
omc_control "$FORMAT_PICKER_ID" html
omc_control "$STANDALONE_TOGGLE_ID" true
omc_control "$TOC_TOGGLE_ID" false
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "with the toggle off there is no contents list" "0" \
    "$(count_matches '<nav id="TOC"' "$destination/article.html")"

# --toc is decided per input file, not once for the batch: a contents list of
# nothing is worse than none. This is only observable in the argv - pandoc omits
# an empty contents list by itself, so the converted file looks identical either
# way and an assertion against it could never fail.
load_documents "$article" "$notes"
omc_control "$FORMAT_PICKER_ID" html
omc_control "$STANDALONE_TOGGLE_ID" true
omc_control "$TOC_TOGGLE_ID" true
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
record_pandoc_calls
run_with_list doctodoc.start.batch
use_real_pandoc

check "both documents were handed to pandoc" "2" "$(pandoc_call_count)"
check "the one with headings was converted with a contents list" "yes" \
    "$(contains "$(pandoc_call_for article.md)" "--toc")"
check "the one without headings was not" "no" \
    "$(contains "$(pandoc_call_for notes.txt)" "--toc")"
# The control for the pair above: both invocations carry the flags that do apply
# to the whole batch, so "no --toc" is a real difference and not a recorder that
# captured nothing.
check "and both still asked for the chosen format" "yes" \
    "$(contains "$(pandoc_call_for notes.txt)" "--to=html")"
check "and standalone" "yes" \
    "$(contains "$(pandoc_call_for notes.txt)" "--standalone")"

# --------------------------------------------------------------------------
section "a mixed batch converts every input format"
# --------------------------------------------------------------------------
load_documents "$article" "$page" "$notes"
omc_control "$FORMAT_PICKER_ID" plain
destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check_status "the batch succeeded" 0

check "all three were written" "3" \
    "$(/usr/bin/find "$destination" -type f -name '*.txt' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "the markdown's text came through" "1" \
    "$(count_matches 'MARKER-MD' "$destination/article.txt")"
check "the html's text came through"     "1" \
    "$(count_matches 'MARKER-HTML' "$destination/page.txt")"
check "and its markup did not"           "0" \
    "$(count_matches '<h1>' "$destination/page.txt")"
check "the info pane reports three successes" "yes" "$(contains "$(info_text)" "3 succeeded")"

# --------------------------------------------------------------------------
section "an existing file is kept unless overwrite is on"
# --------------------------------------------------------------------------
load_documents "$article"
omc_control "$FORMAT_PICKER_ID" html
destination="$(new_destination)"
printf 'PREVIOUS CONTENT\n' > "$destination/article.html"

omc_control "$OVERWRITE_TOGGLE_ID" false
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "the existing file was left alone" "PREVIOUS CONTENT" \
    "$(cat "$destination/article.html")"
check "and the run says it skipped one" "yes" "$(contains "$(info_text)" "1 skipped")"

omc_control "$OVERWRITE_TOGGLE_ID" true
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check "with overwrite on it was replaced" "1" \
    "$(count_matches 'MARKER-MD' "$destination/article.html")"
check "and counted as a success" "yes" "$(contains "$(info_text)" "1 succeeded")"

# --------------------------------------------------------------------------
section "a listed document that has gone missing is reported, not fatal"
# --------------------------------------------------------------------------
vanishing="$OMCTEST_WORK/vanishing.md"
/bin/cp "$article" "$vanishing"
/bin/chmod u+w "$vanishing"
load_documents "$vanishing" "$page"
omc_control "$FORMAT_PICKER_ID" plain
/bin/rm -f "$vanishing"

destination="$(new_destination)"
omc_dialog_answer choose_folder "$destination"
run_with_list doctodoc.start.batch
check_status "the batch still finished" 0
check "the surviving document was converted" "1" \
    "$(count_matches 'MARKER-HTML' "$destination/page.txt")"
check "the missing one is counted as a failure" "yes" "$(contains "$(info_text)" "1 failed")"
check "and named in the report" "yes" "$(contains "$(info_text)" "vanishing")"

# --------------------------------------------------------------------------
section "canceling the destination panel converts nothing"
# --------------------------------------------------------------------------
load_documents "$article"
before="$(info_text)"
omc_dialog_answer choose_folder ""
run_with_list doctodoc.start.batch
check_status "the handler exited cleanly" 0
check "the info pane was not touched" "$before" "$(info_text)"

# --------------------------------------------------------------------------
section "cumulative: the last section's window writes were all declared"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
