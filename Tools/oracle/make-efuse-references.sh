#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# espefuse references (black box, read only) for ESPEfuse.
#
#   ESPEFUSE=espefuse ./make-efuse-references.sh <output> [<chip> <port>]…
#
# Without a board: <output>/virt/<chip>.json for every chip (espefuse --virt), used as labels
# by the generator. With boards: summary-<chip>.json and dump-<chip>.txt, compared by
# the tests (ESPKIT_EFUSE_REFERENCES=<output>), and <output>/real/<chip>.json for the generator.
set -euo pipefail

ESPEFUSE=${ESPEFUSE:-espefuse}
out=$1; shift
mkdir -p "$out/virt" "$out/real"
for chip in esp32 esp32s2 esp32s3 esp32c2 esp32c3 esp32c5 esp32c6 esp32c61 esp32h2 esp32h21 esp32h4 esp32p4; do
    $ESPEFUSE --virt --chip $chip summary --format json --file "$out/virt/$chip.json" > /dev/null
done
while [ $# -ge 2 ]; do
    chip=$1; port=$2; shift 2
    $ESPEFUSE --port "$port" --chip $chip summary --format json --file "$out/summary-$chip.json" > /dev/null
    $ESPEFUSE --port "$port" --chip $chip dump > "$out/dump-$chip.txt"
    cp "$out/summary-$chip.json" "$out/real/$chip.json"
done
echo "references in $out"
echo "then: python3 -I Tools/efuse-codegen/generate.py <esp-idf>/components/efuse $out/real $out/virt"
