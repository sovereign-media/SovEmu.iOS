#!/usr/bin/env bash
# Downloads the pinned WebRTC xcframework (LiveKit's build of Google's libwebrtc for Apple
# platforms, livekit/webrtc-xcframework, the one with tvOS slices) into Packages/WebRTC, where a
# local Swift package wraps it and re-exports it under WebRTC's own names.
#
# A local package rather than a remote one: the bytes are pinned by SHA-256 here, and builds do
# not depend on Xcode's package fetcher (which hangs on some machines). Run after a clone, and
# again when VERSION changes. The framework itself is gitignored.
set -euo pipefail

VERSION=150.7871.09
SHA256=4ce3ba4041b94128c8e8bf7b2bc0ad9371af61dc65588b8023f4562db5c3c653

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Packages/WebRTC"
stamp="$dest/LiveKitWebRTC.xcframework/.version"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$VERSION" ]; then
  echo "WebRTC $VERSION already present"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
url="https://github.com/livekit/webrtc-xcframework/releases/download/$VERSION/LiveKitWebRTC.xcframework.zip"
echo "fetching $url"
curl --fail --silent --show-error --location -o "$tmp/webrtc.zip" "$url"
got="$(shasum -a 256 "$tmp/webrtc.zip" | cut -d' ' -f1)"
[ "$got" = "$SHA256" ] || { echo "checksum mismatch: $got" >&2; exit 1; }

rm -rf "$dest/WebRTC.xcframework" "$dest/LiveKitWebRTC.xcframework"
unzip -q "$tmp/webrtc.zip" -d "$tmp/out"
mv "$tmp/out/LiveKitWebRTC.xcframework" "$dest/"
echo "$VERSION" > "$stamp"
echo "WebRTC $VERSION ready"
