#!/bin/bash
# doctodoc.files.selection.changed.sh - Handle file selection changes

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.doctodoc.sh"

# Get selected row - column 1 is filename, column 2 is path (hidden)
apply_file_selection "$OMC_ACTIONUI_TABLE_10_COLUMN_2_VALUE"
