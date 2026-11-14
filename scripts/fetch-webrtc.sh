#!/usr/bin/env bash
# Downloads the pinned WebRTC xcframework (stasel/WebRTC, Google's libwebrtc built for Apple
# platforms) into Packages/WebRTC, where a local Swift package wraps it as a binary target.
#
# A local package rather than a remote one: the bytes are pinned by SHA-256 here, and builds do
# not depend on Xcode's package fetcher (which hangs on some machines). Run after a clone, and
# again when VERSION changes. The framework itself is gitignored.
set -euo pipefail

VERSION=157.0.0
MILESTONE=M157
SHA256=ffb1221be2138ecc6bc92300ae4f0157e18694d652db9921e4251992ea91a328

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Packages/WebRTC"
stamp="$dest/WebRTC.xcframework/.version"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$VERSION" ]; then
  echo "WebRTC $VERSION already present"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
url="https://github.com/stasel/WebRTC/releases/download/$VERSION/WebRTC-$MILESTONE.xcframework.zip"
echo "fetching $url"
curl --fail --silent --show-error --location -o "$tmp/webrtc.zip" "$url"
got="$(shasum -a 256 "$tmp/webrtc.zip" | cut -d' ' -f1)"
[ "$got" = "$SHA256" ] || { echo "checksum mismatch: $got" >&2; exit 1; }

rm -rf "$dest/WebRTC.xcframework"
unzip -q "$tmp/webrtc.zip" -d "$tmp/out"
mv "$tmp/out/WebRTC.xcframework" "$dest/"
echo "$VERSION" > "$stamp"
echo "WebRTC $VERSION ready"
