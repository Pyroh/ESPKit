#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds the DocC documentation: one archive, one entry point. No package plugin needed: the
# symbol graph comes from `swift package dump-symbol-graph`.
#
#   Tools/build-docs.sh [output folder]          # default: .build/documentation
#
# The ESPKit umbrella re-exports every module, so the documentation presents them as one module:
# each module's symbol graph is relabelled ESPKit (macOS would emit the re-exported symbols in
# ESPKit's own graph, Linux does not), and Sources/ESPKit/ESPKit.docc curates them by topic.
# Output: ESPKit.doccarchive. Preview with `xcrun docc preview Sources/ESPKit/ESPKit.docc
# --additional-symbol-graph-dir <output>/graphs`. DOCC overrides the docc command;
# WARNINGS_AS_ERRORS=1 fails on the first warning; DOCC_FLAGS adds options to `docc convert`.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/.build/documentation}
if [ -n "${DOCC:-}" ]; then docc=($DOCC)
elif command -v xcrun > /dev/null; then docc=(xcrun docc)
else docc=(docc); fi
strict=()
[ "${WARNINGS_AS_ERRORS:-0}" = 1 ] && strict=(--warnings-as-errors)

# On Linux the command can exit non-zero after writing every graph: judge by the files.
graphs=$( (swift package --package-path "$root" dump-symbol-graph --minimum-access-level public 2>&1 || true) \
    | sed -n 's/^Files written to //p' | tail -1)
[ -d "$graphs" ] || { echo "no symbol graphs" >&2; exit 1; }

rm -rf "${out:?}"
mkdir -p "$out/graphs"
for module in ESPTargets ESPTransport ESPImage ESPSecure ESPDevice ESPEfuse; do
    for graph in "$graphs/$module".symbols.json "$graphs/$module"@*.symbols.json; do
        [ -f "$graph" ] || continue
        sed "s/\"module\":{\"name\":\"$module\"/\"module\":{\"name\":\"ESPKit\"/" "$graph" \
            > "$out/graphs/$(basename "$graph")"
    done
done
"${docc[@]}" convert "$root/Sources/ESPKit/ESPKit.docc" \
    --fallback-display-name ESPKit --fallback-bundle-identifier espkit \
    --additional-symbol-graph-dir "$out/graphs" \
    --enable-inherited-docs ${strict[@]+"${strict[@]}"} \
    ${DOCC_FLAGS:-} --output-path "$out/ESPKit.doccarchive"
echo "documentation in $out/ESPKit.doccarchive"
