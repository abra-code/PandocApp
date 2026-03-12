#!/bin/bash
# pandoc.remove.selected.sh - Remove selected file from table

dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

# Get selected path
selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ]; then
    # Get all file paths from the table
    all_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"

    # Build buffer with remaining files (tab-separated: filename\tpath)
    buffer=""
    while IFS= read -r file_path; do
        if [ -n "$file_path" ] && [ "$file_path" != "$selected_path" ]; then
            filename="$("/usr/bin/basename" "$file_path")"
            buffer="${buffer}${filename}	${file_path}
"
        fi
    done <<< "$all_paths"

    # Update table with remaining files (or clear if buffer is empty)
    printf "%s" "$buffer" | /usr/bin/sort -u | "$dialog_tool" "$window_uuid" 10 omc_table_set_rows_from_stdin
fi

# Refresh controls based on current selection
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "pandoc.files.selection.changed"
