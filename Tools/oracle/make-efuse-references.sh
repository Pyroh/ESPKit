#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Références espefuse (boîte noire, lecture seule) pour ESPEfuse.
#
#   ESPEFUSE=espefuse ./make-efuse-references.sh <sortie> [<puce> <port>]…
#
# Sans carte : <sortie>/virt/<puce>.json pour toutes les puces (espefuse --virt), qui servent de
# libellés au générateur. Avec des cartes : summary-<puce>.json et dump-<puce>.txt, comparés par
# les tests (ESPKIT_EFUSE_REFERENCES=<sortie>), et <sortie>/real/<puce>.json pour le générateur.
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
echo "références dans $out"
echo "puis : python3 -I Tools/efuse-codegen/generate.py <esp-idf>/components/efuse $out/real $out/virt"
