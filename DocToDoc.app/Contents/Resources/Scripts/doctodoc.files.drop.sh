#!/bin/sh
# doctodoc.files.drop.sh - Handle files dropped onto the document table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.doctodoc.sh"

plister="$OMC_OMC_SUPPORT_PATH/plister"

# OMC_ACTIONUI_TRIGGER_CONTEXT is JSON: {"items": ["/path/a", "/path/b"], "location": {...}}
_lib_log "=== doctodoc.files.drop ==="
_lib_log "OMC_ACTIONUI_TRIGGER_CONTEXT=${OMC_ACTIONUI_TRIGGER_CONTEXT}"

if [ -z "$OMC_ACTIONUI_TRIGGER_CONTEXT" ]; then
    _lib_log "No context, exiting"
    exit 0
fi

tmp_json="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/doctodoc.drop.XXXXXX.json")"
printf '%s' "$OMC_ACTIONUI_TRIGGER_CONTEXT" > "$tmp_json"

dropped_paths="$("$plister" iterate "$tmp_json" /items get value /)"
/bin/rm -f "$tmp_json"

_lib_log "dropped_paths=${dropped_paths}"

if [ -z "$dropped_paths" ]; then
    _lib_log "No paths extracted, exiting"
    exit 0
fi

add_files_to_table "$dropped_paths"

"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "doctodoc.files.selection.changed"
_lib_log "=== done ==="
