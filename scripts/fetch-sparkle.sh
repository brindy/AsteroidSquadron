#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

sparkle_version="2.10.0"
sparkle_sha256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
sparkle_cache="${SPARKLE_CACHE_DIR:-$PWD/.cache/sparkle}"
sparkle_cache="${sparkle_cache:A}"
sparkle_dir="$sparkle_cache/$sparkle_version"
sparkle_archive="$sparkle_cache/downloads/Sparkle-$sparkle_version.tar.xz"
mkdir -p "$sparkle_cache/downloads"

download_temp=""
extract_temp=""
cleanup_sparkle() {
    [[ -z "$download_temp" ]] || rm -f "$download_temp"
    [[ -z "$extract_temp" ]] || rm -rf "$extract_temp"
}
trap cleanup_sparkle EXIT

archive_matches() {
    [[ -f "$sparkle_archive" && "$(shasum -a 256 "$sparkle_archive" | awk '{ print $1 }')" == "$sparkle_sha256" ]]
}

if ! archive_matches; then
    download_temp="$(mktemp "$sparkle_cache/downloads/.download.XXXXXX")"
    curl --fail --location --silent --show-error --retry 2 --proto '=https' --tlsv1.2 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
        --output "$download_temp"
    [[ "$(shasum -a 256 "$download_temp" | awk '{ print $1 }')" == "$sparkle_sha256" ]] || {
        print -u2 'The Sparkle download did not match its pinned SHA-256.'
        exit 1
    }
    mv "$download_temp" "$sparkle_archive"
    download_temp=""
fi

if [[ ! -f "$sparkle_dir/.distribution-sha256" || "$(< "$sparkle_dir/.distribution-sha256")" != "$sparkle_sha256" || \
      ! -x "$sparkle_dir/bin/sign_update" || ! -f "$sparkle_dir/Sparkle.framework/Versions/B/Sparkle" ]]; then
    extract_temp="$(mktemp -d "$sparkle_cache/.extract.XXXXXX")"
    tar -xf "$sparkle_archive" -C "$extract_temp"
    print -r -- "$sparkle_sha256" > "$extract_temp/.distribution-sha256"
    if [[ -d "$sparkle_dir" ]]; then rm -rf "$sparkle_dir"; fi
    mv "$extract_temp" "$sparkle_dir"
    extract_temp=""
fi

print -r -- "$sparkle_dir"
