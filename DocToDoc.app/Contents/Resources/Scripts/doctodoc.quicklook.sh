#!/bin/bash
# doctodoc.quicklook.sh - preview the selected file in a native Quick Look window.
# Runs in the main window context, so it reads the live table selection, hands the
# path to the Quick Look window's init via a private pasteboard, then opens the
# window (its ACTIONUI_WINDOW runs doctodoc.quicklook.init).

next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

QL_PB_KEY="DOCTODOC_QUICKLOOK_PATH"

# Column 1 is the filename, column 2 is the full path (hidden)
selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    "$pasteboard_tool" "$QL_PB_KEY" set "$selected_path"
    "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "doctodoc.quicklook.window"
else
    "$alert_tool" --level caution --title "DocToDoc" "File does not exist"
fi
