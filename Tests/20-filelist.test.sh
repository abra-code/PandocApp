#!/bin/sh
# Tests/20-filelist.test.sh - building the document list, and what a selection
# does.
#
# This applet filters harder than its siblings: the list of extensions it will
# accept is derived from `pandoc --list-input-formats`, so the filter and the
# engine cannot drift apart. That derivation is worth testing directly, because
# a filter that silently matches nothing looks exactly like a filter that works.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.doctodoc.sh"

section "preconditions"
check_preconditions

# --------------------------------------------------------------------------
section "the supported-extension list comes from pandoc"
# --------------------------------------------------------------------------
extensions="$(doctodoc_call get_supported_extension_list)"
check "the list was built" "yes" \
    "$([ "$(printf '%s\n' "$extensions" | /usr/bin/wc -w)" -gt 15 ] && echo yes || echo no)"
check "markdown is in it" "yes" "$(contains " $extensions " " md ")"
check "html is in it"     "yes" "$(contains " $extensions " " html ")"
# .txt is not a pandoc input format; the applet adds it deliberately because
# pandoc reads plain text as markdown.
check "and txt was added on top"  "yes" "$(contains " $extensions " " txt ")"

check "a supported file is accepted"   "yes" \
    "$(doctodoc_call is_supported_input_file "article.md" && echo yes || echo no)"
check "an unsupported one is refused"  "no" \
    "$(doctodoc_call is_supported_input_file "blob.bin" && echo yes || echo no)"
check "a file with no extension is refused" "no" \
    "$(doctodoc_call is_supported_input_file "README" && echo yes || echo no)"
check "and the check ignores case" "yes" \
    "$(doctodoc_call is_supported_input_file "ARTICLE.MD" && echo yes || echo no)"

# --------------------------------------------------------------------------
section "the add panel puts chosen documents in the list"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init

omc_dialog_answer choose_object "$(fixture article.md)
$(fixture page.html)"
run_with_list doctodoc.add.files
check_status "the add handler succeeded" 0

check "both documents were added" "2" "$(file_count)"
check "sorted by display name" "article.md
page.html" "$(file_list_names)"
check "and it refreshed the row buttons afterwards" "1" \
    "$(chain_asked doctodoc.files.selection.changed)"

# --------------------------------------------------------------------------
section "adding more keeps what was already there"
# --------------------------------------------------------------------------
# add_files_to_table rebuilds the whole table from the engine's ALL_ROWS export
# plus the new paths, so "preserves the existing rows" is a real behavior with a
# real way to break: run_with_list is what supplies that export.
omc_dialog_answer choose_object "$(fixture notes.txt)"
run_with_list doctodoc.add.files
check "the list grew rather than being replaced" "3" "$(file_count)"
check "the earlier documents are still there" "yes" \
    "$(contains "$(file_list_names)" "article.md")"

# --------------------------------------------------------------------------
section "a file pandoc cannot read is skipped, and the user is told once"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init
alerts_reset

omc_dialog_answer choose_object "$(fixture article.md)
$(fixture blob.bin)"
run_with_list doctodoc.add.files

check "the readable document went in" "1" "$(file_count)"
check "the unreadable one did not"    "no" "$(contains "$(file_list_names)" "blob.bin")"
check "and exactly one alert was raised" "1" "$(alerts_count)"
check "which named the skipped file" "1" "$(alerts_mention "blob.bin")"

# --------------------------------------------------------------------------
section "a folder is scanned for the document types pandoc reads"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init

folder="$OMCTEST_WORK/papers"
/bin/mkdir -p "$folder/nested"
/bin/cp "$(fixture article.md)" "$folder/one.md"
/bin/cp "$(fixture page.html)" "$folder/nested/two.html"
/bin/cp "$(fixture blob.bin)" "$folder/three.bin"
/bin/chmod -R u+w "$folder"

omc_dialog_answer choose_object "$folder"
run_with_list doctodoc.add.files
check "documents were found, including in subfolders" "2" "$(file_count)"
check "and the unreadable type was left out" "no" \
    "$(contains "$(file_list_names)" "three.bin")"
# A folder's strays are filtered silently - one alert per stray file in a
# scanned folder would be unusable. Only individually chosen files are reported.
check "scanning a folder raises no alert" "0" "$(alerts_count)"

# --------------------------------------------------------------------------
section "dropping documents on the table adds them"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init

omc_drop "$(fixture article.md)" "$(fixture page.html)"
run_with_list doctodoc.files.drop
check_status "the drop handler succeeded" 0
check "both dropped documents landed" "2" "$(file_count)"
check "and the row buttons were refreshed" "1" \
    "$(chain_asked doctodoc.files.selection.changed)"

# --------------------------------------------------------------------------
section "a drop with no payload changes nothing"
# --------------------------------------------------------------------------
chains_reset
omc_trigger "$TABLE_ID"
run_with_list doctodoc.files.drop
check_status "the handler exited cleanly" 0
check "the list is untouched" "2" "$(file_count)"
check "and nothing was refreshed" "0" "$(chain_asked doctodoc.files.selection.changed)"

# --------------------------------------------------------------------------
section "selecting a row lights up its buttons and describes it"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init
select_file "$(fixture article.md)"
omc_run doctodoc.files.selection.changed
check_status "the selection handler succeeded" 0

check "remove is live"     "1" "$(ui_enabled "$REMOVE_BUTTON_ID")"
check "reveal is live"     "1" "$(ui_enabled "$REVEAL_BUTTON_ID")"
check "quick look is live" "1" "$(ui_enabled "$QUICKLOOK_BUTTON_ID")"
check "the info pane names the file"   "yes" "$(contains "$(info_text)" "article.md")"
check "reports its size"               "yes" "$(contains "$(info_text)" "Size:")"
check "what kind of file it is"        "yes" "$(contains "$(info_text)" "Type:")"
check "and the dates the applet adds"  "yes" "$(contains "$(info_text)" "Modified:")"

# --------------------------------------------------------------------------
section "losing the selection puts them back to sleep"
# --------------------------------------------------------------------------
clear_selection
omc_run doctodoc.files.selection.changed
check "remove is dead"     "0" "$(ui_enabled "$REMOVE_BUTTON_ID")"
check "reveal is dead"     "0" "$(ui_enabled "$REVEAL_BUTTON_ID")"
check "quick look is dead" "0" "$(ui_enabled "$QUICKLOOK_BUTTON_ID")"
check "and the info pane was cleared" "" "$(info_text)"

# --------------------------------------------------------------------------
section "remove takes out the selected row and leaves the rest"
# --------------------------------------------------------------------------
reset_window
omc_run doctodoc.init
omc_dialog_answer choose_object "$(fixture article.md)
$(fixture page.html)
$(fixture notes.txt)"
run_with_list doctodoc.add.files
check "three documents to start with" "3" "$(file_count)"

select_file "$(fixture page.html)"
run_with_list doctodoc.remove.selected
check_status "the remove handler succeeded" 0
check "one row went"                "2" "$(file_count)"
check "and it was the selected one" "no" "$(contains "$(file_list_names)" "page.html")"
check "the others stayed"           "yes" "$(contains "$(file_list_names)" "article.md")"

# --------------------------------------------------------------------------
section "remove with nothing selected removes nothing"
# --------------------------------------------------------------------------
clear_selection
run_with_list doctodoc.remove.selected
check "the list is unchanged" "2" "$(file_count)"

# --------------------------------------------------------------------------
section "clear all empties the list"
# --------------------------------------------------------------------------
run_with_list doctodoc.clear.all
check_status "the clear handler succeeded" 0
check "the list is empty" "0" "$(file_count)"
check "the table was actively emptied" "yes" \
    "$([ "$(ui_calls "omc_table_remove_all_rows")" -ge 1 ] && echo yes || echo no)"

# --------------------------------------------------------------------------
section "cumulative: the last section's window writes were all declared"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
