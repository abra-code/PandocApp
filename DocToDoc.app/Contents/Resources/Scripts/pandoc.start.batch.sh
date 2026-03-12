#!/bin/bash
# pandoc.start.batch.sh - Run batch conversion using pandoc

# env | sort

# Source shared library
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.pandoc.sh"

# Get destination folder from CHOOSE_FOLDER_DIALOG
destination="$OMC_DLG_CHOOSE_FOLDER_PATH"

if [ -z "$destination" ]; then
    exit 0
fi

# Get output format from main Picker id 13
main_format="$OMC_ACTIONUI_VIEW_13_VALUE"

if [ -z "$main_format" ]; then
    main_format="html"
fi

# Check if this format has flavors and read the flavor picker value
flavor_options=$(get_output_flavor_options "$main_format")
if [ -n "$flavor_options" ]; then
    flavor_value="$OMC_ACTIONUI_VIEW_17_VALUE"
else
    flavor_value=""
fi

# Resolve the actual pandoc format to use
output_format=$(resolve_output_format "$main_format" "$flavor_value")

# Get file extension for the resolved format
output_ext="$(output_format_to_extension "$output_format")"

# Get all file paths from the table (column 2)
file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"

if [ -z "$file_paths" ]; then
    exit 0
fi

# Convert newline-separated paths to array
IFS=$'\n' read -r -d '' -a files <<< "$file_paths" || true

# Get options
standalone="$OMC_ACTIONUI_VIEW_14_VALUE"
toc="$OMC_ACTIONUI_VIEW_15_VALUE"
overwrite="$OMC_ACTIONUI_VIEW_16_VALUE"

# Build pandoc flags (--toc is added per-file based on input format)
pandoc_flags="--to=$output_format"

if [ "$standalone" = "true" ]; then
    pandoc_flags="$pandoc_flags --standalone"
fi

# Collect errors and results
errors=""
results=""
skipped=""

# Process each file
success_count=0
error_count=0
skipped_count=0

for file_path in "${files[@]}"; do
    if [ -e "$file_path" ]; then
        filename="$("/usr/bin/basename" "$file_path")"
        name_without_ext="${filename%.*}"

        output_file="$destination/${name_without_ext}.${output_ext}"

        # Check if output exists - skip if overwrite is not enabled
        if [ -e "$output_file" ] && [ "$overwrite" != "true" ]; then
            ((skipped_count++))
            skipped="${skipped}
- ${name_without_ext}.${output_ext}: skipped"
        else
            # Add --toc only if enabled and the input file has heading structure
            file_flags="$pandoc_flags"
            if [ "$toc" = "true" ] && input_extension_has_headings "$file_path"; then
                file_flags="$file_flags --toc"
            fi

            # Run pandoc conversion
            output="$("$pandoc_bin" $file_flags -o "$output_file" "$file_path" 2>&1)"
            exit_code=$?

            if [ $exit_code -eq 0 ]; then
                ((success_count++))
                results="${results}
✓ ${name_without_ext}.${output_ext}"
            else
                ((error_count++))
                errors="${errors}
✗ ${name_without_ext}.${output_ext}: ${output}"
            fi
        fi
    else
        ((error_count++))
        errors="${errors}
✗ ${file_path}: file does not exist"
    fi
done

# Build completion message
result_message="Destination Folder:
${destination}

Format: ${output_format}
Converted: ${success_count} succeeded, ${skipped_count} skipped, ${error_count} failed${results}${skipped}${errors}"

"$dialog_tool" "$window_uuid" ${FILE_INFO_VIEW_ID} "$result_message"
