#!/bin/bash
# pandoc.toc.changed.sh - When TOC is enabled, auto-enable Standalone (required for HTML TOC)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.pandoc.sh"

toc_value="$OMC_ACTIONUI_VIEW_15_VALUE"

if [ "$toc_value" = "true" ]; then
    "$dialog_tool" "$window_uuid" ${STANDALONE_TOGGLE_ID} "true"
fi
