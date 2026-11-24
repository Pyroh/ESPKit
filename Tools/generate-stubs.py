#!/usr/bin/env python3
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Génère Sources/ESPDevice/BundledStubs.swift à partir des JSON d'une release d'esp-flasher-stub.

Usage :
    python3 -I Tools/generate-stubs.py <version> <dossier contenant les <puce>.json>

Les JSON se téléchargent depuis https://github.com/espressif/esp-flasher-stub/releases
(MIT OR Apache-2.0). Ils sont recopiés tels quels : ESPKit ne lit que les segments de base
(text, data, adresses, entrée) et ignore les plugins.
"""

import json
import pathlib
import sys

# Fichier de release -> cas de ChipFamily. esp32p4-rev1.json (P4 avant la révision 3) n'est pas
# embarqué : la sélection par révision viendra avec chipInfo().
CHIPS = {
    "esp8266": "esp8266",
    "esp32": "esp32",
    "esp32s2": "esp32s2",
    "esp32s3": "esp32s3",
    "esp32s31": "esp32s31",
    "esp32c2": "esp32c2",
    "esp32c3": "esp32c3",
    "esp32c5": "esp32c5",
    "esp32c6": "esp32c6",
    "esp32c61": "esp32c61",
    "esp32h2": "esp32h2",
    "esp32h21": "esp32h21",
    "esp32h4": "esp32h4",
    "esp32p4": "esp32p4",
}


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    version, folder = sys.argv[1].lstrip("v"), pathlib.Path(sys.argv[2])
    root = pathlib.Path(__file__).resolve().parent.parent
    lines = [
        "// SPDX-License-Identifier: MIT OR Apache-2.0",
        "//",
        f"// Généré par Tools/generate-stubs.py à partir d'esp-flasher-stub v{version}. Ne pas modifier.",
        "// esp-flasher-stub : Copyright (c) 2025 Espressif Systems (Shanghai) CO LTD, MIT OR Apache-2.0.",
        "// https://github.com/espressif/esp-flasher-stub",
        "",
        "import ESPTargets",
        "",
        "extension StubImage {",
        f'    static let bundledVersion = "{version}"',
        "",
        "    static func bundledJSON(for chip: ChipFamily) -> String? {",
        "        switch chip {",
    ]
    for name, case in CHIPS.items():
        text = (folder / f"{name}.json").read_text()
        json.loads(text)  # refuse un fichier illisible
        if '"""###' in text:
            sys.exit(f"{name}.json contient un délimiteur de chaîne brute")
        lines.append(f"        case .{case}:")
        # Chaîne brute multiligne : le JSON est recopié octet pour octet, sans indentation.
        lines.append('            ###"""')
        lines.append(text.strip())
        lines.append('"""###')
    lines += [
        "        default:",
        "            nil",
        "        }",
        "    }",
        "}",
        "",
    ]
    out = root / "Sources" / "ESPDevice" / "BundledStubs.swift"
    out.write_text("\n".join(lines))
    print(f"{out.relative_to(root)} : {len(CHIPS)} stubs, {out.stat().st_size} octets")


if __name__ == "__main__":
    main()
