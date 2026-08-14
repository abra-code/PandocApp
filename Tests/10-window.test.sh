#!/bin/sh
# Tests/10-window.test.sh - the window as it opens, and the two ways it gets
# seeded.
#
# The applet used to demand a file-selection panel before showing anything: its
# main command was act_file_or_folder, so launching with no document made the
# engine go looking for one. That was a particularly poor fit here, because the
# output format list is built from pandoc at window init and is worth browsing
# before choosing any input. It now opens empty.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.doctodoc.sh"

section "preconditions"
check_preconditions

# --------------------------------------------------------------------------
section "the window opens empty and says what to do with it"
# --------------------------------------------------------------------------
reset_window
omc_object ""
omc_run doctodoc.init
check_status "init succeeded with no document" 0

check "the document list starts empty" "0" "$(file_count)"
check "the table was actively emptied, not merely never filled" "1" \
    "$(ui_calls "omc_table_remove_all_rows")"
check "the table's column was named" "Documents" "$(ui_columns "$TABLE_ID")"
# With no document there is nothing else in the window to explain itself, so
# this text is the whole of the empty state.
check "the info pane tells the user what to do" "yes" \
    "$(contains "$(info_text)" "Drop documents")"

# --------------------------------------------------------------------------
section "init builds the format picker from pandoc itself"
# --------------------------------------------------------------------------
# The whole reason opening empty matters for this applet: the format list is not
# in the JSON, it is whatever the embedded pandoc says it can write.
formats="$(offered_formats)"
check "the picker was filled" "yes" \
    "$([ "$(printf '%s\n' "$formats" | /usr/bin/wc -w)" -gt 10 ] && echo yes || echo no)"
check "html is offered"  "yes" "$(contains "$formats" "html")"
check "docx is offered"  "yes" "$(contains "$formats" "docx")"
check "plain is offered" "yes" "$(contains "$formats" "plain")"

# Formats pandoc cannot produce without a LaTeX engine are deliberately dropped -
# offering them would promise a conversion that always fails.
check "pdf is not offered" "no" "$(contains "$formats" "pdf")"
# The positive control for that check: the exclusion list has to be doing the
# work, not an empty picker.
check "and the exclusion list did not simply empty the picker" "yes" \
    "$(contains "$formats" "epub")"

check "the picker is left on plain text" "plain" "$(ui_value "$FORMAT_PICKER_ID")"
# Plain text supports no table of contents, so the toggle must start hidden -
# a picker fires no action for the value it starts on, and nothing else would
# hide it.
check "the contents toggle starts hidden" "true" "$(ui_prop "$TOC_TOGGLE_ID" hidden)"

# --------------------------------------------------------------------------
section "the declared window state is the one the handlers assume"
# --------------------------------------------------------------------------
reset_window
check "the declared defaults loaded" "yes" \
    "$([ "${OMCTEST_DEFAULTS_APPLIED:-0}" -gt 3 ] && echo yes || echo no)"

# The overwrite toggle is the only id this suite restates rather than imports,
# so it is checked against the document: if it moved, the batch tests would
# otherwise keep passing while driving the wrong control.
check "the overwrite toggle starts off" "false" \
    "$(eval "printf '%s' \"\$OMC_ACTIONUI_VIEW_${OVERWRITE_TOGGLE_ID}_VALUE\"")"
check "the standalone toggle starts off" "false" \
    "$(eval "printf '%s' \"\$OMC_ACTIONUI_VIEW_${STANDALONE_TOGGLE_ID}_VALUE\"")"
check "the contents toggle starts off" "false" \
    "$(eval "printf '%s' \"\$OMC_ACTIONUI_VIEW_${TOC_TOGGLE_ID}_VALUE\"")"

# --------------------------------------------------------------------------
section "a window opened on dropped documents seeds itself from them"
# --------------------------------------------------------------------------
# Documents dropped on the app icon arrive as OMC_OBJ_PATH on the chained
# command. This is the path the migration changed - the window used to hang off
# the main command directly - so it is worth an explicit test.
reset_window
omc_object "$(fixture article.md)"
omc_run doctodoc.init
check_status "init succeeded with an object" 0

check "the dropped document is in the list" "1" "$(file_count)"
check "listed by name" "article.md" "$(file_list_names)"
check "and by path"    "$(fixture article.md)" "$(file_list)"

# Init selects and describes the first row directly rather than chaining to the
# selection handler, to avoid racing the selection it just made.
check "the first row is selected"    "0" "$(ui_selection "$TABLE_ID")"
check "the row's buttons came alive" "1" "$(ui_enabled "$REMOVE_BUTTON_ID")"
check "reveal too"                   "1" "$(ui_enabled "$REVEAL_BUTTON_ID")"
check "quick look too"               "1" "$(ui_enabled "$QUICKLOOK_BUTTON_ID")"
check "the info pane describes the document" "yes" \
    "$(contains "$(info_text)" "article.md")"
check "and no longer shows the empty-state hint" "no" \
    "$(contains "$(info_text)" "Drop documents")"

# Seeding happens after the pandoc query, so the format picker is ready by the
# time the list is - the reason init was reordered.
check "the format picker was still built" "yes" \
    "$([ "$(offered_formats | /usr/bin/wc -w)" -gt 10 ] && echo yes || echo no)"

# --------------------------------------------------------------------------
section "File > Open... seeds a new window through the pasteboard"
# --------------------------------------------------------------------------
reset_window
omc_dialog_answer choose_object "$(fixture page.html)"
omc_run doctodoc.open
check_status "the open handler succeeded" 0

check "it asked for a window to be made" "1" "$(chain_asked doctodoc.new)"
check "and left the selection where the new window will look" \
    "$(fixture page.html)" "$(pb_open_paths get)"

# The window the chain would open. OMC_OBJ_PATH is empty here - that is what
# distinguishes Open... from a drop on the app icon.
omc_object ""
omc_run doctodoc.init
check "the new window picked the selection up" "1" "$(file_count)"
check "from the pasteboard, not from the object" "$(fixture page.html)" "$(file_list)"
check "and consumed it, so the next window opens empty" "" "$(pb_open_paths get)"

# The positive control for that last check: an empty read has to mean "cleared",
# not "this accessor never worked".
pb_open_paths set "sentinel" >/dev/null 2>&1
check "the pasteboard accessor does read back" "sentinel" "$(pb_open_paths get)"

# --------------------------------------------------------------------------
section "a canceled Open... makes no window and leaves nothing behind"
# --------------------------------------------------------------------------
reset_window
chains_reset
omc_dialog_answer choose_object ""
omc_run doctodoc.open
check_status "the handler succeeded" 0
check "no window was asked for" "0" "$(chain_asked doctodoc.new)"
check "and nothing was handed off" "" "$(pb_open_paths get)"

# --------------------------------------------------------------------------
section "a dropped object wins over a stale pasteboard handoff"
# --------------------------------------------------------------------------
# Both seeding paths can be armed at once - an Open... whose window never opened
# leaves its key set. The object is the one the user just acted on.
reset_window
pb_open_paths set "$(fixture page.html)" >/dev/null 2>&1
omc_object "$(fixture article.md)"
omc_run doctodoc.init
check "the dropped document is what loaded" "article.md" "$(file_list_names)"
check "and only it" "1" "$(file_count)"

# --------------------------------------------------------------------------
section "cumulative: the last section's window writes were all declared"
# --------------------------------------------------------------------------
# Every earlier section was checked by reset_window on its way out; this covers
# the one after the last reset.
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
