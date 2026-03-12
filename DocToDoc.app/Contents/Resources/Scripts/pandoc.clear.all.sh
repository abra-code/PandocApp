#!/bin/bash
# pandoc.clear.all.sh - Clear all files from table

dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

# Clear all rows from the table
"$dialog_tool" "$window_uuid" 10 omc_table_remove_all_rows

# Refresh controls based on current selection
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "pandoc.files.selection.changed"
