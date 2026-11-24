#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# eFuse programming scenarios replayed by espefuse in virtual mode (--virt): no chip
# is touched. Run in an empty folder holding key-ecdsa256.pem (a Secure Boot v2
# ECDSA P-256 key), then: ESPKIT_BURN_REFERENCES=<folder> swift test --filter ESPEfuseTests
set -e
python3 -I -c "open('key.bin','wb').write(bytes(range(32))); open('data.bin','wb').write(bytes(range(100,116)))"
run() { chip=$1; shift; espefuse --virt --path-efuse-file $chip.state --chip $chip --do-not-confirm "$@" >> log-$chip.txt 2>&1 || echo "FAILED $chip $*"; }
run esp32s3 burn-key BLOCK_KEY0 key.bin XTS_AES_128_KEY
run esp32s3 burn-key-digest BLOCK_KEY1 key-ecdsa256.pem SECURE_BOOT_DIGEST0
run esp32s3 burn-custom-mac 02:11:22:33:44:55
run esp32s3 set-flash-voltage 3.3V
run esp32s3 burn-block-data BLOCK_KEY5 data.bin --offset 4
run esp32s3 write-protect-efuse DIS_USB_JTAG
run esp32s3 burn-bit BLOCK_KEY4 0 1 2 255
run esp32s3 burn-efuse SPI_BOOT_CRYPT_CNT 1 DIS_DOWNLOAD_MODE 1
espefuse --virt --path-efuse-file esp32s3.state --chip esp32s3 summary --format json --file final-esp32s3.json > /dev/null 2>&1
espefuse --virt --path-efuse-file esp32s3.state --chip esp32s3 dump > dump-esp32s3.txt 2>&1
run esp32 burn-key flash_encryption key.bin
run esp32 burn-custom-mac 02:11:22:33:44:55
run esp32 set-flash-voltage 1.8V
run esp32 burn-efuse FLASH_CRYPT_CNT 1 JTAG_DISABLE 1
espefuse --virt --path-efuse-file esp32.state --chip esp32 summary --format json --file final-esp32.json > /dev/null 2>&1
espefuse --virt --path-efuse-file esp32.state --chip esp32 dump > dump-esp32.txt 2>&1
# ESP32 with the 3/4 coding scheme: 24-byte blocks and keys (state file esp32-34.state).
python3 -I -c "open('key24.bin','wb').write(bytes(range(1,25))); open('data8.bin','wb').write(bytes(range(0x80,0x88)))"
run34() { espefuse --virt --path-efuse-file esp32-34.state --chip esp32 --do-not-confirm "$@" >> log-esp32-34.txt 2>&1 || echo "FAILED esp32-34 $*"; }
run34 burn-efuse CODING_SCHEME 1
run34 burn-key flash_encryption key24.bin
run34 burn-key secure_boot_v1 key24.bin --no-protect-key
run34 burn-block-data BLOCK3 data8.bin --offset 4
run34 set-flash-voltage 3.3V
run34 burn-efuse FLASH_CRYPT_CNT 1 ABS_DONE_0 1
espefuse --virt --path-efuse-file esp32-34.state --chip esp32 summary --format json --file final-esp32-34.json > /dev/null 2>&1
espefuse --virt --path-efuse-file esp32-34.state --chip esp32 dump > dump-esp32-34.txt 2>&1
