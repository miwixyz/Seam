#!/usr/bin/env python3
"""Erzeugt die Stream-Deck-Profile, die das Seam-Plugin mitliefert (aus Gnotchis tools/deck-profiles.py übernommen).

Format wie Stream Decks eigener Export: ZIP mit `package.json` und `Profiles/<UUID>.sdProfile/{manifest.json, Profiles/<Seite>/manifest.json}`.
Feste UUIDs, damit jeder Lauf dieselbe Datei ergibt. Vier Profile: je Gerät (Stream Deck +, Neo) „Fenster“ (Hälften, Teilen, Naht)
und „Raster“ (Drittel, Zweidrittel, Viertel).

Aufruf:  python3 -I tools/deck-profiles.py SeamDeck/dev.mwlr.seam.deck.sdPlugin/profiles
"""
import json
import sys
import uuid
import zipfile
from pathlib import Path

PLUGIN = {"Name": "Seam", "UUID": "dev.mwlr.seam.deck", "Version": "1.3.0.2"}
NS = uuid.UUID("3b7d1c52-8a6e-4c1e-9d3a-5f4a2b7c9e11")   # Namensraum für feste UUIDs


def fixed(name):
    return str(uuid.uuid5(NS, name))


def key_state():
    return [{"FontFamily": "", "FontSize": 10, "FontStyle": "", "FontUnderline": False, "OutlineThickness": 2,
             "ShowTitle": True, "TitleAlignment": "top", "TitleColor": "#ffffff"}]


def action(kind, name, settings, slot):
    uuids = {"place": "dev.mwlr.seam.deck.place", "seam": "dev.mwlr.seam.deck.seam", "desk": "dev.mwlr.seam.deck.desk",
             "wallpaper": "dev.mwlr.seam.deck.wallpaper"}
    return {"ActionID": fixed(f"{slot}-{kind}-{json.dumps(settings, sort_keys=True)}"), "LinkedTitle": True, "Name": name,
            "Plugin": PLUGIN, "Resources": None, "Settings": settings, "State": 0, "States": key_state(), "UUID": uuids[kind]}


def place(what, slot):
    return action("place", "Platz", {"what": what}, slot)


def naht(direction, slot):
    return action("seam", "Naht", {"dir": str(direction)}, slot)


def dial(slot):
    return action("seam", "Naht", {}, slot)


def ring(name, slot):
    return action("place", "Platz", {"ring": name}, slot)


# Regler: 1 Naht (drehen = Naht, drücken = Teilen), 2 bis 4 = Platz-Ringe (drehen wählt, drücken wendet an).
PLUS_DIALS = {"0,0": dial("d0"), "1,0": ring("halves", "d1"), "2,0": ring("thirds", "d2"), "3,0": ring("quarters", "d3")}


def desk(what, slot):
    return action("desk", "Layout", {"desk": what}, slot)


def bild(direction, slot):
    return action("wallpaper", "Hintergrund", {"dir": str(direction)}, slot)


def bild_dial(slot):
    return action("wallpaper", "Hintergrund", {}, slot)


def keys(prefix, items):
    return {f"{i % 4},{i // 4}": item(f"{prefix}{i}") for i, item in enumerate(items)}


# Stream Deck + (4 × 2 Tasten, 4 Regler).
PLUS_FENSTER = [lambda s: place("split", s), lambda s: place("left", s), lambda s: place("right", s), lambda s: place("up", s),
                lambda s: place("down", s), lambda s: place("maximize", s), lambda s: place("center", s),
                lambda s: place("nextDisplay", s)]
PLUS_RASTER = [lambda s: place("firstThird", s), lambda s: place("centerThird", s), lambda s: place("lastThird", s),
               lambda s: place("restore", s),
               lambda s: place("firstTwoThirds", s), lambda s: place("centerTwoThirds", s), lambda s: place("lastTwoThirds", s),
               lambda s: place("previousDisplay", s)]
# Neo (4 × 2 Tasten, keine Regler): Naht ± liegt auf Tasten.
NEO_FENSTER = [lambda s: place("split", s), lambda s: place("left", s), lambda s: place("right", s), lambda s: place("maximize", s),
               lambda s: naht(-1, s), lambda s: naht(1, s), lambda s: place("center", s), lambda s: place("nextDisplay", s)]
NEO_RASTER = [lambda s: place("topLeft", s), lambda s: place("topRight", s), lambda s: place("bottomLeft", s),
              lambda s: place("bottomRight", s),
              lambda s: place("up", s), lambda s: place("down", s), lambda s: naht(-1, s), lambda s: naht(1, s)]

# Layout und Hintergrund (Stufe 2 und 3): Layout-Tasten nur per langem Druck (≥ 0,8 s, im Plugin).
PLUS_LAYOUT = [lambda s: desk("save", s), lambda s: desk("tidy", s), lambda s: bild(-1, s), lambda s: bild(1, s),
               lambda s: place("split", s), lambda s: place("left", s), lambda s: place("right", s), lambda s: place("maximize", s)]
PLUS_LAYOUT_DIALS = {"0,0": bild_dial("d0"), "1,0": dial("d1"), "2,0": ring("halves", "d2"), "3,0": ring("thirds", "d3")}
NEO_LAYOUT = [lambda s: desk("save", s), lambda s: desk("tidy", s), lambda s: bild(-1, s), lambda s: bild(1, s),
              lambda s: place("split", s), lambda s: place("left", s), lambda s: place("right", s), lambda s: place("maximize", s)]

# Gerätemodelle gemessen 17.11. in Michaels ProfilesV3: Stream Deck + = 20GBD9901, Stream Deck Neo = 20GBJ9901.
PROFILES = [
    {"file": "seam-plus", "title": "Seam Fenster", "model": "20GBD9901", "second": "Encoder", "keys": PLUS_FENSTER, "dials": PLUS_DIALS},
    {"file": "seam-plus-raster", "title": "Seam Raster", "model": "20GBD9901", "second": "Encoder", "keys": PLUS_RASTER, "dials": PLUS_DIALS},
    {"file": "seam-plus-layout", "title": "Seam Layout", "model": "20GBD9901", "second": "Encoder", "keys": PLUS_LAYOUT,
     "dials": PLUS_LAYOUT_DIALS},
    {"file": "seam-neo-layout", "title": "Seam Layout", "model": "20GBJ9901", "second": "Neo", "keys": NEO_LAYOUT, "dials": None},
    {"file": "seam-neo", "title": "Seam Fenster", "model": "20GBJ9901", "second": "Neo", "keys": NEO_FENSTER, "dials": None},
    {"file": "seam-neo-raster", "title": "Seam Raster", "model": "20GBJ9901", "second": "Neo", "keys": NEO_RASTER, "dials": None},
]


def build(p, target: Path):
    prof = fixed(p["file"] + "-profile").upper()
    page = fixed(p["file"] + "-page")
    default = fixed(p["file"] + "-default")
    manifest = {"Device": {"Model": p["model"], "UUID": fixed(p["file"] + "-device")}, "Name": p["title"],
                "Pages": {"Current": "00000000-0000-0000-0000-000000000000", "Default": default, "Pages": [page]},
                "Version": "3.0"}
    page_manifest = {"Controllers": [{"Actions": keys(p["file"] + "-k", p["keys"]), "Type": "Keypad"},
                                     {"Actions": p["dials"], "Type": p["second"]}],
                     "Icon": "", "Name": p["title"]}
    default_manifest = {"Controllers": [{"Actions": None, "Type": "Keypad"}, {"Actions": None, "Type": p["second"]}],
                        "Icon": "", "Name": ""}
    package = {"AppVersion": "7.6.1.23033", "DeviceModel": p["model"], "DeviceSettings": None, "FormatVersion": 1,
               "OSType": "macOS", "OSVersion": "27.2", "RequiredPlugins": [PLUGIN["UUID"]]}
    root = f"Profiles/{prof}.sdProfile"
    path = target / f"{p['file']}.streamDeckProfile"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        def add(name, obj):
            z.writestr(zipfile.ZipInfo(name, date_time=(2026, 11, 23, 0, 0, 0)), json.dumps(obj, ensure_ascii=False, indent=2))

        def folder(name):
            z.writestr(zipfile.ZipInfo(name + "/", date_time=(2026, 11, 23, 0, 0, 0)), "")

        add("package.json", package)
        folder("Profiles")
        folder(root)
        add(f"{root}/manifest.json", manifest)
        folder(f"{root}/Profiles")
        folder(f"{root}/Profiles/{page.upper()}")
        add(f"{root}/Profiles/{page.upper()}/manifest.json", page_manifest)
        folder(f"{root}/Profiles/{default.upper()}")
        add(f"{root}/Profiles/{default.upper()}/manifest.json", default_manifest)
    return path


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    target.mkdir(parents=True, exist_ok=True)
    for prof in PROFILES:
        print("geschrieben:", build(prof, target))
