#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Produit les binaires de référence d'esptool (boîte noire) pour les tests différentiels d'ESPImage.
# esptool n'est jamais lu ni recopié : on compare seulement ses sorties à celles d'ESPKit.
#
#   ESPTOOL="esptool" ./make-references.sh <sortie> <dossier ELF ESP-IDF> <dossier ELF Arduino> <dossier ELF ESP8266>
#
# Chaque dossier contient un sous-dossier par puce (esp32, esp32s3 ; esp8266), avec firmware.elf
# et, pour ESP-IDF, bootloader.elf, bootloader.bin et partitions.bin. La sortie reçoit un fichier
# par cas et un manifeste `cases.tsv` : nom, puce, ELF, arguments.
set -euo pipefail

ESPTOOL=${ESPTOOL:-esptool}
out=$1; idf=$2; arduino=$3; esp8266=$4
mkdir -p "$out"
manifest="$out/cases.tsv"
: > "$manifest"

elf2image() {   # nom puce elf arguments…
    local name=$1 chip=$2 elf=$3; shift 3
    $ESPTOOL --chip "$chip" elf2image "$@" -o "$out/$name.bin" "$elf" > "$out/$name.log" 2>&1
    printf '%s\t%s\t%s\t%s\n' "$name" "$chip" "$elf" "$*" >> "$manifest"
}

for chip in esp32 esp32s3; do
    freq=40m; [ $chip = esp32s3 ] && freq=80m
    size=4MB; [ $chip = esp32s3 ] && size=8MB
    maxrev=399; [ $chip = esp32s3 ] && maxrev=99
    app=$idf/$chip/firmware.elf
    elf2image idf-$chip-app $chip "$app" --flash_mode dio --flash_freq $freq --flash_size $size --elf-sha256-offset 0xb0
    elf2image idf-$chip-boot $chip "$idf/$chip/bootloader.elf" --flash_mode dio --flash_freq $freq --flash_size 2MB --min-rev-full 0 --max-rev-full $maxrev
    elf2image idf-$chip-nodigest $chip "$app" --flash_mode qio --flash_freq $freq --flash_size $size --dont-append-digest
    elf2image idf-$chip-securepad2 $chip "$app" --flash_mode dio --flash_freq $freq --flash_size $size --secure-pad-v2
    elf2image idf-$chip-segments $chip "$app" --flash_mode dio --flash_freq $freq --flash_size $size --use_segments
    elf2image idf-$chip-padded $chip "$app" --flash_mode dout --flash_freq 20m --flash_size 16MB --pad-to-size 1MB
    elf2image arduino-$chip-app $chip "$arduino/$chip/firmware.elf" --flash_mode dio --flash_freq $freq --flash_size $size --elf-sha256-offset 0xb0
done

# ESP8266 : v1 (deux fichiers) et v2.
$ESPTOOL --chip esp8266 elf2image --version 1 -o "$out/esp8266-v1-" "$esp8266/esp8266/firmware.elf" > "$out/esp8266-v1.log" 2>&1
printf '%s\t%s\t%s\t%s\n' esp8266-v1 esp8266 "$esp8266/esp8266/firmware.elf" "--version 1" >> "$manifest"
elf2image esp8266-v2 esp8266 "$esp8266/esp8266/firmware.elf" --version 2 --flash_mode dio --flash_freq 40m --flash_size 4MB

# merge-bin : bootloader, partitions et application ESP-IDF.
for chip in esp32 esp32s3; do
    boot=0x1000; [ $chip = esp32s3 ] && boot=0x0
    files=("$boot" "$idf/$chip/bootloader.bin" 0x8000 "$idf/$chip/partitions.bin" 0x10000 "$idf/$chip/firmware.bin")
    for format in raw hex uf2; do
        $ESPTOOL --chip $chip merge_bin --format $format -o "$out/merge-$chip.$format" "${files[@]}" > "$out/merge-$chip-$format.log" 2>&1 || true
    done
done
# Patch d'en-tête, offset cible et remplissage (--fill-flash-size avant esptool 5).
fill=--pad-to-size; $ESPTOOL version 2>/dev/null | grep -q "v\?4\." && fill=--fill-flash-size
$ESPTOOL --chip esp32 merge_bin --format raw --flash_mode qio --flash_freq 80m --flash_size 16MB \
    --target-offset 0x1000 $fill 4MB -o "$out/merge-esp32-patched.raw" \
    0x1000 "$idf/esp32/bootloader.bin" 0x8000 "$idf/esp32/partitions.bin" 0x10000 "$idf/esp32/firmware.bin" \
    > "$out/merge-esp32-patched.log" 2>&1
echo "références dans $out"
