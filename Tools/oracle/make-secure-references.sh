#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Produces espsecure references (black box) for the ESPSecure interoperability tests.
#
#   ESPSECURE=espsecure ./make-secure-references.sh <output> <ESP32-S3 image to sign (.bin)>
#
# Then: ESPKIT_SECURE_REFERENCES=<output> ESPKIT_ESPSECURE=espsecure swift test --filter ESPSecureTests
set -euo pipefail

ESPSECURE=${ESPSECURE:-espsecure}
out=$1; image=$2
mkdir -p "$out"
cd "$out"
for scheme in rsa3072 ecdsa256 ecdsa384; do
    $ESPSECURE generate-signing-key --version 2 --scheme $scheme key-$scheme.pem > /dev/null
    $ESPSECURE sign-data --version 2 --keyfile key-$scheme.pem --output signed-$scheme.bin "$image" > /dev/null
    $ESPSECURE digest-sbv2-public-key --keyfile key-$scheme.pem --output digest-$scheme.bin > /dev/null
done
head -c 32 /dev/urandom > xts128.key
head -c 64 /dev/urandom > xts256.key
head -c 4096 /dev/urandom > plain.bin
head -c 208 plain.bin > plain208.bin
for key in xts128 xts256; do
    for address in 0x0 0x10000 0x1080; do
        $ESPSECURE encrypt-flash-data --aes-xts --keyfile $key.key --address $address --output enc-$key-$address.bin plain.bin > /dev/null
    done
done
for input in plain.bin plain208.bin; do
    for address in 0x1010 0x1000; do
        $ESPSECURE encrypt-flash-data --aes-xts --keyfile xts128.key --address $address --output enc-mis-$address-$input $input > /dev/null
    done
done
# ESP32 scheme: key tweaked by address and FLASH_CRYPT_CONFIG.
head -c 32 /dev/urandom > esp32.key
head -c 256 plain.bin > p256.bin
for config in 0x0 0x1 0x2 0x4 0x8 0xf; do
    for address in 0x0 0x1000 0x12340 0xfedc0; do
        $ESPSECURE encrypt-flash-data --keyfile esp32.key --address $address --flash-crypt-conf $config \
            --output e32-$config-$address.bin p256.bin > /dev/null
    done
done
# Secure Boot v1 (ESP32): signing key, derived BLOCK2 keys, bootloader digest with a fixed IV, signature.
$ESPSECURE generate-signing-key --version 1 key-v1.pem > /dev/null
$ESPSECURE digest-private-key --keyfile key-v1.pem --keylen 256 v1-derived256.bin > /dev/null
$ESPSECURE digest-private-key --keyfile key-v1.pem --keylen 192 v1-derived192.bin > /dev/null
head -c 32 /dev/urandom > v1-sbkey.bin
head -c 128 /dev/urandom > v1-iv.bin
$ESPSECURE digest-secure-bootloader --keyfile v1-sbkey.bin --iv v1-iv.bin --output v1-digest.bin "$image" > /dev/null
cp "$image" v1-input.bin
$ESPSECURE sign-data --version 1 --keyfile key-v1.pem --output v1-signed.bin "$image" > /dev/null
echo "references in $out"
