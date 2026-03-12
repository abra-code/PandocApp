#!/bin/bash
# pandoc.add.files.sh - Add files via file picker

# Source shared library
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.pandoc.sh"

# Files selected via CHOOSE_OBJECT_DIALOG are in OMC_DLG_CHOOSE_OBJECT_PATH (newline separated)
if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    add_files_to_table "$OMC_DLG_CHOOSE_OBJECT_PATH"
fi

# Refresh controls based on current selection
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "pandoc.files.selection.changed"
