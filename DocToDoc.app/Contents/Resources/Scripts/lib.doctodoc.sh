#!/bin/bash
# lib.doctodoc.sh - Shared functions and variables for DocToDoc

# Control IDs
TABLE_ID=10
FILE_INFO_VIEW_ID=12
REMOVE_BUTTON_ID=102
REVEAL_BUTTON_ID=104
QUICKLOOK_BUTTON_ID=105
FORMAT_PICKER_ID=13
STANDALONE_TOGGLE_ID=14
TOC_TOGGLE_ID=15
FLAVOR_PICKER_ID=17

# Get dialog tool path
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

# Private pasteboard key: hand a selection from the Open... panel to a window
# that does not exist yet, so its init script can pick it up.
OPEN_PATHS_PB_KEY="DOCTODOC_OPEN_PATHS"

DEBUG=false

# The trailing "return 0" is load-bearing. With logging off the && short-circuits
# to false, and every caller that ends with a _lib_log call - doctodoc.files.drop
# does - would hand that back as its own exit status. A logging helper must never
# decide whether the handler succeeded.
_lib_log() { [ "$DEBUG" = "true" ] && printf '%s\n' "$*" >> /tmp/doctodoc_drop.log; return 0; }

# Bundled pandoc binary.
#
# Overridable so a test can point it at a recorder and assert on the flags the
# applet builds. Some of them cannot be seen any other way: pandoc omits an empty
# contents list on its own, so whether the applet asked for --toc on a document
# with no headings is invisible in the output and visible only in the argv.
pandoc_bin="${DOCTODOC_PANDOC_BIN:-${OMC_APP_BUNDLE_PATH}/Contents/Helpers/pandoc}"

# Map pandoc input format name to file extension(s), space-separated
input_format_extensions() {
    local format="$1"
    case "$format" in
        asciidoc)                echo "adoc asciidoc" ;;
        biblatex|bibtex)         echo "bib" ;;
        commonmark|commonmark_x|gfm|markdown|markdown_github|markdown_mmd|markdown_phpextra|markdown_strict)
                                 echo "md markdown" ;;
        creole)                  echo "creole" ;;
        csv)                     echo "csv" ;;
        csljson)                 echo "json" ;;
        djot)                    echo "dj djot" ;;
        docbook)                 echo "dbk xml" ;;
        docx)                    echo "docx" ;;
        epub)                    echo "epub" ;;
        fb2)                     echo "fb2" ;;
        html)                    echo "html htm" ;;
        ipynb)                   echo "ipynb" ;;
        json)                    echo "json" ;;
        latex)                   echo "tex latex" ;;
        man|mdoc)                echo "1 2 3 4 5 6 7 8 9" ;;
        mediawiki|dokuwiki|tikiwiki|twiki|vimwiki) echo "wiki" ;;
        muse)                    echo "muse" ;;
        odt)                     echo "odt" ;;
        opml)                    echo "opml" ;;
        org)                     echo "org" ;;
        pptx)                    echo "pptx" ;;
        ris)                     echo "ris" ;;
        rst)                     echo "rst" ;;
        rtf)                     echo "rtf" ;;
        t2t)                     echo "t2t" ;;
        textile)                 echo "textile" ;;
        tsv)                     echo "tsv" ;;
        typst)                   echo "typ" ;;
        xlsx)                    echo "xlsx" ;;
        xml|jats|bits|endnotexml) echo "xml" ;;
        *)                       echo "" ;;
    esac
}

# Build the plain, space-separated list of supported input extensions (lowercase)
# from pandoc --list-input-formats. This is the single source of truth: both the
# find filter (build_supported_input_extensions) and the single-file type check
# (is_supported_input_file) derive from it, so they can never drift apart.
build_supported_extension_list() {
    local tmp_formats="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/doctodoc.XXXXXX")"
    "$pandoc_bin" --list-input-formats > "$tmp_formats" 2>/dev/null
    local seen=""
    local format
    local ext
    while IFS= read -r format; do
        [ -z "$format" ] && continue
        [ "$format" = "native" ] && continue
        [ "$format" = "pod" ] && continue
        [ "$format" = "jira" ] && continue
        local exts="$(input_format_extensions "$format")"
        [ -z "$exts" ] && continue
        for ext in $exts; do
            # Skip duplicates
            case " $seen " in
                *" $ext "*) continue ;;
            esac
            seen="$seen $ext"
        done
    done < "$tmp_formats"
    /bin/rm -f "$tmp_formats"
    # Plain text (.txt) is not a pandoc input format but pandoc handles it as markdown
    case " $seen " in
        *" txt "*) ;;
        *) seen="$seen txt" ;;
    esac
    # Strip the leading space
    printf '%s\n' "${seen# }"
}

# Lazy accessor for the plain extension list
get_supported_extension_list() {
    if [ -z "$_SUPPORTED_EXTENSION_LIST_CACHED" ]; then
        _SUPPORTED_EXTENSION_LIST_CACHED="$(build_supported_extension_list)"
    fi
    printf '%s\n' "$_SUPPORTED_EXTENSION_LIST_CACHED"
}

# Build filter arguments for the find command from the supported extension list.
build_supported_input_extensions() {
    local result=""
    local ext
    for ext in $(get_supported_extension_list); do
        if [ -n "$result" ]; then
            result="$result -o -iname *.$ext"
        else
            result="-iname *.$ext"
        fi
    done
    printf '%s\n' "$result"
}

# Lazy accessor - only calls build_supported_input_extensions on first use
get_supported_input_extensions() {
    if [ -z "$_SUPPORTED_INPUT_EXTENSIONS_CACHED" ]; then
        _SUPPORTED_INPUT_EXTENSIONS_CACHED="$(build_supported_input_extensions)"
    fi
    printf '%s\n' "$_SUPPORTED_INPUT_EXTENSIONS_CACHED"
}

# Return 0 if filename has a supported (case-insensitive) input extension, else 1.
# Used to filter individually selected/dropped files; directory contents are
# filtered by find -iname, which is already case-insensitive.
is_supported_input_file() {
    local filename="$1"
    # A name with no dot has no extension -> unsupported
    case "$filename" in
        *.*) ;;
        *) return 1 ;;
    esac
    local ext="$(printf '%s' "${filename##*.}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    case " $(get_supported_extension_list) " in
        *" $ext "*) return 0 ;;
    esac
    return 1
}

# Show a single consolidated alert for files skipped because their type is not
# supported. Aggregates so a multi-file drop produces one dialog, not one per file.
# Arguments: count, newline-separated list of file names
notify_unsupported_files() {
    local count="$1"
    local names="$2"
    local alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

    # Cap the listed names so a large drop does not produce a giant dialog
    local max_list=10
    local shown="$(printf '%s\n' "$names" | /usr/bin/head -n "$max_list")"
    local extra=$(( count - max_list ))

    local header
    if [ "$count" -eq 1 ]; then
        header="1 file was skipped because its type is not supported:"
    else
        header="$count files were skipped because their type is not supported:"
    fi

    local message="$header
$shown"
    if [ "$extra" -gt 0 ]; then
        message="$message
...and $extra more"
    fi

    "$alert_tool" --level caution --title "DocToDoc" "$message"
}

# Formats to exclude from the output picker
# pdf/beamer: require LaTeX or other PDF engine
# native/json/csljson: pandoc internal representations
# flavor variants handled by flavor picker: markdown_*, commonmark*, gfm, html4/5, asciidoctor, docbook5, epub2/3, wiki variants
# bbcode variants: too niche for general use
# highly technical: jats_*, context, ms, tei, texinfo, vimdoc, chunkedhtml, icml, haddock, muse, fb2
EXCLUDED_OUTPUT_FORMATS="pdf beamer asciidoc_legacy markdown_github markdown_mmd markdown_phpextra markdown_strict markua commonmark commonmark_x gfm html4 html5 asciidoctor docbook4 docbook5 epub2 epub3 dokuwiki xwiki zimwiki jira bbcode_fluxbb bbcode_hubzilla bbcode_phpbb bbcode_steam bbcode_xenforo native json csljson jats_archiving jats_articleauthoring jats_publishing context ms tei texinfo vimdoc chunkedhtml icml haddock muse fb2 ansi xml"

# Popular formats shown in the top section of the picker
POPULAR_OUTPUT_FORMATS="html docx odt epub pptx rtf markdown latex plain"

# Formats that have flavor variants
# Returns flavor options JSON for a given format, or empty string if no flavors
get_output_flavor_options() {
    local format="$1"
    case "$format" in
        markdown)
            echo '[{"title": "Pandoc", "tag": "markdown"},{"title": "GitHub (GFM)", "tag": "gfm"},{"title": "Strict (original)", "tag": "markdown_strict"},{"title": "CommonMark", "tag": "commonmark"},{"title": "CommonMark Extended", "tag": "commonmark_x"},{"title": "MultiMarkdown", "tag": "markdown_mmd"},{"title": "PHP Extra", "tag": "markdown_phpextra"},{"title": "Markua (Leanpub)", "tag": "markua"}]'
            ;;
        html)
            echo '[{"title": "HTML 5", "tag": "html5"},{"title": "HTML 4", "tag": "html4"}]'
            ;;
        asciidoc)
            echo '[{"title": "AsciiDoc", "tag": "asciidoc"},{"title": "AsciiDoctor", "tag": "asciidoctor"}]'
            ;;
        docbook)
            echo '[{"title": "DocBook 5", "tag": "docbook5"},{"title": "DocBook 4", "tag": "docbook4"}]'
            ;;
        epub)
            echo '[{"title": "EPUB 3", "tag": "epub3"},{"title": "EPUB 2", "tag": "epub2"}]'
            ;;
        mediawiki)
            echo '[{"title": "MediaWiki (Wikipedia)", "tag": "mediawiki"},{"title": "DokuWiki", "tag": "dokuwiki"},{"title": "XWiki", "tag": "xwiki"},{"title": "Zim Wiki", "tag": "zimwiki"},{"title": "Jira", "tag": "jira"}]'
            ;;
        *)
            echo ""
            ;;
    esac
}

# Resolve the actual pandoc --to format from the main picker + optional flavor picker
# Arguments: main_format flavor_value
# If flavor is set and non-empty, use it; otherwise use the main format directly
resolve_output_format() {
    local main_format="$1"
    local flavor="$2"
    if [ -n "$flavor" ]; then
        echo "$flavor"
    else
        echo "$main_format"
    fi
}

# Output formats that support --toc (table of contents)
output_format_supports_toc() {
    local format="$1"
    case "$format" in
        html|html4|html5)        return 0 ;; 
        docx)                    return 0 ;;
        odt|opendocument)        return 0 ;;
        epub|epub2|epub3)        return 0 ;;
        pptx)                    return 0 ;;
        *)                       return 1 ;;
    esac
}

# Input file extensions that are likely to have heading structure for --toc
# Returns 1 (false) for flat/structured data without headings
input_extension_has_headings() {
    local ext="${1##*.}"
    ext=$(echo "$ext" | /usr/bin/tr '[:upper:]' '[:lower:]')
    case "$ext" in
        md|markdown)             return 0 ;;
        html|htm)                return 0 ;;
        docx)                    return 0 ;;
        odt)                     return 0 ;;
        pptx)                    return 0 ;;
        epub)                    return 0 ;;
        tex|latex)               return 0 ;;
        org)                     return 0 ;;
        rst)                     return 0 ;;
        adoc|asciidoc)           return 0 ;;
        dbk)                     return 0 ;;
        wiki)                    return 0 ;;
        textile)                 return 0 ;;
        typ)                     return 0 ;;
        t2t)                     return 0 ;;
        dj|djot)                 return 0 ;;
        ipynb)                   return 0 ;;
        creole)                  return 0 ;;
        *)                       return 1 ;;
    esac
}

# Display names for known formats
get_output_format_display_name() {
    local format="$1"
    case "$format" in
        asciidoc)          echo "AsciiDoc" ;;
        asciidoctor)       echo "AsciiDoctor" ;;
        bbcode)            echo "BBCode" ;;
        biblatex)          echo "BibLaTeX (Bibliography)" ;;
        bibtex)            echo "BibTeX (Bibliography)" ;;
        commonmark)        echo "CommonMark" ;;
        commonmark_x)      echo "CommonMark Extended" ;;
        djot)              echo "Djot" ;;
        docbook)           echo "DocBook (XML)" ;;
        docbook5)          echo "DocBook 5 (XML)" ;;
        docx)              echo "Microsoft Word (docx)" ;;
        dokuwiki)          echo "DokuWiki" ;;
        dzslides)          echo "DZSlides (HTML Slides)" ;;
        epub)              echo "EPUB (E-book)" ;;
        epub3)             echo "EPUB 3 (E-book)" ;;
        html)              echo "HTML" ;;
        html5)             echo "HTML 5" ;;
        ipynb)             echo "Jupyter Notebook" ;;
        jats)              echo "JATS (Journal Article)" ;;
        jira)              echo "Jira Wiki" ;;
        latex)             echo "LaTeX" ;;
        man)               echo "Man Page (roff)" ;;
        markdown)          echo "Markdown (md)" ;;
        markdown_mmd)      echo "MultiMarkdown" ;;
        markdown_phpextra) echo "Markdown (PHP Extra)" ;;
        markdown_strict)   echo "Markdown (Strict)" ;;
        markua)            echo "Markua (Leanpub)" ;;
        mediawiki)         echo "Wiki" ;;
        odt)               echo "OpenDocument (odt)" ;;
        opendocument)      echo "OpenDocument (XML)" ;;
        opml)              echo "OPML (Outline)" ;;
        org)               echo "Emacs Org Mode" ;;
        plain)             echo "Plain Text (txt)" ;;
        pptx)              echo "PowerPoint (pptx)" ;;
        revealjs)          echo "Reveal.js (HTML Slides)" ;;
        rst)               echo "reStructuredText (rst)" ;;
        rtf)               echo "Rich Text Format (rtf)" ;;
        s5)                echo "S5 (HTML Slides)" ;;
        slideous)          echo "Slideous (HTML Slides)" ;;
        slidy)             echo "Slidy (HTML Slides)" ;;
        textile)           echo "Textile" ;;
        typst)             echo "Typst" ;;
        xwiki)             echo "XWiki" ;;
        zimwiki)           echo "Zim Wiki" ;;
        *)                 echo "$format" ;;
    esac
}

# Map output format tags to file extensions
output_format_to_extension() {
    local format="$1"
    case "$format" in
        html|html4|html5)        echo "html" ;;
        docx)                    echo "docx" ;;
        odt|opendocument)        echo "odt" ;;
        epub|epub2|epub3)         echo "epub" ;;
        latex)                   echo "tex" ;;
        markdown|markdown_mmd|markdown_phpextra|markdown_strict|markua) echo "md" ;;
        gfm|commonmark|commonmark_x) echo "md" ;;
        rst)                     echo "rst" ;;
        plain)                   echo "txt" ;;
        revealjs|dzslides|s5|slideous|slidy) echo "html" ;;
        rtf)                     echo "rtf" ;;
        pptx)                    echo "pptx" ;;
        docbook|docbook4|docbook5) echo "xml" ;;
        ipynb)                   echo "ipynb" ;;
        man)                     echo "1" ;;
        org)                     echo "org" ;;
        textile)                 echo "textile" ;;
        typst)                   echo "typ" ;;
        biblatex|bibtex)         echo "bib" ;;
        opml)                    echo "opml" ;;
        jats)                    echo "xml" ;;
        asciidoc|asciidoctor)    echo "adoc" ;;
        djot)                    echo "dj" ;;
        mediawiki|dokuwiki|xwiki|zimwiki|jira) echo "wiki" ;;
        *)                       echo "$format" ;;
    esac
}

# Add files to the table.
# Argument: newline-separated list of file or directory paths to add.
# Directories are scanned recursively for pandoc-supported input formats.
add_files_to_table() {
    local new_paths="$1"
    local buffer=""
    local file_path="" filename="" found_file=""
    # Track individually added files skipped for unsupported type, so we can
    # warn once at the end instead of one alert per file.
    local unsupported_count=0
    local unsupported_names=""

    _lib_log "--- add_files_to_table ---"
    _lib_log "new_paths='${new_paths}'"

    # Preserve existing table rows
    local existing_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS"
    if [ -n "$existing_paths" ]; then
        local tmp_existing="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/doctodoc.XXXXXX")"
        printf '%s\n' "$existing_paths" > "$tmp_existing"
        while IFS= read -r file_path; do
            [ -z "$file_path" ] && continue
            filename="$(/usr/bin/basename "$file_path")"
            buffer="${buffer}${filename}	${file_path}
"
        done < "$tmp_existing"
        /bin/rm -f "$tmp_existing"
    fi

    # Process each new path
    local supported_exts="$(get_supported_input_extensions)"
    local tmp_new="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/doctodoc.XXXXXX")"
    printf '%s\n' "$new_paths" > "$tmp_new"
    while IFS= read -r file_path; do
        [ -z "$file_path" ] && continue
        _lib_log "processing path='${file_path}'"

        if [ -d "$file_path" ]; then
            # Directory — scan recursively for pandoc-supported input formats
            local tmp_files="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/doctodoc.XXXXXX")"
            /usr/bin/find "$file_path" -type f \
                \( $supported_exts \) \
                ! -path "*/.*" -print > "$tmp_files" 2>/dev/null
            while IFS= read -r found_file; do
                [ -z "$found_file" ] && continue
                _lib_log "  found: '${found_file}'"
                filename="$(/usr/bin/basename "$found_file")"
                buffer="${buffer}${filename}	${found_file}
"
            done < "$tmp_files"
            /bin/rm -f "$tmp_files"

        elif [ -e "$file_path" ]; then
            _lib_log "  is file"
            filename="$(/usr/bin/basename "$file_path")"
            if is_supported_input_file "$filename"; then
                buffer="${buffer}${filename}	${file_path}
"
            else
                _lib_log "  unsupported type, skipping: $filename"
                unsupported_count=$(( unsupported_count + 1 ))
                if [ -z "$unsupported_names" ]; then
                    unsupported_names="$filename"
                else
                    unsupported_names="$unsupported_names
$filename"
                fi
            fi
        fi
    done < "$tmp_new"
    /bin/rm -f "$tmp_new"

    _lib_log "buffer='${buffer}'"

    # Sort, deduplicate, and push to the table.
    # The sorted rows go through a temp file so the path that ends up in row 0
    # can be read back - callers use it to select and describe the first document
    # without waiting for a selection event that may not have landed yet.
    _first_row_path=""
    if [ -n "$buffer" ]; then
        local tmp_rows="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/doctodoc.XXXXXX")"
        printf "%s" "$buffer" | /usr/bin/sort -u > "$tmp_rows"
        _first_row_path="$(/usr/bin/head -1 "$tmp_rows" | /usr/bin/cut -f2)"
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin < "$tmp_rows"
        /bin/rm -f "$tmp_rows"
    else
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows
    fi

    # Warn once about any individually added files of unsupported type
    if [ "$unsupported_count" -gt 0 ]; then
        notify_unsupported_files "$unsupported_count" "$unsupported_names"
    fi

    _lib_log "--- add_files_to_table done ---"
}

# Bring the selection-dependent controls in line with a file path, or with
# nothing selected when the path is empty.
# Arguments: file_path (may be empty)
apply_file_selection() {
    local selected_path="$1"
    local file_size="" size_display="" file_type="" created="" modified=""

    if [ -z "$selected_path" ]; then
        "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${QUICKLOOK_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${FILE_INFO_VIEW_ID} ""
        return
    fi

    "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${QUICKLOOK_BUTTON_ID} omc_enable

    local file_info="File: $selected_path"

    if [ -e "$selected_path" ]; then
        file_size="$(/usr/bin/stat -f "%z" "$selected_path" 2>/dev/null)"
        if [ -n "$file_size" ]; then
            if [ "$file_size" -gt 1048576 ]; then
                size_display="$((file_size / 1048576)) MB"
            elif [ "$file_size" -gt 1024 ]; then
                size_display="$((file_size / 1024)) KB"
            else
                size_display="${file_size} bytes"
            fi
            file_info="${file_info}
  Size: ${size_display}"
        fi

        file_type="$(/usr/bin/file -b "$selected_path" 2>/dev/null)"
        if [ -n "$file_type" ]; then
            file_info="${file_info}
  Type: ${file_type}"
        fi

        created="$(/usr/bin/stat -f "%SB" "$selected_path" 2>/dev/null)"
        modified="$(/usr/bin/stat -f "%Sm" "$selected_path" 2>/dev/null)"

        if [ -n "$created" ] || [ -n "$modified" ]; then
            file_info="${file_info}

  Created: ${created}
  Modified: ${modified}"
        fi
    fi

    "$dialog_tool" "$window_uuid" ${FILE_INFO_VIEW_ID} "$file_info"
}
