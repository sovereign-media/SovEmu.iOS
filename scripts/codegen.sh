#!/bin/sh
# Regenerates Packages/SovEmuKit/Sources/SovEmuKit/Generated from the GraphQL documents and the
# vendored schema (Packages/SovEmuKit/Sources/SovEmuKit/GraphQL).
#
# The CLI is downloaded at the exact version Package.swift pins the Apollo library to, because
# generated code is only guaranteed to compile against the library release that wrote it. Run it
# after any change to a .graphql document or to schema.graphqls, and commit the result: codegen
# validates every document against the schema, so a failure here is the check working.
#
# --check regenerates and fails if the committed files differ (CI).
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/.*apollo-ios\.git", exact: "\([0-9.]*\)".*/\1/p' Packages/SovEmuKit/Package.swift)
[ -n "$version" ] || { echo "codegen: could not read the Apollo version from Package.swift" >&2; exit 1; }

cli_dir=".build/apollo-ios-cli/$version"
if [ ! -x "$cli_dir/apollo-ios-cli" ]; then
    mkdir -p "$cli_dir"
    echo "codegen: fetching apollo-ios-cli $version"
    curl -fsSL "https://github.com/apollographql/apollo-ios/releases/download/$version/apollo-ios-cli.tar.gz" \
        | tar xz -C "$cli_dir"
fi

"$cli_dir/apollo-ios-cli" generate --path apollo-codegen-config.json

generated=Packages/SovEmuKit/Sources/SovEmuKit/Generated
if [ "${1:-}" = "--check" ]; then
    if [ -n "$(git status --porcelain -- "$generated")" ]; then
        git status --short -- "$generated" >&2
        echo "codegen: $generated is out of date; run scripts/codegen.sh and commit the result" >&2
        exit 1
    fi
fi
echo "codegen: $generated is up to date"
