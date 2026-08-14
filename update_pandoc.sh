#!/bin/bash
# update_pandoc.sh
# Downloads and installs the latest (or specified) pandoc release into the app bundle.
#
# DocToDoc ships separate per-arch builds - never a universal binary - so this script
# always installs a single-arch pandoc and takes --arch to say which one. Upstream
# publishes ready-made arm64 and x86_64 macOS zips, so nothing has to be lipo'd or
# thinned afterwards; ./thin_distribution.sh has no work to do on Contents/Helpers.

set -uo pipefail

# Colors only when the stream they land on is a terminal, so redirecting to a build
# log does not fill it with escape sequences. stdout and stderr are gated separately
# because they are routinely redirected apart from each other.
# stdout carries progress only, so green is the whole palette it needs: everything
# red-worthy goes to stderr through err().
if [ -t 1 ]; then
    GREEN=$(printf '\033[92m')
    RESET=$(printf '\033[0m')
else
    GREEN=""
    RESET=""
fi

if [ -t 2 ]; then
    ERR_RED=$(printf '\033[91m')
    ERR_RESET=$(printf '\033[0m')
else
    ERR_RED=""
    ERR_RESET=""
fi

VERSION="auto"
ARCH="auto"
SIGNING_IDENTITY="-"
APP_BUNDLE=""   # empty = resolve from SCRIPT_DIR; --app=PATH overrides

PREFERRED_APP_NAME="DocToDoc.app"

# Set by prepare()
ASSET_NAME=""
DOWNLOAD_URL=""
WORK_DIR=""
ZIPFILE=""
EXTRACT_DIR=""
HOST_ARCH=""

# Set by update_copyright() / verify_install()
COPYRIGHT_STATUS=""   # "ok", "unchanged", "download-failed"
VERIFY_STATUS=""      # "ok", "arch-only"

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" >/dev/null 2>&1 && pwd)"

# Every failure message goes to stderr so that `./update_pandoc.sh > build.log` still
# shows what went wrong. Advisory notices that do not abort the run use this too - a
# warning nobody sees is not a warning.
err() {
    echo "${ERR_RED}$*${ERR_RESET}" >&2
}

# Picks the bundle to update, in priority order:
#   1. --app=PATH, if the caller named one
#   2. $SCRIPT_DIR/$PREFERRED_APP_NAME, if present
#   3. the sole *.app in SCRIPT_DIR
# More than one candidate with no preferred name and no --app is an error rather than
# a coin flip on glob order.
resolve_app_bundle() {
    if [ -n "$APP_BUNDLE" ]; then
        APP_BUNDLE="${APP_BUNDLE%/}"
        [ -d "$APP_BUNDLE" ] || { err "--app bundle not found: $APP_BUNDLE"; exit 1; }
    elif [ -d "$SCRIPT_DIR/$PREFERRED_APP_NAME" ]; then
        APP_BUNDLE="$SCRIPT_DIR/$PREFERRED_APP_NAME"
    else
        local candidates=()
        local _candidate
        for _candidate in "$SCRIPT_DIR"/*.app; do
            [ -d "$_candidate" ] || continue
            candidates+=("$_candidate")
        done

        case "${#candidates[@]}" in
            0) err "No .app bundle found in $SCRIPT_DIR"; exit 1 ;;
            1) APP_BUNDLE="${candidates[0]}" ;;
            *)
                err "Multiple .app bundles in $SCRIPT_DIR and no $PREFERRED_APP_NAME to pin to:"
                for _candidate in "${candidates[@]}"; do
                    echo "  $(/usr/bin/basename "$_candidate")" >&2
                done
                echo "Pass --app=PATH to name the target explicitly." >&2
                exit 1
                ;;
        esac
    fi

    # A directory is not a bundle, and neither is one that merely ends in .app.
    # Without this, prepare() creates Contents/Helpers inside whatever was named and
    # installs 190 MB there before codesign fails. Checked on every resolution path,
    # not just --app: an empty DocToDoc.app placeholder would fail the same way.
    [ -f "$APP_BUNDLE/Contents/Info.plist" ] || {
        err "Not an app bundle (no Contents/Info.plist): $APP_BUNDLE"
        exit 1
    }
}

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Downloads the specified (or latest) pandoc macOS release and installs the binary
into <AppName>.app/Contents/Helpers/pandoc, refreshes the bundled pandoc
COPYRIGHT file, then codesigns the app.

Target bundle: $PREFERRED_APP_NAME in the directory containing this script, if
present; otherwise the sole *.app there.

Options:
  --version=VERSION   pandoc release to install (e.g. 3.10.2, default: auto-detect latest)
  --arch=ARCH         Architecture: arm64 or x86_64 (default: auto-detect from host)
  --identity=CERT     Signing identity for codesign (default: - for ad-hoc)
  --app=PATH          App bundle to update (default: $PREFERRED_APP_NAME beside this script)
  --help              Show this help message

Exit status:
  0  pandoc installed, signed and verified
  1  the update did not complete - see the error. Codesigning and verification run
     after the binary is in place, so a failure there leaves the bundle holding a
     new pandoc that is unsigned or unverified.
  2  pandoc installed and signed, but the COPYRIGHT refresh failed - the bundle's
     license file is missing or left over from a different release

Examples:
  ./update_pandoc.sh
  ./update_pandoc.sh --version=3.10.2 --arch=arm64
  ./update_pandoc.sh --arch=x86_64
  ./update_pandoc.sh --app=/path/to/DocToDoc.app --identity="Developer ID Application: Me (TEAMID)"
EOF
}

# An option whose value went missing - "--arch" as the last argument, or "--app=" -
# must not fall through to the default. Silently updating the default bundle, or
# ad-hoc signing when a Developer ID was intended, is the kind of mistake that is
# only noticed after distribution.
require_value() {
    [ -n "$2" ] || { err "$1 requires a value"; exit 1; }
    # "--identity --app=/x" would otherwise sign with the literal string "--app=/x".
    # No value this script takes can legitimately start with a dash.
    case "$2" in
        --*) err "$1 requires a value (got option $2)"; exit 1 ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --help) show_help; exit 0 ;;
        --version=*) VERSION="${1#*=}"; require_value --version "$VERSION" ;;
        --version) shift; VERSION="${1:-}"; require_value --version "$VERSION" ;;
        --arch=*) ARCH="${1#*=}"; require_value --arch "$ARCH" ;;
        --arch) shift; ARCH="${1:-}"; require_value --arch "$ARCH" ;;
        --identity=*) SIGNING_IDENTITY="${1#*=}"; require_value --identity "$SIGNING_IDENTITY" ;;
        --identity) shift; SIGNING_IDENTITY="${1:-}"; require_value --identity "$SIGNING_IDENTITY" ;;
        --app=*) APP_BUNDLE="${1#*=}"; require_value --app "$APP_BUNDLE" ;;
        --app) shift; APP_BUNDLE="${1:-}"; require_value --app "$APP_BUNDLE" ;;
        # Exit non-zero: a mistyped flag that printed help and reported success would
        # let a build script record an update that never happened.
        *) err "Unknown option: $1"; show_help >&2; exit 1 ;;
    esac
    shift
done

resolve_app_bundle
echo "Target app bundle: $APP_BUNDLE"

INSTALL_DIR="$APP_BUNDLE/Contents/Helpers"
PANDOC_BIN="$INSTALL_DIR/pandoc"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
COPYRIGHT_FILE="$RESOURCES_DIR/PANDOC-COPYRIGHT.txt"

# Runs on every exit path, including the error ones and a Ctrl-C partway through a
# 190 MB download, so no individual failure branch has to remember to clean up after
# itself. The WORK_DIR guard keeps an unset variable from turning this into an rm -rf
# on nothing useful.
#
# The staged binary is swept too: cp preserves the source's executable bit, so a
# signal landing between the cp and the mv would leave an executable pandoc.new in
# Contents/Helpers, and codesign_applet.sh signs and seals every executable file it
# finds under the bundle. That would ship a duplicate 190 MB binary.
cleanup_work_dir() {
    /bin/rm -f "$PANDOC_BIN.new" "$COPYRIGHT_FILE.new"
    [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] || return 0
    /bin/rm -rf "$WORK_DIR"
}
trap cleanup_work_dir EXIT

detect_arch() {
    if [ "$HOST_ARCH" = "arm64" ]; then
        ARCH="arm64"
    else
        ARCH="x86_64"
    fi
    echo "  Detected host architecture: $ARCH"
}

detect_latest_version() {
    echo "Detecting latest pandoc release..."

    # Strategy 1: follow the /releases/latest redirect to read the tag from the URL.
    # pandoc tags are bare version numbers with no leading "v".
    local redirect_url
    redirect_url=$(/usr/bin/curl -s --head -w '%{redirect_url}' --max-time 10 \
        "https://github.com/jgm/pandoc/releases/latest" 2>/dev/null || echo "")

    local tag
    tag=$(echo "$redirect_url" | /usr/bin/grep -oE '/tag/[0-9]+(\.[0-9]+)+$' | /usr/bin/sed 's|/tag/||')
    if [ -n "$tag" ]; then
        VERSION="$tag"
        echo "  Detected from redirect: $VERSION"
        return 0
    fi

    # Strategy 2: GitHub releases API JSON
    echo "  Trying GitHub releases API..."
    local api_json
    api_json=$(/usr/bin/curl -s --fail --max-time 10 \
        "https://api.github.com/repos/jgm/pandoc/releases/latest" 2>/dev/null || echo "")

    tag=$(echo "$api_json" | /usr/bin/grep -oE '"tag_name":[[:space:]]*"[0-9]+(\.[0-9]+)+"' \
        | /usr/bin/grep -oE '[0-9]+(\.[0-9]+)+')
    if [ -n "$tag" ]; then
        VERSION="$tag"
        echo "  Detected from API: $VERSION"
        return 0
    fi

    err "Version detection failed. Specify --version=X.Y.Z explicitly."
    exit 1
}

prepare() {
    echo
    echo "==== Preparing pandoc update ===="
    echo

    HOST_ARCH=$(/usr/bin/uname -m)

    if [ "$ARCH" = "auto" ]; then
        detect_arch
    fi

    case "$ARCH" in
        arm64|x86_64) ;;
        *) err "Invalid --arch: $ARCH (must be arm64 or x86_64)"; exit 1 ;;
    esac

    if [ "$VERSION" = "auto" ]; then
        detect_latest_version
    fi

    # Anchored, so no slashes, no "..", no spaces. VERSION is interpolated into both a
    # URL path and a filesystem path below; a glob-style check like [0-9]*.[0-9]* would
    # accept "1.0/../../someone/somerepo/main", which curl normalizes into a fetch from
    # an entirely different repo.
    if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
        err "Invalid --version: $VERSION (expected format: X.Y, X.Y.Z or X.Y.Z.W)"
        exit 1
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        /bin/mkdir -vp "$INSTALL_DIR"
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        err "Install directory not found and could not be created: $INSTALL_DIR"
        exit 1
    fi

    # Upstream asset names use the same arch spellings this script does.
    ASSET_NAME="pandoc-${VERSION}-${ARCH}-macOS.zip"
    DOWNLOAD_URL="https://github.com/jgm/pandoc/releases/download/${VERSION}/${ASSET_NAME}"

    WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/update-pandoc.XXXXXX")"
    # Without -e a failed mktemp leaves WORK_DIR empty, and every path derived from it
    # would then be rooted at "/".
    if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
        err "Could not create work directory under ${TMPDIR:-/tmp}"
        exit 1
    fi
    ZIPFILE="$WORK_DIR/$ASSET_NAME"
    EXTRACT_DIR="$WORK_DIR/extracted"

    # Read the installed version only when it can run here. Probing an x86_64 binary
    # from an arm64 host would invoke Rosetta, which on a machine without it raises a
    # system dialog from what is supposed to be a headless script.
    local current_version="none"
    if [ -x "$PANDOC_BIN" ]; then
        if [ "$(/usr/bin/lipo -archs "$PANDOC_BIN" 2>/dev/null)" = "$HOST_ARCH" ]; then
            current_version=$("$PANDOC_BIN" --version 2>/dev/null | /usr/bin/head -1 || echo "")
            [ -n "$current_version" ] || current_version="unreadable"
        else
            current_version="$(/usr/bin/lipo -archs "$PANDOC_BIN" 2>/dev/null) build (not run on $HOST_ARCH host)"
        fi
    fi

    echo
    echo "  Installed   : $current_version"
    echo "  Version     : $VERSION"
    echo "  Architecture: $ARCH"
    echo "  Asset       : $ASSET_NAME"
    echo "  Install dir : $INSTALL_DIR"
    echo "  Work dir    : $WORK_DIR"
    echo
}

download_release() {
    echo "==== Downloading pandoc $VERSION ($ARCH) ===="
    echo

    echo "  $DOWNLOAD_URL"
    /usr/bin/curl -L --fail --show-error --progress-bar -o "$ZIPFILE" "$DOWNLOAD_URL"
    local curl_result=$?
    if [ "$curl_result" != 0 ]; then
        err "Download failed (curl exit code: $curl_result)"
        err "Check that $VERSION is a real release tag with a macOS $ARCH zip."
        exit 1
    fi

    echo
    echo "  Saved: $ZIPFILE"
    echo
}

extract_and_install() {
    echo "==== Extracting archive ===="
    echo

    /bin/mkdir -p "$EXTRACT_DIR"
    # unzip verifies a CRC32 per entry, so a truncated or corrupted transfer fails here
    # and no separate checksum step is needed to catch a bad download.
    /usr/bin/unzip -q "$ZIPFILE" -d "$EXTRACT_DIR"
    local unzip_result=$?
    if [ "$unzip_result" != 0 ]; then
        err "Extraction failed (unzip exit $unzip_result)"
        exit 1
    fi

    # The archive lays out pandoc-<version>-<arch>/bin/pandoc, but find the real binary
    # rather than assuming that path: pandoc-lua and pandoc-server sit beside it as
    # 6-byte symlinks, so -type f keeps the search on the executable itself.
    local found_binary
    found_binary=$(/usr/bin/find "$EXTRACT_DIR" -type f -name "pandoc" 2>/dev/null | /usr/bin/head -1)
    if [ -z "$found_binary" ]; then
        err "pandoc binary not found in extracted archive"
        exit 1
    fi

    # That enclosing directory name is the only place the version appears in the
    # payload - pandoc stamps no version into the file name - so asserting the layout
    # is what ties the installed bytes to the release that was asked for. It is also
    # the only such check available on a cross-arch run, where the binary cannot be
    # executed to ask it directly.
    local rel="${found_binary#"$EXTRACT_DIR"/}"
    case "$rel" in
        "pandoc-$VERSION-$ARCH"/bin/pandoc) ;;
        *)
            err "Unexpected archive layout: $rel (expected pandoc-$VERSION-$ARCH/bin/pandoc)"
            exit 1
            ;;
    esac
    echo "  Found: $rel"

    # Confirm the archive really holds the arch we asked for, and only that one, before
    # it lands in the bundle. lipo -archs is exact where `file` is not: `file` names
    # every slice of a universal binary, so a substring test would accept a fat binary
    # as either arch and quietly defeat the per-arch build this script exists to serve.
    local bin_archs
    bin_archs=$(/usr/bin/lipo -archs "$found_binary" 2>/dev/null)
    if [ "$bin_archs" != "$ARCH" ]; then
        err "Archive binary is [$bin_archs], expected exactly [$ARCH]"
        exit 1
    fi
    echo "  Arch : $bin_archs"
    echo

    echo "==== Installing into $INSTALL_DIR ===="
    echo

    # Copy to a sibling and rename. cp writes progressively into the destination, so
    # copying straight onto $PANDOC_BIN would expose a truncated binary to anything
    # reading it, and a cp that fails partway would leave the bundle with no pandoc at
    # all. mv on the same filesystem is atomic, so the bundle holds either the old
    # binary or the complete new one.
    local staged="$PANDOC_BIN.new"
    /bin/rm -f "$staged"
    /bin/cp "$found_binary" "$staged"
    local cp_result=$?
    if [ "$cp_result" != 0 ]; then
        err "Failed to copy pandoc into $INSTALL_DIR (cp exit $cp_result)"
        /bin/rm -f "$staged"
        exit 1
    fi

    /bin/chmod +x "$staged"
    local chmod_result=$?
    if [ "$chmod_result" != 0 ]; then
        err "Failed to make pandoc executable (chmod exit $chmod_result)"
        /bin/rm -f "$staged"
        exit 1
    fi

    /bin/mv -f "$staged" "$PANDOC_BIN"
    local mv_result=$?
    if [ "$mv_result" != 0 ]; then
        err "Failed to move pandoc into place (mv exit $mv_result)"
        /bin/rm -f "$staged"
        exit 1
    fi

    echo "  pandoc ($(/usr/bin/du -h "$PANDOC_BIN" | /usr/bin/cut -f1))"
    echo
}

# Refreshes the bundled COPYRIGHT text from the same tag we installed. The GPL-2 text
# in PANDOC-LICENSE-GPL-2.0.txt is not touched: it is the canonical FSF plain-text
# license and never changes, while upstream's COPYING.md is a markdown rewrap of it.
update_copyright() {
    echo "==== Updating pandoc COPYRIGHT ===="
    echo

    if [ ! -d "$RESOURCES_DIR" ]; then
        err "Resources directory not found: $RESOURCES_DIR"
        COPYRIGHT_STATUS="download-failed"
        return 1
    fi

    local url="https://raw.githubusercontent.com/jgm/pandoc/${VERSION}/COPYRIGHT"
    local fetched="$WORK_DIR/COPYRIGHT"

    echo "  $url"
    /usr/bin/curl -sL --fail --show-error --max-time 30 -o "$fetched" "$url"
    local curl_result=$?
    if [ "$curl_result" != 0 ]; then
        err "  Download failed (curl exit $curl_result) - keeping existing $(/usr/bin/basename "$COPYRIGHT_FILE")"
        COPYRIGHT_STATUS="download-failed"
        return 1
    fi

    # Sanity-check the payload before it overwrites a license file. Size matters as
    # much as content here: the real file is around 9.5 KB, so a short body that
    # happens to mention pandoc must not be allowed to replace it.
    local fetched_size
    fetched_size=$(/usr/bin/wc -c < "$fetched")
    if [ "${fetched_size:-0}" -lt 2000 ] \
        || ! /usr/bin/head -1 "$fetched" | /usr/bin/grep -qi "pandoc" \
        || ! /usr/bin/grep -q "John MacFarlane" "$fetched"; then
        err "  Downloaded file does not look like the pandoc COPYRIGHT - keeping existing"
        COPYRIGHT_STATUS="download-failed"
        return 1
    fi

    if [ -f "$COPYRIGHT_FILE" ] && /usr/bin/cmp -s "$fetched" "$COPYRIGHT_FILE"; then
        echo "  ${GREEN}Already up to date${RESET}"
        COPYRIGHT_STATUS="unchanged"
        echo
        return 0
    fi

    # Staged the same way as the binary, and for a stronger reason: unlike
    # Contents/Helpers, this file is tracked in git, so a torn write leaves a
    # truncated license in the working tree with nothing to restore it from.
    /bin/cp "$fetched" "$COPYRIGHT_FILE.new"
    local cp_result=$?
    if [ "$cp_result" != 0 ]; then
        err "  Failed to write $COPYRIGHT_FILE (cp exit $cp_result)"
        /bin/rm -f "$COPYRIGHT_FILE.new"
        COPYRIGHT_STATUS="download-failed"
        return 1
    fi
    /bin/mv -f "$COPYRIGHT_FILE.new" "$COPYRIGHT_FILE"
    local mv_result=$?
    if [ "$mv_result" != 0 ]; then
        err "  Failed to move $COPYRIGHT_FILE into place (mv exit $mv_result)"
        /bin/rm -f "$COPYRIGHT_FILE.new"
        COPYRIGHT_STATUS="download-failed"
        return 1
    fi
    echo "  ${GREEN}Updated $(/usr/bin/basename "$COPYRIGHT_FILE")${RESET}"
    COPYRIGHT_STATUS="ok"
    echo
}

codesign_app() {
    echo "==== Codesigning app bundle ===="
    echo

    local codesign_script="$SCRIPT_DIR/codesign_applet.sh"
    if [ ! -f "$codesign_script" ]; then
        err "codesign_applet.sh not found at $codesign_script"
        exit 1
    fi

    # codesign_applet.sh discovers entitlements in precedence order: the target
    # bundle's own sibling OMCApplet.entitlements, then the first *.entitlements of
    # any name beside the target, then this script's own directory. Only the middle
    # rung is a hazard - for an --app target elsewhere it hands the signature an
    # unrelated neighbor's file. So pin this repo's file only when the target has no
    # OMCApplet.entitlements of its own, which leaves a target applet's own
    # entitlements winning and makes this a no-op for the default run. (Ad-hoc
    # signing clears entitlements outright; this matters once a real Developer ID is
    # passed.) The grep is a capability probe: these scripts get copied between applet
    # repos and older copies take the unknown flag as the bundle path.
    # Canonicalize first: codesign_applet.sh runs the bundle path through realpath
    # before taking its dirname, so probing the raw path would look at a different
    # directory whenever the last component is a symlink - and then pin over the
    # target's real sibling file, which is the exact outcome this branch avoids.
    local resolved
    resolved=$(/bin/realpath "$APP_BUNDLE" 2>/dev/null) || resolved=""
    [ -n "$resolved" ] || resolved="$APP_BUNDLE"
    local app_dir
    app_dir="$(/usr/bin/dirname "$resolved")"
    local entitlements="$SCRIPT_DIR/OMCApplet.entitlements"
    local result
    # The capability grep is anchored to the parser's case label, not to any mention:
    # usage text and comments name the flag too, and matching those would claim a
    # capability a copy documents but does not implement.
    if [ ! -f "$app_dir/OMCApplet.entitlements" ] && [ -f "$entitlements" ] \
        && /usr/bin/grep -qE -- '^[[:space:]]*--no-entitlements-search\)' "$codesign_script"; then
        "$codesign_script" --no-entitlements-search "$APP_BUNDLE" "$SIGNING_IDENTITY" "$entitlements"
        result=$?
    else
        "$codesign_script" "$APP_BUNDLE" "$SIGNING_IDENTITY"
        result=$?
    fi
    if [ "$result" != 0 ]; then
        err "Codesigning failed (exit $result)"
        exit 1
    fi
    echo
}

verify_install() {
    echo "==== Verifying installation ===="
    echo

    if [ ! -f "$PANDOC_BIN" ]; then
        err "pandoc missing after install"
        exit 1
    fi

    local bin_archs
    bin_archs=$(/usr/bin/lipo -archs "$PANDOC_BIN" 2>/dev/null)
    echo "  Binary: $bin_archs, $(/usr/bin/du -h "$PANDOC_BIN" | /usr/bin/cut -f1)"
    if [ "$bin_archs" != "$ARCH" ]; then
        err "Installed binary is [$bin_archs], expected exactly [$ARCH]"
        exit 1
    fi

    # A cross-arch install cannot be exercised here: an arm64 binary will not run on
    # an Intel host at all, and an x86_64 binary needs Rosetta on Apple silicon, whose
    # absence would look like a broken download. The version is still pinned - by the
    # archive layout check in extract_and_install - so what is skipped is the run test,
    # not the identity of what was installed.
    if [ "$ARCH" != "$HOST_ARCH" ]; then
        echo "  ${GREEN}Arch OK${RESET} (built for $ARCH on a $HOST_ARCH host - skipping run test)"
        VERIFY_STATUS="arch-only"
        echo
        return 0
    fi

    local version_out
    version_out=$("$PANDOC_BIN" --version 2>&1 | /usr/bin/head -1)
    if [ -z "$version_out" ]; then
        err "pandoc --version produced no output"
        exit 1
    fi
    echo "  Version: $version_out"

    case "$version_out" in
        *"$VERSION"*) ;;
        *) err "Version string does not mention $VERSION"; exit 1 ;;
    esac

    # Smoke-test the conversion path the app actually drives, not just --version:
    # a Lua/data-file problem shows up here and nowhere else.
    echo "  Running markdown -> html smoke test..."
    local smoke_out
    smoke_out=$(printf '# Title\n\nHello.\n' | "$PANDOC_BIN" --from=markdown --to=html 2>&1)
    local smoke_result=$?
    if [ "$smoke_result" != 0 ] || [ -z "$smoke_out" ]; then
        err "Conversion smoke test failed (exit $smoke_result): $smoke_out"
        exit 1
    fi
    case "$smoke_out" in
        *"<h1"*) ;;
        *) err "Unexpected conversion output: $smoke_out"; exit 1 ;;
    esac

    echo "  ${GREEN}OK${RESET}"
    VERIFY_STATUS="ok"
    echo
}

# The README advertises the bundled version in prose, so it goes stale silently.
# Flag the mismatch instead of editing it - the wording around it is a human's call.
# A README that states a prefix of the installed version ("pandoc 3.10" against
# 3.10.2) is deliberately accepted: upstream's patch component moves often and the
# README is written at major.minor granularity.
check_readme_version() {
    local readme="$SCRIPT_DIR/README.md"
    [ -f "$readme" ] || return 0

    # Take the numeric field rather than stripping the word: the grep is
    # case-insensitive, so any strip pattern would have to enumerate the casings and
    # would silently pass "PANDOC 3.10" through into the message.
    local stated
    stated=$(/usr/bin/grep -oEi 'pandoc [0-9]+(\.[0-9]+)*' "$readme" | /usr/bin/head -1 \
        | /usr/bin/awk '{print $2}')
    [ -n "$stated" ] || return 0

    case "$VERSION" in
        "$stated"|"$stated".*) return 0 ;;
    esac

    err "  README.md still advertises pandoc $stated - update it to $VERSION"
}

print_summary() {
    echo "==== Update complete ===="
    echo
    echo "  pandoc $VERSION ($ARCH) installed to:"
    echo "  $PANDOC_BIN"
    if [ "$VERIFY_STATUS" = "arch-only" ]; then
        echo "  ${GREEN}Arch and version verified${RESET} - not run (cross-arch build)"
    else
        echo "  ${GREEN}Verified${RESET}"
    fi
    echo
    echo "  COPYRIGHT:"
    case "$COPYRIGHT_STATUS" in
        ok)              echo "  ${GREEN}Refreshed from tag $VERSION${RESET}" ;;
        unchanged)       echo "  ${GREEN}Already current${RESET}" ;;
        download-failed) err "  Not updated - check $COPYRIGHT_FILE by hand" ;;
        *)               echo "  Not updated" ;;
    esac
    echo
    check_readme_version
    echo
}

main() {
    prepare
    download_release
    extract_and_install
    update_copyright
    codesign_app
    verify_install
    print_summary

    # A new binary sitting next to the previous version's COPYRIGHT is a license
    # mismatch in a bundle that gets distributed, so it must not read as a clean run
    # to a caller that only checks the exit status. Distinct from 1, which means
    # nothing was installed at all.
    [ "$COPYRIGHT_STATUS" = "download-failed" ] && exit 2
    exit 0
}

main
