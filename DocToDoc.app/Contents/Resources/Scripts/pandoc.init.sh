#!/bin/bash
# pandoc.init.sh - Initialize the table and populate format picker

# Source shared library
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.pandoc.sh"

# Set up table columns
"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_columns "Documents"
"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_column_widths 270

# Clear any existing rows
"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows

# Query pandoc for supported output formats
all_formats=$("$pandoc_bin" --list-output-formats 2>/dev/null)

# Build a set of available formats (after exclusions)
available_formats=""
while IFS= read -r format; do
    [ -z "$format" ] && continue
    skip=false
    for excluded in $EXCLUDED_OUTPUT_FORMATS; do
        if [ "$format" = "$excluded" ]; then
            skip=true
            break
        fi
    done
    [ "$skip" = true ] && continue
    available_formats="${available_formats} ${format}"
done <<< "$all_formats"

# Build sectioned JSON: Popular section first, then Other
options_json="[{\"section\": \"Popular\"}"

# Add popular formats in the defined order (only if available)
for format in $POPULAR_OUTPUT_FORMATS; do
    for avail in $available_formats; do
        if [ "$format" = "$avail" ]; then
            display_name=$(get_output_format_display_name "$format")
            options_json="${options_json},{\"title\": \"${display_name}\", \"tag\": \"${format}\"}"
            break
        fi
    done
done

# Add Other section header
options_json="${options_json},{\"section\": \"Other\"}"

# Collect non-popular formats, sorted alphabetically by display name
other_entries=""
for format in $available_formats; do
    is_popular=false
    for popular in $POPULAR_OUTPUT_FORMATS; do
        if [ "$format" = "$popular" ]; then
            is_popular=true
            break
        fi
    done
    [ "$is_popular" = true ] && continue

    display_name=$(get_output_format_display_name "$format")
    other_entries="${other_entries}${display_name}|${format}
"
done

# Sort Other entries by display name and append to JSON
while IFS='|' read -r display_name format; do
    [ -z "$format" ] && continue
    options_json="${options_json},{\"title\": \"${display_name}\", \"tag\": \"${format}\"}"
done <<< "$(printf "%s" "$other_entries" | /usr/bin/sort -df)"

options_json="${options_json}]"

# Set the format picker options dynamically and default to Plain Text
"$dialog_tool" "$window_uuid" ${FORMAT_PICKER_ID} omc_set_property "options" "$options_json"
"$dialog_tool" "$window_uuid" ${FORMAT_PICKER_ID} "plain"

# Hide TOC toggle - Plain Text does not support it
"$dialog_tool" "$window_uuid" ${TOC_TOGGLE_ID} omc_set_property "hidden" "true"

# If files were dropped on the app, add them
if [ -n "$OMC_OBJ_PATH" ]; then
    add_files_to_table "$OMC_OBJ_PATH"
fi
