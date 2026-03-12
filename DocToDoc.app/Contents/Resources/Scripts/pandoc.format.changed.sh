#!/bin/bash
# pandoc.format.changed.sh - Handle format picker change, show/hide flavor picker

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.pandoc.sh"

output_format="$OMC_ACTIONUI_VIEW_13_VALUE"

if [ -n "$output_format" ]; then
    flavor_options=$(get_output_flavor_options "$output_format")

    if [ -n "$flavor_options" ]; then
        # Format has flavors - populate and show the flavor picker
        "$dialog_tool" "$window_uuid" ${FLAVOR_PICKER_ID} omc_set_property "options" "$flavor_options"
        "$dialog_tool" "$window_uuid" ${FLAVOR_PICKER_ID} omc_set_property "hidden" "false"
    else
        # No flavors - hide the flavor picker
        "$dialog_tool" "$window_uuid" ${FLAVOR_PICKER_ID} omc_set_property "hidden" "true"
    fi

    # Show TOC toggle only for output formats that support it
    if output_format_supports_toc "$output_format"; then
        "$dialog_tool" "$window_uuid" ${TOC_TOGGLE_ID} omc_set_property "hidden" "false"
    else
        "$dialog_tool" "$window_uuid" ${TOC_TOGGLE_ID} omc_set_property "hidden" "true"
    fi
fi
