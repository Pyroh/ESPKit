#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds the DocC documentation of every public module, then merges the archives into one.
# No package plugin needed: the symbol graphs come from `swift package dump-symbol-graph`.
#
#   Tools/build-docs.sh [output folder]          # default: .build/documentation
#
# Output: one <Module>.doccarchive per module and ESPKitDocumentation.doccarchive (all merged).
# Preview a module with `xcrun docc preview Sources/ESPDevice/ESPDevice.docc
# --additional-symbol-graph-dir <output>/graphs/ESPDevice`. DOCC overrides the docc command;
# WARNINGS_AS_ERRORS=1 fails on the first warning.
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
archives=()
for module in ESPTargets ESPTransport ESPImage ESPSecure ESPDevice ESPEfuse; do
    mkdir -p "$out/graphs/$module"
    cp "$graphs/$module.symbols.json" "$out/graphs/$module/"
    cp "$graphs/$module"@*.symbols.json "$out/graphs/$module/" 2> /dev/null || true
    "${docc[@]}" convert "$root/Sources/$module/$module.docc" \
        --fallback-display-name "$module" --fallback-bundle-identifier "espkit.$module" \
        --additional-symbol-graph-dir "$out/graphs/$module" \
        --enable-inherited-docs ${strict[@]+"${strict[@]}"} \
        --output-path "$out/$module.doccarchive"
    archives+=("$out/$module.doccarchive")
done
# The umbrella re-exports every module: its own graph would duplicate them all, uncurated.
# Its catalog is a technology root holding the guides.
"${docc[@]}" convert "$root/Sources/ESPKit/ESPKit.docc" \
    --fallback-display-name ESPKit --fallback-bundle-identifier espkit.ESPKit \
    ${strict[@]+"${strict[@]}"} --output-path "$out/ESPKit.doccarchive"
archives=("$out/ESPKit.doccarchive" "${archives[@]}")
"${docc[@]}" merge "${archives[@]}" --synthesized-landing-page-name ESPKit \
    --output-path "$out/ESPKitDocumentation.doccarchive"
echo "documentation in $out"
