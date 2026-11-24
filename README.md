# ESPKit

SDK Swift pour dialoguer avec le bootloader série des puces Espressif (ESP8266, ESP32 et famille ESP32-x) : détection, flash, images, Secure Boot, chiffrement flash et eFuses. Réimplémentation indépendante des capacités d'esptool, espefuse et espsecure, sans CLI.

- **Plateformes :** macOS 15+, puis Linux.
- **Langage :** Swift 6, concurrence stricte. `ESPDevice` est un `actor` ; les opérations longues sont des `AsyncSequence`.
- **Licence :** MIT OR Apache-2.0 (`LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE`).

La spécification de l'API publique fait foi : elle se trouve dans le dossier de recherche (`ESPKit-API.md`).

## État : phase 0 (socle)

Disponible :

- types de base (`ChipFamily`, `ChipRevision`, `MACAddress`, `KeyPurpose`, réglages flash) ;
- `SerialPort` POSIX (débits arbitraires sur macOS, débits standard sur Linux), découverte des ports (IOKit, sysfs), séquences de reset (classique, UnixTight, USB-Serial-JTAG, personnalisée) ;
- connexion : reset, synchro, détection de la puce (chip ID ou valeur magique), Secure Download Mode ;
- registres, MAC, `securityInfo()`, attachement de la flash et identité JEDEC, commandes SPI brutes ;
- trace bas niveau (`ConnectOptions.trace`).

Pas encore : le stub (phase 1). En attendant, se connecter en ROM seule :

```swift
import ESPKit

var options = ConnectOptions()
options.stub = .romOnly
options.baudRate = nil

let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001", options: options)
print(esp.chip, try await esp.macAddress(), try await esp.flashInfo())
await esp.disconnect(.hard)
```

## Tests

```bash
swift test
```

Les tests sur carte sont ignorés par défaut. Pour les lancer :

```bash
ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_PORT_S3=/dev/cu.usbmodem1101 swift test --filter HardwareTests
```

## Règles de contribution

- On code depuis la spécification et la documentation publique, jamais en traduisant le Python d'esptool (GPL).
- Chaque fichier porte l'en-tête `// SPDX-License-Identifier: MIT OR Apache-2.0`.
- Dépendances acceptées : `swift-crypto`, libz système. Rien sous GPL ou LGPL.
