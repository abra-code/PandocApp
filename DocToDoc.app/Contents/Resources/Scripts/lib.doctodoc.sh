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
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

DEBUG=false

_lib_log() { [ "$DEBUG" = "true" ] && printf '%s\n' "$*" >> /tmp/doctodoc_drop.log; }

# Bundled pandoc binary
pandoc_bin="${OMC_APP_BUNDLE_PATH}/Contents/Helpers/pandoc"

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

# Build filter arguments for find command from pandoc --list-input-formats
build_supported_input_extensions() {
    local tmp_formats="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/doctodoc.XXXXXX")"
    "$pandoc_bin" --list-input-formats > "$tmp_formats" 2>/dev/null
    local seen=""
    local result=""
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
            if [ -n "$result" ]; then
                result="$result -o -iname *.$ext"
            else
                result="-iname *.$ext"
            fi
        done
    done < "$tmp_formats"
    /bin/rm -f "$tmp_formats"
    # Plain text (.txt) is not a pandoc input format but pandoc handles it as markdown
    case " $seen " in
        *" txt "*) ;;
        *) result="$result -o -iname *.txt" ;;
    esac
    printf '%s\n' "$result"
}

# Lazy accessor - only calls build_supported_input_extensions on first use
get_supported_input_extensions() {
    if [ -z "$_SUPPORTED_INPUT_EXTENSIONS_CACHED" ]; then
        _SUPPORTED_INPUT_EXTENSIONS_CACHED="$(build_supported_input_extensions)"
    fi
    printf '%s\n' "$_SUPPORTED_INPUT_EXTENSIONS_CACHED"
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
            buffer="${buffer}${filename}	${file_path}
"
        fi
    done < "$tmp_new"
    /bin/rm -f "$tmp_new"

    _lib_log "buffer='${buffer}'"

    # Sort, deduplicate, and push to the table
    if [ -n "$buffer" ]; then
        printf "%s" "$buffer" | /usr/bin/sort -u | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
    else
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows
    fi
    _lib_log "--- add_files_to_table done ---"
}
