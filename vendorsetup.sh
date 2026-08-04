#!/bin/bash
# Fetches the prebuilt APKs referenced by each module's Android.mk from upstream releases,
# so no binaries are tracked in this repo.
#
# Auto-sourced by build/envsetup.sh (source_vendorsetup); also runnable directly:
#   ./vendorsetup.sh [--force]
# Only fetches when WITH_GMS=true (set PARTNER_GMS_FETCH=always to override).
# PARTNER_GMS_FORCE=true re-fetches. GITHUB_TOKEN is used if set (anonymous API allows
# 60 requests/hour).
#
# Every download must match the pinned signing certificate below. For the microG trio this
# is functional, not just defensive: frameworks/base 0036-Unprivileged_microG_Handling only
# spoofs signatures for APKs whose cert SHA-256 matches exactly, so a wrong-key APK would
# install and silently do nothing.

_pgms_dir() { (cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); }

# $1 owner/repo, $2 ERE the asset filename must match
_pgms_github_url() {
    local -a auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl -sfL "${auth[@]}" "https://api.github.com/repos/$1/releases/latest" \
        | grep '"browser_download_url"' | cut -d'"' -f4 \
        | grep -E "/$2$" | head -1
}

# $1 gitlab host, $2 project id, $3 ERE the filename must match.
# The APKs are markdown links in the release description, not API assets, and the upload
# host is not guaranteed, so take whatever URL the description names.
_pgms_gitlab_url() {
    curl -sfL "$1/api/v4/projects/$2/releases?per_page=1" \
        | python3 -c '
import json, re, sys
host, pid, pattern = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    rel = json.load(sys.stdin)[0]
except (ValueError, IndexError):
    sys.exit(0)
for url in re.findall(r"\]\(([^)\s]+\.apk)\)", rel.get("description", "")):
    if re.search(pattern + "$", url):
        print(url if url.startswith("http") else "%s/-/project/%s%s" % (host, pid, url))
        break
' "$1" "$2" "$3"
}

# $1 module dir, $2 pinned cert sha256, $3 resolved url
_pgms_install() {
    local name="$1" pin="$2" url="$3"
    local dest hash
    dest="$(_pgms_dir)/${name}/${name}.apk"

    if [ -z "${url}" ]; then
        echo "ERROR: partner_gms: could not resolve a download URL for ${name}" >&2
        return 1
    fi
    echo "partner_gms: ${name} <- ${url}"
    if ! curl -sfL --retry 3 --output "${dest}.tmp" "${url}"; then
        echo "ERROR: partner_gms: download failed for ${name}" >&2
        rm -f "${dest}.tmp"
        return 1
    fi

    hash="$(python3 "$(_pgms_dir)/apk_cert_sha256.py" "${dest}.tmp" 2>/dev/null)"
    if [ "${hash}" != "${pin}" ]; then
        rm -f "${dest}.tmp"
        echo "ERROR: partner_gms: ${name} signing cert mismatch, discarded" >&2
        echo "       expected ${pin}" >&2
        echo "       got      ${hash:-<none>}" >&2
        return 1
    fi

    mv "${dest}.tmp" "${dest}"
}

# $1 module, $2 pin, $3 source spec ("gh <repo>" or "gl <host> <id>"), $4 filename ERE
_pgms_fetch() {
    local name="$1" pin="$2" kind="$3"
    if [ -f "$(_pgms_dir)/${name}/${name}.apk" ] && [ "${PARTNER_GMS_FORCE:-false}" != "true" ]; then
        return 0
    fi
    case "${kind}" in
        gh) _pgms_install "${name}" "${pin}" "$(_pgms_github_url "$4" "$5")" ;;
        gl) _pgms_install "${name}" "${pin}" "$(_pgms_gitlab_url "$4" "$5" "$6")" ;;
        *)  echo "ERROR: partner_gms: unknown source '${kind}'" >&2; return 1 ;;
    esac
}

_pgms_main() {
    if [ "${WITH_GMS:-false}" != "true" ] && [ "${PARTNER_GMS_FETCH:-}" != "always" ]; then
        echo "partner_gms: WITH_GMS is not true, skipping APK fetch"
        return 0
    fi

    # Signing key of official microG releases; must equal MICROG_HASH in
    # frameworks/base AppsFilterImpl / ComputerEngine.
    local microg="9BD06727E62796C0130EB6DAB39B73157451582CBD138E86C468ACC395D14165"
    local rc=0

    # microG releases also carry -hw (Huawei) variants, an org.microg.gms user build and
    # .asc signatures; match the plain <id>-<versioncode>.apk only.
    _pgms_fetch GmsCore   "${microg}" gh microg/GmsCore \
        'com\.google\.android\.gms-[0-9]+\.apk'                                     || rc=1
    _pgms_fetch FakeStore "${microg}" gh microg/GmsCore \
        'com\.android\.vending-[0-9]+\.apk'                                         || rc=1
    _pgms_fetch GsfProxy  "${microg}" gh microg/android_packages_apps_GsfProxy \
        'GsfProxy\.apk'                                                             || rc=1
    _pgms_fetch Obtainium \
        "B353601F6A1D5FD6603AE2F50BE80CF301367B86B6AB8B1F66243DA96CD57362" \
        gh ImranR98/Obtainium 'app-arm64-v8a-release\.apk'                          || rc=1
    # Upstream asset is currently misspelled "PdfViwer-<v>.apk".
    _pgms_fetch PdfViewer \
        "EEA4B37D46E361CE2583E1F59859DB9E784D456425FF40FE6CF75D90F6A968E0" \
        gh GrapheneOS/PdfViewer 'Pdf[A-Za-z]*-[0-9]+\.apk'                          || rc=1
    # AuroraStore ships on GitLab; -hw and -preload variants are not wanted.
    _pgms_fetch AuroraStore \
        "4C626157AD02BDA3401A7263555F68A79663FC3E13A4D4369A12570941AA280F" \
        gl https://gitlab.com 6922885 'AuroraStore-[0-9][0-9.]*\.apk'               || rc=1

    [ "${rc}" -ne 0 ] && echo "ERROR: partner_gms: APKs missing; the build will fail" >&2
    return "${rc}"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ "${1:-}" = "--force" ] && PARTNER_GMS_FORCE=true
    _pgms_main
    exit $?
else
    _pgms_main || true
fi
