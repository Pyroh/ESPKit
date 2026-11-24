#!/usr/bin/env python3
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Generates ESPKit's eFuse tables (Sources/ESPEfuse/Generated/) from ESP-IDF.

    python3 -I Tools/efuse-codegen/generate.py <esp-idf>/components/efuse <labels>...

Source of facts: each chip's `esp_efuse_table.csv` (ESP-IDF, Apache-2.0): name, aliases,
block, bits, description, named values, WR_DIS / RD_DIS protection bits.

The label folders hold `<chip>.json` files produced by
`espefuse summary --format json` (on a board or with `--virt`). They are only used to align
the presentation with espefuse: displayed name among the aliases, category, type, fields shown
by `summary`, and the description of the few composite fields espefuse adds. No value,
position or protection comes from them.
"""

import json
import pathlib
import re
import sys

CHIPS = ["esp32", "esp32s2", "esp32s3", "esp32c2", "esp32c3", "esp32c5", "esp32c6",
         "esp32c61", "esp32h2", "esp32h21", "esp32h4", "esp32p4"]


def parse_csv(path):
    """Fields, write protections and read protections."""
    fields, order = {}, []
    wr_dis, rd_dis = {}, {}
    rd_dis_start = None
    current = None
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(",", 4)]
        name, block, start, count = parts[:4]
        comment = parts[4] if len(parts) > 4 else ""
        aliases = []
        match = re.match(r"\[([^\]]*)\]\s*", comment)
        if match:
            aliases = match.group(1).split()
            comment = comment[match.end():]
        values = {}
        match = re.search(r"\s*\{(.*)\}\s*$", comment)
        if match:
            for key, text in re.findall(r'(\d+)\s*:\s*"([^"]*)"', match.group(1)):
                values[int(key)] = text
            comment = comment[:match.start()]
        block_index = int(block.replace("EFUSE_BLK", ""))
        start = int(start)
        count = 256 if count == "MAX_BLK_LEN" else int(count)
        if name.startswith("WR_DIS."):
            wr_dis[name[len("WR_DIS."):]] = start
            current = None
            continue
        if name.startswith("RD_DIS."):
            rd_dis[name[len("RD_DIS."):]] = start - rd_dis_start
            current = None
            continue
        if name == "":
            fields[current]["segments"].append((start, count))
            fields[current]["lines"].append(comment)
            continue
        if name == "RD_DIS":
            rd_dis_start = start
        current = name
        order.append(name)
        fields[name] = dict(name=name, aliases=aliases, block=block_index, segments=[(start, count)],
                            description=comment.strip(), values=values, lines=[comment])
    return [fields[n] for n in order], wr_dis, rd_dis


def load_labels(folders, chip):
    labels = {}
    for folder in folders:
        path = pathlib.Path(folder) / f"{chip}.json"
        if path.exists():
            for name, entry in json.loads(path.read_text()).items():
                labels.setdefault(name, entry)
    return labels


# Fixes for wrong facts in the ESP-IDF CSVs, each one justified.
DESCRIPTION_FIXES = {
    # ESP-IDF 5.5.3 says gpio10; on the ESP32-S3 the JTAG strapping pin is GPIO3
    # (ESP32-S3 datasheet, as espefuse shows it).
    ("esp32s3", "STRAP_JTAG_SEL"): ("strapping gpio10", "strapping gpio3"),
}

SWIFT_KEYWORDS = {"default", "case", "class", "func", "import", "in", "is", "let", "var", "return",
                  "self", "struct", "switch", "true", "false", "nil", "where", "while", "for", "if", "else"}


def default_type(bits):
    if bits == 1:
        return "bool"
    if bits <= 64 or bits % 8:
        return f"uint:{bits}"
    return f"bytes:{bits // 8}"


def swift_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def generate(efuse_root, label_folders, out_dir):
    for chip in CHIPS:
        csv_path = efuse_root / chip / "esp_efuse_table.csv"
        if not csv_path.exists():
            continue
        fields, wr_dis, rd_dis = parse_csv(csv_path)
        labels = load_labels(label_folders, chip)
        used = set()
        entries = []

        def protection(field, table):
            for candidate in [field["name"]] + field["aliases"]:
                if candidate in table:
                    return table[candidate]
            return None

        for field in fields:
            fix = DESCRIPTION_FIXES.get((chip, field["name"]))
            if fix:
                field["description"] = field["description"].replace(*fix)
            display = next((c for c in [field["name"]] + field["aliases"] if c in labels and c not in used),
                           field["name"])
            label = labels.get(display)
            segments = field["segments"]
            if label and label["bit_len"] < sum(c for _, c in segments) and label["bit_len"] == segments[0][1]:
                # espefuse splits a field spread over several CSV lines: keep the first one.
                segments = segments[:1]
            bits = sum(c for _, c in segments)
            entries.append(dict(name=display, csv=field["name"], aliases=field["aliases"], block=field["block"],
                                segments=segments, description=field["description"],
                                values=field["values"], wr=protection(field, wr_dis), rd=protection(field, rd_dis),
                                category=label["category"] if label else "config",
                                type=label["efuse_type"] if label else default_type(bits),
                                shown=label is not None))
            if label:
                used.add(display)

        # espefuse fields that match a CSV continuation line.
        for name, label in labels.items():
            if name in used or label.get("word") is None:
                continue
            start = label["word"] * 32 + label["pos"]
            for field in fields:
                for index, (s, c) in enumerate(field["segments"]):
                    if field["block"] == label["block"] and s == start and c == label["bit_len"] and index > 0:
                        entries.append(dict(name=name, csv=field["name"], aliases=[], block=field["block"],
                                            segments=[(s, c)], description=field["lines"][index].strip(),
                                            values={}, wr=protection(field, wr_dis), rd=protection(field, rd_dis),
                                            category=label["category"], type=label["efuse_type"], shown=True))
                        used.add(name)

        composites = [dict(name=name, category=label["category"], type=label["efuse_type"],
                           description=label["description"], bits=label["bit_len"], block=label["block"])
                      for name, label in sorted(labels.items()) if name not in used]

        case = chip
        lines = [
            "// SPDX-License-Identifier: MIT OR Apache-2.0",
            "//",
            "// Generated by Tools/efuse-codegen/generate.py from ESP-IDF's components/efuse/"
            f"{chip}/esp_efuse_table.csv (Apache-2.0). Do not edit.",
            "",
            "extension EfuseTable {",
            f"    static let {case} = EfuseTable(chip: .{case}, fields: [",
        ]
        for e in entries:
            segs = ", ".join(f"Bits({s}, {c})" for s, c in e["segments"])
            values = ", ".join(f"{k}: {swift_string(v)}" for k, v in sorted(e["values"].items())) or ":"
            aliases = ", ".join(swift_string(a) for a in e["aliases"])
            lines.append(
                f"        EfuseDefinition(name: {swift_string(e['name'])}, idfName: {swift_string(e['csv'])}, "
                f"aliases: [{aliases}], block: {e['block']}, bits: [{segs}], "
                f"description: {swift_string(e['description'])}, category: {swift_string(e['category'])}, "
                f"type: {swift_string(e['type'])}, inSummary: {'true' if e['shown'] else 'false'}, "
                f"writeDisableBit: {e['wr'] if e['wr'] is not None else 'nil'}, "
                f"readDisableBit: {e['rd'] if e['rd'] is not None else 'nil'}, values: [{values}]),")
        lines.append("    ], composites: [")
        for c in composites:
            lines.append(
                f"        CompositeLabel(name: {swift_string(c['name'])}, block: {c['block']}, bitCount: {c['bits']}, "
                f"description: {swift_string(c['description'])}, category: {swift_string(c['category'])}, "
                f"type: {swift_string(c['type'])}),")
        lines += ["    ])", "}", ""]
        # Name constants: EfuseFieldName.ESP32S3.spiBootCryptCnt.
        namespace = {"esp32": "ESP32"}.get(chip, "ESP32" + chip[5:].upper())
        display = "ESP32" if chip == "esp32" else "ESP32-" + chip[5:].upper()
        documentation = {c["name"]: (c["description"], c["block"]) for c in composites}
        documentation.update({e["name"]: (e["description"], e["block"]) for e in entries})
        lines += ["extension EfuseFieldName {",
                  f"    /// Names of the {display} eFuse fields, from ESP-IDF's table.",
                  f"    public enum {namespace} {{"]
        names = sorted({e["name"] for e in entries} | {c["name"] for c in composites})
        for name in names:
            text, block = documentation[name]
            text = " ".join(text.split()).rstrip(".") or f"The `{name}` field"
            lines.append(f"        /// {text} (BLOCK{block}).")
            parts = name.lower().replace(".", "_").split("_")
            identifier = parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
            if identifier[:1].isdigit():
                identifier = "_" + identifier
            if identifier in SWIFT_KEYWORDS:
                identifier = f"`{identifier}`"
            lines.append(f"        public static let {identifier}: EfuseFieldName = {swift_string(name)}")
        lines += ["    }", "}", ""]
        out = out_dir / f"EfuseTable+{chip}.swift"
        out.write_text("\n".join(lines))
        print(f"{out.name}: {len(entries)} fields, {sum(e['shown'] for e in entries)} in summary, "
              f"{len(composites)} composite")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = pathlib.Path(__file__).resolve().parent.parent.parent
    out_dir = root / "Sources" / "ESPEfuse" / "Generated"
    out_dir.mkdir(parents=True, exist_ok=True)
    generate(pathlib.Path(sys.argv[1]), sys.argv[2:], out_dir)


if __name__ == "__main__":
    main()
