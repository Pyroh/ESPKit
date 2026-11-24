# ESPKit

SDK Swift pour dialoguer avec le bootloader série des puces Espressif (ESP8266, ESP32 et famille ESP32-x) : détection, flash, images, Secure Boot, chiffrement flash et eFuses. Réimplémentation indépendante des capacités d'esptool, espefuse et espsecure, sans CLI.

- **Plateformes :** macOS 15+, puis Linux.
- **Langage :** Swift 6, concurrence stricte. `ESPDevice` est un `actor` ; les opérations longues sont des `AsyncSequence`.
- **Licence :** MIT OR Apache-2.0 (`LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE`).

La spécification de l'API publique fait foi : elle se trouve dans le dossier de recherche (`ESPKit-API.md`).

## État : phase 2 (images)

Disponible :

- types de base (`ChipFamily`, `ChipRevision`, `MACAddress`, `KeyPurpose`, réglages flash) ;
- `SerialPort` POSIX avec débits arbitraires (macOS : IOSSIOSPEED ; Linux : termios2), découverte des ports (IOKit, sysfs), séquences de reset (classique, UnixTight, USB-Serial-JTAG, personnalisée) ;
- connexion : reset, synchro, détection de la puce (chip ID ou valeur magique), Secure Download Mode ;
- stub v2 embarqué (`esp-flasher-stub` 2.0.0, toutes les puces sauf l'ESP32-E22), changement de débit ;
- flash : écriture compressée zlib avec contrôle MD5, patch d'en-tête du bootloader, lecture, vérification, effacement total ou par zone ;
- opérations longues en `AsyncSequence` (`ESPOperation`) : progression, annulation ;
- images (`ESPImage`, sans I/O) : lecture d'ELF, `elf2image` (ESP32-x et ESP8266 v1/v2), lecture et validation d'images (`image-info`), fusion brute, Intel HEX et UF2, lecture d'Intel HEX. Sorties identiques à l'octet à esptool 4.11 et 5.1 sur des builds ESP-IDF et Arduino ;
- registres, MAC, `securityInfo()`, identité JEDEC, commandes SPI brutes ;
- trace bas niveau (`ConnectOptions.trace`).

```swift
import ESPKit

let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")   // stub v2, 460 800 bauds
let regions = [
    FlashRegion(address: esp.chip.bootloaderOffset, data: try Data(contentsOf: bootloader)),
    FlashRegion(address: 0x8000, data: try Data(contentsOf: partitions)),
    FlashRegion(address: 0x10000, data: try Data(contentsOf: firmware)),
]
for try await event in esp.writeFlash(regions) {
    if case .progress(let p) = event { print(p.stage, Int(p.fractionCompleted * 100), "%") }
}
await esp.disconnect(.hard)
```

Pas encore : espsecure (phase 3), eFuses (phases 4 et 5), écriture chiffrée, reflash différentiel, NAND et le reste (phase 6).

## Tests

```bash
swift test
```

Les tests sur carte sont ignorés par défaut. Pour les lancer (identité des puces) :

```bash
ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_PORT_S3=/dev/cu.usbmodem1101 swift test --filter HardwareTests
```

Le test de flash a besoin en plus d'un build PlatformIO dont l'application écrit `ESPKit HIL OK <puce>` sur sa console (`printf("ESPKit HIL OK %s\n", CONFIG_IDF_TARGET)` sous ESP-IDF) :

```bash
ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_FIRMWARE_ESP32=…/.pio/build/esp32 swift test --filter HardwareTests
```

Les tests différentiels d'`ESPImage` comparent ESPKit à esptool, utilisé comme boîte noire. `Tools/oracle/make-references.sh` produit les binaires de référence à partir de builds ESP-IDF, Arduino et ESP8266 (voir l'en-tête du script), puis :

```bash
ESPKIT_IMAGE_REFERENCES=…/ref-v5 swift test --filter ReferenceTests
```

Le stub embarqué se régénère depuis une release d'esp-flasher-stub :

```bash
python3 -I Tools/generate-stubs.py v2.0.0 <dossier des JSON téléchargés>
```

## Règles de contribution

- On code depuis la spécification et la documentation publique, jamais en traduisant le Python d'esptool (GPL).
- Chaque fichier porte l'en-tête `// SPDX-License-Identifier: MIT OR Apache-2.0`.
- Dépendances acceptées : `swift-crypto`, libz système (paquet `zlib1g-dev` sous Linux). Rien sous GPL ou LGPL.
