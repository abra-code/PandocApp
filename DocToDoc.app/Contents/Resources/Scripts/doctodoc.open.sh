#!/bin/bash
# doctodoc.open.sh - "Open..." menu item handler
#
# CHOOSE_OBJECT_DIALOG has already let the user pick documents and/or folders
# (newline-separated in OMC_DLG_CHOOSE_OBJECT_PATH). Hand the selection to a new
# window via the private pasteboard and chain to doctodoc.new, whose
# ACTIONUI_WINDOW opens the dialog and runs doctodoc.init.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.doctodoc.sh"

if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    "$pasteboard_tool" "$OPEN_PATHS_PB_KEY" put "$OMC_DLG_CHOOSE_OBJECT_PATH"
    "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "doctodoc.new"
fi
