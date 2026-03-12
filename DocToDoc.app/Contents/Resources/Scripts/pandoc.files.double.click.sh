#!/bin/bash
# pandoc.files.double.click.sh - Handle double-click on file

# Get the double-clicked row path
selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    # Open the file with the default application
    /usr/bin/open "$selected_path"
fi
