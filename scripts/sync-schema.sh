#!/bin/sh
# Copies SovEmu's GraphQL schema into this repository, then regenerates the Swift from it.
#
# The schema lives in SovEmu (SovEmu.Backend/SovEmu.Server/schema.graphql, kept current by a
# server test). This repository keeps a copy so it builds on its own, as SovEmu.Android does
# (`./gradlew :common:core:syncSchema`). Run it when the server's schema changes; by default it reads the
# parent checkout this repository is a submodule of, or the path given.
set -eu
cd "$(dirname "$0")/.."

source="${1:-../SovEmu.Backend/SovEmu.Server/schema.graphql}"
[ -f "$source" ] || { echo "sync-schema: no schema at $source (pass its path)" >&2; exit 1; }

cp "$source" Packages/SovEmuKit/Sources/SovEmuKit/GraphQL/schema.graphqls
echo "sync-schema: copied $source"
exec scripts/codegen.sh
