#!/bin/bash
# pandoc.quicklook.sh - QuickLook preview of selected file

# Get selected file path from table (column 2)
selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    /usr/bin/qlmanage -p "$selected_path"
else
    alert="$OMC_OMC_SUPPORT_PATH/alert"
    "$alert" --level caution --title "DocToDoc" "File does not exist"
fi
