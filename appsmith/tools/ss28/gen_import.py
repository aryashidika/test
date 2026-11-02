"""Buat SQL impor specsheet SS28 (Excel lama) ke sistem sebagai revisi DRAFT stage Preview.

  python gen_import.py <batch> <out_dir>    -> <out_dir>/cek.sql dan <out_dir>/impor.sql   (batch: pilot, impulse, ...)

Keputusan per batch ada di BATCHES (data model, material baru, Master Options, pemetaan khusus batch/model);
pemetaan teks material Excel -> material sistem yang berlaku untuk semua batch ada di MAT.
Keputusan user (Claude Doc "Migrasi Specsheet SS28", 28-29 Okt 2026):
- semua revisi hasil impor = stage Preview (PREV) rev 0, DRAFT; article tanpa nomor
- Size Label / Hang Tag / Sticker Inner Box = material per model (nama + model)
- bagian outsole (Base, Stud, Logo) tidak jadi sub-baris: warnanya ke baris outsole, namanya ke kolom Process
- komponen + material + dimension yang sama dua kali (Sewing Thread) = baris kedua jadi sub-baris
- dicatat sebagai "Migrasi data"
- material, Master Options, dan link supplier yang dipakai tetapi belum ada di database didaftarkan oleh impor (30 Okt 2026)
"""
import json
import os
import re
import sys

import build_mapping as bm
import extract

USER = "Migrasi data"
SEASON = "SS28"
STAGE = "PREV"


def _permodel(tag, jr):
    """Size Label / Hang Tag / Sticker Inner Box per model (nama baku 75 kode per model); tag = nama di kamus ERP."""
    sticker_dim = "7.8 CM X 5 CM" if jr else "10 CM X 6 CM"
    emran = "EMRAN GHANIM ASAHI,PT"
    return [
        (r"^STANDARD HANGTAG PRICE SPECS$", ("HANGTAG " + tag, "PCS", "60 MM X 40 MM", emran)),
        (r"^HEAT SEAL SIZE LABEL SPECS$", ("SIZE LABEL " + tag, "PRS", None, emran)),
        (r"^STANDARD STICKER INNER BOX SPECS$", ("STICKER INNER BOX " + tag, "PCS", sticker_dim, emran)),
    ]

# ---------------------------------------------------------------- per batch
# models      : file Excel -> data model (+ "mat": pemetaan khusus model, dicek paling awal)
# options     : Master Options baru (yang dipakai model juga didaftarkan bila belum ada)
# materials   : material baru (nama, category, UoM, Process)
# mat         : pemetaan khusus batch, dicek sebelum MAT umum
# process     : kolom Process tambahan per (model, komponen)
BATCHES = {
    "pilot": {
        "models": {
            "RAIDEN FG SS 28.xlsx": {
                "name": "RAIDEN FG", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-023 MID", "outsole_mold": "PRM-112", "sizes": list(range(37, 45)), "sample": 41,
            },
            "RAIDEN IN SS 28.xlsx": {
                "name": "RAIDEN IN", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-014", "outsole_mold": "PRM-113", "sizes": list(range(37, 45)), "sample": 41,
            },
        },
        "options": [("LAST", "PRL-023 MID"), ("OUTSOLE_MOLD", "PRM-113")],
        "materials": [
            ("PU SYNTHETIC KD DUNE BACKING NON WOVEN", "SYNTHETIC LEATHER", "ME", False),
            ("EVA HARDNESS 45-50", "FOAM", "ME", False),
            ("PERFORATED", "PROCESS", "PRS", True),
            ("OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112", "OUTSOLE", "PRS", False),
            ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-113", "OUTSOLE", "PRS", False),
            ("INJECTION PHYLON HARDNESS 50-55 ASKER C", "MIDSOLE", "PRS", False),
            ("CM-04 HARDNESS 55 ASKER D", "COUNTER", "PRS", False),
            ("SIZE LABEL RAIDEN FG", "LABEL", "PRS", False),
            ("SIZE LABEL RAIDEN IN", "LABEL", "PRS", False),
            ("HANGTAG RAIDEN FG", "PACKAGING", "PCS", False),
            ("HANGTAG RAIDEN IN", "PACKAGING", "PCS", False),
            ("STANDARD STICKER INER BOX SPECS RAIDEN FG", "PACKAGING", "EA", False),
            ("STANDARD STICKER INER BOX SPECS RAIDEN IN", "PACKAGING", "EA", False),
        ],
        "mat": [
            (r"^STANDARD STICKER INNER BOX SPECS$", ("STANDARD STICKER INER BOX SPECS {model}", "EA", None, None)),
        ],
        "process": {("RAIDEN IN", "MIDSOLE"): "PRM-113"},
    },
    # Batch 1 (30 Okt 2026): Sticker Inner Box memakai nama baku impor 75 kode per model (STICKER INNER BOX <model>, PCS)
    "impulse": {
        "models": {
            "IMPULSE FG SS 28.xlsx": {
                "name": "IMPULSE FG", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-023 MID", "outsole_mold": "PRM-112", "sizes": list(range(37, 45)), "sample": 41,
            },
            "IMPULSE IN SS 28.xlsx": {
                "name": "IMPULSE IN", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-023 MID", "outsole_mold": "PRM-113", "sizes": list(range(37, 45)), "sample": 41,
            },
            "IMPULSE FG JR SS 28.xlsx": {
                "name": "IMPULSE FG JR", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-024 JR", "outsole_mold": "PRM-091 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": [(r"^TPU INJECTION$", ("OUTSOLE TPU INJECTION HARDNESS 98 A PRM-091 JR", "PRS", None, None))],
            },
            "IMPULSE IN JR SS 28.xlsx": {
                "name": "IMPULSE IN JR", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-014 JR", "outsole_mold": "PRM-099 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": [(r"^RUBBER CUP SOLE HARDNESS 60",
                         ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 JR", "PRS", None, None))],
            },
        },
        "options": [],
        "materials": [
            ("PU SYNTHETIC KD KL-314 BACKING NON WOVEN", "SYNTHETIC LEATHER", "ME", False),
            ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 JR", "OUTSOLE", "PRS", False),
        ] + [(f"SIZE LABEL IMPULSE {s}", "LABEL", "PRS", False) for s in ("FG", "IN", "FG JR", "IN JR")]
          + [(f"HANGTAG IMPULSE {s}", "PACKAGING", "PCS", False) for s in ("FG", "IN", "FG JR", "IN JR")]
          + [(f"STICKER INNER BOX IMPULSE {s}", "PACKAGING", "PCS", False) for s in ("FG", "IN", "FG JR", "IN JR")],
        "mat": [
            (r"^STANDARD STICKER INNER BOX SPECS$", ("STICKER INNER BOX {model}", "PCS", None, None)),
        ],
        # keputusan user 1 Nov 2026: Sticker Inner Box FG / IN warna kosong di Excel = Brown/Black (seperti JR);
        # Process outsole FG JR tanpa teks hardness (materialnya 98 A, teks Excel 98 Shore D); salah ketik Noen Volt
        "colors": {("IMPULSE FG", "STICKER INNER BOX"): "Brown/Black", ("IMPULSE IN", "STICKER INNER BOX"): "Brown/Black"},
        "process_set": {("IMPULSE FG JR", "OUTSOLE"): "BASE / STUD / LOGO"},
        "color_fix": {"NOEN VOLT / BLACK": "Neon Volt / Black"},
        # R22: awalan kamus ERP yang disambung ke material baru (nama app beda dengan nama ERP)
        "dict": {"PU SYNTHETIC KD KL-314 BACKING NON WOVEN": "38AX"},
        "process": {("IMPULSE IN", "MIDSOLE"): "PRM-113",
                    # teks "C/D ..." di nama komponen Insole Excel jadi remark di kolom Process (jawaban user 31 Okt)
                    ("IMPULSE FG", "INSOLE"): "C/D ALPHA NERVE", ("IMPULSE IN", "INSOLE"): "C/D DOMINIO",
                    ("IMPULSE FG JR", "INSOLE"): "C/D ALPHA NERVE JR", ("IMPULSE IN JR", "INSOLE"): "C/D ALPHA NERVE JR"},
    },
    # Batch 2 (2 Nov 2026): XCELLS FATALE + GALACTICA MORPH NV. Draf menunggu koreksi user di doc.
    "batch2": {
        "models": {
            "GALACTICA MORPH NV FG SS 28.xls": {
                "name": "GALACTICA MORPH NV FG", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-015", "outsole_mold": "PRM-080", "sizes": list(range(37, 45)), "sample": 41,
                "mat": _permodel("GALACTICA MORPH NV FG", False),
            },
            "GALACTICA MORPH NV IN SS 28.xls": {
                "name": "GALACTICA MORPH NV IN", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-014", "outsole_mold": "PRM-072", "sizes": list(range(37, 47)), "sample": 41,
                "mat": _permodel("GALACTICA MORPH NV IN", False),
            },
            "GALACTICA MORPH NV FG JR  SS 28.xls": {
                "name": "GALACTICA MORPH NV FG JR", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-024 JR", "outsole_mold": "PRM-091 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": _permodel("GALACTICA MORPH NV FG JR", True),
            },
            "GALACTICA MORPH NV IN JR SS 28.xls": {
                "name": "GALACTICA MORPH NV IN JR", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-014 JR", "outsole_mold": "PRM-099 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": _permodel("GALACTICA MORPH NV IN JR", True),
            },
            "XCELLS FATALE  FG SS 28.xls": {
                "name": "XCELLS FATALE FG", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-015", "outsole_mold": "PRM-080", "sizes": list(range(37, 45)), "sample": 41,
                "mat": _permodel("XCELLS FG", False),
            },
            "XCELLS FATALE IN SS 28 .xls": {
                "name": "XCELLS FATALE IN", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-014", "outsole_mold": "PRM-081", "sizes": list(range(37, 45)), "sample": 41,
                "mat": _permodel("XCELLS IN", False),
            },
            "XCELLS FATALE FG JR  SS 28.xls": {
                "name": "XCELLS FATALE FG JR", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-024 JR", "outsole_mold": "PRM-091 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": _permodel("XCELLS FG JR", True),
            },
            "XCELLS FATALE IN JR SS 28.xls": {
                "name": "XCELLS FATALE IN JR", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-014 JR", "outsole_mold": "PRM-081 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": _permodel("XCELLS IN JR", True),
            },
        },
        # nama komponen Excel -> komponen master (M3 user, 2 Nov 2026); yang tidak ada didaftarkan oleh impor
        "comp_alias": {"VAMP / UPPER": "UPPER", "VAMP FOAM": "UPPER FOAM", "VAMP BACKER": "UPPER BACKER",
                       "O/S THREAD ARRIANCE": "THREAD ARIANCE", "MIDSOLE IN SERT": "MIDSOLE INSERT"},
        "components": [("UPPER LOOP", "a"), ("VAMP + QUARTER REINF IN", "a")],
        # komponen Excel yang jadi sub-baris komponen lain: (model, komponen Excel) -> (komponen induk, nama sub)
        "sub_of": {("GALACTICA MORPH NV FG", "SPRAY OUTSOLE"): ("OUTSOLE", "SPRAY OUTSOLE")},
        # ukuran punch hole dan logo transpaper jadi remark di kolom Process
        "process_from_text": [r"^PUNCH HOLE\s*(.+)$", r"^TRANSPAPER\s+(.+)$"],
        "color_sub": [("METALIC", "METALLIC"), ("SHINNY", "SHINY")],
        "outsole_parts": True,        # Base / Stud / Logo walau punya supplier tetap bagian outsole
        "options": [],
        "materials": [
            ("SIZE LABEL XCELLS FG", "LABEL", "PRS", False), ("SIZE LABEL XCELLS IN", "LABEL", "PRS", False),
            ("SIZE LABEL XCELLS FG JR", "LABEL", "PRS", False), ("SIZE LABEL XCELLS IN JR", "LABEL", "PRS", False),
            ("HANGTAG XCELLS FG JR", "PACKAGING", "PCS", False), ("HANGTAG XCELLS IN JR", "PACKAGING", "PCS", False),
            ("STICKER INNER BOX XCELLS FG JR", "PACKAGING", "PCS", False), ("STICKER INNER BOX XCELLS IN JR", "PACKAGING", "PCS", False),
            ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-072", "OUTSOLE", "PRS", False),
            ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-081", "OUTSOLE", "PRS", False),
            ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-081 JR", "OUTSOLE", "PRS", False),
            ("EMBOSS", "PROCESS", "PRS", True), ("SPRAY OUTSOLE", "PROCESS", "PRS", True),
            ("EVA HARDNESS 40 ASKER C", "FOAM", "ME", False),
            ("FLAT LACE TIP 15 MM BYL G 252", "LACE", "PRS", False),
        ],
        "mat": [
            (r"^1,2MM PU SHYNTETIC KD R 8", ("PU SYNTHETIC KD R 8 BACKING NON WOVEN", "ME", '1.2 MM X 54"', None)),
            (r"^1\.1 MM BELLA LUNA R 8", ("BELLA LUNA R-8 BACKING MICRO FIBER", "ME", '1.1 MM X 54"', None)),
            (r"^1\.2 MM PU SYNTHETIC KD KL-R 054", ("PU SYNTHETIC KD KL-R054 BACKING NON WOVEN", "ME", '1.2 MM X 54"', None)),
            (r"^0[,.]7 MM MERRY KD DE-7", ("MERISKIN KD DE-7 BACKING KNITWEAR", "ME", '0.7 MM X 54"', None)),
            (r"^DECORATION PRINTING", ("PRINTING SCREEN", "PRS", None, None)),
            (r"^DECORATION DEBOSS", ("DEBOSS", "PCS", None, None)),
            (r"^DECORATION EMBOSS", ("EMBOSS", "PRS", None, None)),
            (r"^2\.0 MM FOAM 50 KG$", ("2 MM FOAM 50 KG", "ME", '2 MM X 44"', None)),
            (r"^2\.0 MM FOAM 50\+5 SHL$", ("2 MM FOAM 50 KG +5 SHL", "ME", '2 MM X 44"', None)),
            (r"^SINGLE STIKER$", ("SINGLE STICKER", "PRS", None, None)),
            (r"^PUNCH HOLE", ("PUNCH HOLE", "PRS", None, None)),
            (r"^W/COATING FA 7300", ("COATING FA7300/50 MICRON", "ME", None, "ASSEMS INDO, PT")),
            (r"^6 OZ CANVAS$", ("CANVAS 6 OZ", "ME", '44"', None)),
            (r"^POLY FLAT LACE 6 MM TIP 15MM WIDTH BYL G252", ("FLAT LACE TIP 15 MM BYL G 252", "PRS", "6 MM X 110 CM", None)),
            (r"^5 MM SHOE LACE SPUN TUBULAR NSL 0208\(115 CM\)", ("SHOELACE SPUN TUBULAR (NSL0208)", "PRS", "5 MM X 115 CM", "SUN-TEX INDONESIA, PT")),
            (r"^5 MM SHOE LACE SPUN TUBULAR NSL 0208\(110 CM\)", ("SHOELACE SPUN TUBULAR (NSL0208)", "PRS", "5 MM X 110 CM", "SUN-TEX INDONESIA, PT")),
            (r"^CM 02$", ("CM 02", "EA", None, None)),
            (r"^1\.6 HYSOCK 16N$", ("HY SOCK 16N", "ME", '1.6 MM X 44"', None)),
            (r"^MERRY MESH\(GRAMASI 100\)$", ("MERRY MESH GRAMASI 100", "ME", '44"', None)),
            (r"^4\.0MM EVA HARDNESS 40 ASKER C$", ("EVA HARDNESS 40 ASKER C", "ME", '4 MM X 44"', None)),
            (r"^4\.0 MM EVA HARDNESS 45-50", ("EVA HARDNESS 45-50", "ME", '4 MM X 44"', None)),
            (r"^NKLD/008 STAR BONDED 1050", ("BONDED THREAD(1050D/3P)", "CON", "400 ME", None)),
            (r"^A7\(320X 220 X 125MM\)", ("INNER BOX SPECS", "SET", "A7 (320 X 220 X 125 MM)", None)),
            (r"^STANDARD CARTON BOX SPECS", ("STANDARD CARTON BOX NEW", "EA", None, "KARYA INDAH MULTIGUNA,PT")),
            (r"^STANDARD ISOLATAPE SPECS$", ("STANDARD ISOLATAPE SPECS", "ME", None, "RUNGKUT CAHAYA,PT")),
        ],
        # material per (model, komponen) bila teks Excel sama untuk dua baris (TPU Injection) atau pabrik/mold beda
        "mat_comp": {
            ("GALACTICA MORPH NV FG", "OUTSOLE"): ("OUTSOLE TPU INJECTION BASE 64 D STUD 64 A PRM-080", "PRS", None, "GUNFESAS TECHNOLOGY,PT"),
            ("XCELLS FATALE FG", "OUTSOLE"): ("OUTSOLE TPU INJECTION BASE 64 D STUD 64 A PRM-080", "PRS", None, "GUNFESAS TECHNOLOGY,PT"),
            ("GALACTICA MORPH NV FG", "SPRAY OUTSOLE"): ("SPRAY OUTSOLE", "PRS", None, "INDOKU HESA MAJU JAYA, PT"),   # kunci = komponen Excel (sub_of)
            ("GALACTICA MORPH NV FG JR", "OUTSOLE"): ("OUTSOLE TPU INJECTION HARDNESS 98 A PRM-091 JR", "PRS", None, None),
            ("XCELLS FATALE FG JR", "OUTSOLE"): ("OUTSOLE TPU INJECTION HARDNESS 98 A PRM-091 JR", "PRS", None, None),
            ("GALACTICA MORPH NV IN", "OUTSOLE"): ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-072", "PRS", None, None),
            ("GALACTICA MORPH NV IN JR", "OUTSOLE"): ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 JR", "PRS", None, None),
            ("XCELLS FATALE IN", "OUTSOLE"): ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-081", "PRS", None, None),
            ("XCELLS FATALE IN JR", "OUTSOLE"): ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-081 JR", "PRS", None, None),
            ("XCELLS FATALE IN", "MIDSOLE INSERT"): ("EVA MIDSOLE IN HARDNESS 55 ASKER C PRM-081", "SHT", "6 MM (150 CM X 93 CM)", "EVA CHEMICAL,PT"),
            ("XCELLS FATALE IN JR", "MIDSOLE INSERT"): ("EVA MIDSOLE IN HARDNESS 55 ASKER C PRM-081", "SHT", "6 MM (145 CM X 80 CM)", "EVA CHEMICAL,PT"),
        },
        "process_set": {("GALACTICA MORPH NV FG JR", "OUTSOLE"): "BASE / STUD / LOGO", ("XCELLS FATALE FG JR", "OUTSOLE"): "BASE / STUD / LOGO"},
        "process": {("GALACTICA MORPH NV IN", "MIDSOLE"): "PRM-072"},
    },
    # Batch 3 (2 Nov 2026): ACC LS SPYDER (6) + ALPHA FORCE PRO (2). Draf: pemetaan material menunggu hasil cek.
    "batch3": {
        "models": {
            "ACC LS  SPYDER   FG SS 28.xlsx": {
                "name": "ACC LS SPYDER FG", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-023", "outsole_mold": "PRM-105", "sizes": list(range(37, 45)), "sample": 41,
                "mat": _permodel("ACC LS SPYDER FG", False),
            },
            "ACC LS  SPYDER  IN SS 28.xlsx": {
                "name": "ACC LS SPYDER IN", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-014", "outsole_mold": "PRM-106", "sizes": list(range(37, 45)), "sample": 41,
                "mat": _permodel("ACC LS SPYDER IN", False),
            },
            "ACC LS  SPYDER CORE FG SS 28.xlsx": {
                "name": "ACC LIGHTSPEED SPYDER CORE FG", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-023 MID", "outsole_mold": "PRM-112", "sizes": list(range(37, 45)), "sample": 41,
                "mat": _permodel("ACC LIGHTSPEED SPYDER CORE FG", False),
            },
            "ACC LS  SPYDER CORE IN  SS 28.xlsx": {
                "name": "ACC LIGHTSPEED SPYDER CORE IN", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-023 MID", "outsole_mold": "PRM-099", "sizes": list(range(37, 47)), "sample": 41,
                "mat": _permodel("ACC LIGHTSPEED SPYDER CORE IN", False),
            },
            "ACC LS  SPYDER FG JR  SS 28.xls": {
                "name": "ACC LS SPYDER FG JR", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-024 JR", "outsole_mold": "PRM-091 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": _permodel("ACC LS SPYDER FG JR", True),
            },
            "ACC LS  SPYDER IN JR  SS 28.xls": {
                "name": "ACC LS SPYDER IN JR", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "JR",
                "last": "PRL-014 JR MID", "outsole_mold": "PRM-099 JR", "sizes": list(range(32, 37)), "sample": 34,
                "mat": _permodel("ACC LS SPYDER IN JR", True),
            },
            "ALPHA FORCE PRO FG SS 28.xlsx": {
                "name": "ALPHA FORCE PRO FG", "category": "FOOTBALL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-023 MID", "outsole_mold": "PRM-110", "sizes": list(range(37, 45)), "sample": 41,
                "mat": _permodel("ALPHA FORCE PRO FG", False),
            },
            "ALPHA FORCE PRO IN SS 28.xlsx": {
                "name": "ALPHA FORCE PRO IN", "category": "FUTSAL", "construction": "STROBLE + TOE LASTING", "gender": "MEN",
                "last": "PRL-014", "outsole_mold": "PRM-109", "sizes": list(range(37, 47)), "sample": 41,
                "mat": _permodel("ALPHA FORCE PRO IN", False),
            },
        },
        "comp_alias": {},
        "components": [],
        "options": [],
        "materials": [],
        "mat": [],
        "mat_comp": {},
        "process": {},
    },
}

# material yang sudah ada tapi bukan dari master JSON 28 Okt (dipakai untuk mendaftarkan bila ternyata belum ada)
KNOWN_EXTRA = {                 # dari M1 2 Nov 2026 (category, UoM, Process)
    "HANGTAG GALACTICA MORPH NV FG JR": ("PACKAGING", "PCS", False), "HANGTAG GALACTICA MORPH NV IN JR": ("PACKAGING", "PCS", False),
    "SIZE LABEL GALACTICA MORPH NV FG JR": ("LABEL", "PRS", False), "SIZE LABEL GALACTICA MORPH NV IN JR": ("LABEL", "PRS", False),
    "STICKER INNER BOX GALACTICA MORPH NV FG": ("PACKAGING", "PCS", False), "STICKER INNER BOX GALACTICA MORPH NV IN": ("PACKAGING", "PCS", False),
    "STICKER INNER BOX GALACTICA MORPH NV FG JR": ("PACKAGING", "PCS", False), "STICKER INNER BOX GALACTICA MORPH NV IN JR": ("PACKAGING", "PCS", False),
    "STICKER INNER BOX XCELLS FG": ("PACKAGING", "PCS", False), "STICKER INNER BOX XCELLS IN": ("PACKAGING", "PCS", False),
    "CM 02": ("COUNTER", "EA", False),
}

# teks material Excel (pola regex pada extract.key) -> (material, UoM, Dimension, supplier pengganti / None)
# "{model}" diganti nama model. Supplier None = supplier dari Excel (dipetakan ke master).
MAT = [
    (r"^1,2MM PU SHYNTETIC KD DUNE", ("PU SYNTHETIC KD DUNE BACKING NON WOVEN", "ME", '1.2 MM X 54"', None)),
    (r"^DECORATION PUFF PRINTING", ("PUFF PRINTING", "PRS", None, None)),
    (r"^DECORATION PRINTING (GRAPHIC|BLOCK|LINE)", ("PRINTING SCREEN", "PRS", None, None)),   # PRINTING sudah tidak ada; user pilih PRINTING SCREEN (31 Okt)
    (r"^1,2MM PU SHYNTETIC KD KL-314", ("PU SYNTHETIC KD KL-314 BACKING NON WOVEN", "ME", '1.2 MM X 54"', None)),
    (r"^DECORATION PERPORATED", ("PERFORATED", "PRS", None, None)),
    (r"^0,7 MM MERRY KD KL-050", ("MERRY KD KL-050 BACKING KNITWEAR", "ME", '0.7 MM X 54"', None)),
    (r"^2MM COCOTEX$", ("COCOTEX", "ME", '2 MM X 44"', None)),
    (r"^SINGLE STICKER$", ("SINGLE STICKER", "PRS", None, None)),
    (r"^6\.0 MM FOAM 50 KG$", ('FOAM 50KG 6 MM X 44"', "ME", '6 MM X 44"', None)),
    (r"^2\.0 MM EVA HARDNESS 40-45 ASKER C$", ("EVA HARDNESS 40-45 ASKER C", "ME", '2 MM X 44"', None)),
    (r"^0,6 MM SUPER LIGHT SL 560$", ("SUPERLIGHT SL 560", "ME", '0.6 MM X 44"', None)),
    (r"^PUNCH OVAL HOLE", ("PUNCH HOLE", "PRS", None, None)),
    (r"^6 MM FLAT NSL 0207", ("POLYFLAT TUBULAR (NSL 0207)", "PRS", "6 MM X 115 CM", "SUN-TEX INDONESIA, PT")),
    (r"^6 MM FLAT TUBULAR BSL 0040\(115 CM\)", ("POLY FLAT TUBULAR (BSL-0040)", "PRS", "6 MM X 115 CM", "SUN-TEX INDONESIA, PT")),
    (r"^6 MM FLAT TUBULAR BSL 0040\(110 CM\)", ("POLY FLAT TUBULAR (BSL-0040)", "PRS", "6 MM X 110 CM", "SUN-TEX INDONESIA, PT")),
    (r"^TR COUNTER K10 JR\(TIDAK PAKAI KAKI\)$", ("TR COUNTER K-10 JR POTONG KAKI", "PRS", None, None)),
    (r"^SC 02$", ("TR COUNTER SC-02 (HARDNESS 99)", "PRS", None, None)),
    (r"^CM 04 NEW", ("CM-04 HARDNESS 55 ASKER D", "PRS", None, None)),
    (r"^1\.6MM HYSOCK 16 N$", ("HY SOCK 16N", "ME", '1.6 MM X 44"', None)),
    (r"^MERRY MESH GRAMASI 100$", ("MERRY MESH GRAMASI 100", "ME", '44"', None)),
    (r"^4\.0MM EVA HARDNESS 45-50", ("EVA HARDNESS 45-50", "ME", '4 MM X 44"', None)),
    (r"^TRANSPAPER LOGO", ("TRANSFER PAPER", "PRS", None, None)),
    (r"^NKLH 040 STAR BONDED 210", ("BONDED THREAD(210D/3P)", "CON", "2000 ME", None)),
    (r"^NKLH 040 STAR BONDED 280", ("BONDED THREAD(N280D/3P)", "CON", "1500 ME", None)),
    (r"^TPU INJECTION$", ("OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112", "PRS", None, None)),
    (r"^RUBBER CUP SOLE HARDNESS 60", ("OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-113", "PRS", None, None)),
    (r"^INJECTION PHYLON HARDNESS .*50-55 ASKER C$",
     ("INJECTION PHYLON HARDNESS 50-55 ASKER C", "PRS", None, "EVALIA JAYA ABADI, PT")),
    (r"^STANDARD HANGTAG PRICE SPECS$", ("HANGTAG {model}", "PCS", None, None)),
    (r"^HEAT SEAL SIZE LABEL SPECS$", ("SIZE LABEL {model}", "PRS", None, None)),
    (r"^KERTAS TISSUE POLOS", ("TISSUE PAPER", "RIM", "44 X 69 CM", None)),
    (r"^INNER BOX SPECS NEW DESIGN 2023 A3", ("INNER BOX SPECS", "SET", "A3 (300 X 200 X 110 MM)", None)),
    (r"^INNER BOX SPECS NEW DESIGN 2023 A1A", ("INNER BOX SPECS", "SET", "A1A (275 X 170 X 100 MM)", None)),
    (r"^A6\(310 X 215 X 110 MM\)", ("INNER BOX SPECS", "SET", "A6 (310 X 215 X 110 MM)", None)),
    (r"^A7\(320 X 220 X 125 MM\)", ("INNER BOX SPECS", "SET", "A7 (320 X 220 X 125 MM)", None)),
    (r"^STANDARD CARTON BOX SPECS$", ("STANDARD CARTON BOX NEW", "EA", None, "KARYA INDAH MULTIGUNA,PT")),
    (r"^STANDARD ISOLATAPE SPECS$", ("STANDARD ISOLATAPE SPECS", "ME", None, None)),
    (r"^PVC CLEAR$", ("STRING PIN", "PCS", '3"', "DARMA SUKSES MANDIRI,CV")),
    (r"^2 GR SILICA GEL NATURAL$", ("SILICAGEL", "PCS", None, None)),
]
SUP_CANON = {}          # ejaan Excel -> (nama supplier master, ditemukan)



def comp_of(text, comps, batch):
    """Komponen sistem untuk nama komponen Excel: alias batch dulu, lalu saran build_mapping."""
    alias = batch.get("comp_alias", {})
    k = extract.clean(text).upper()
    if k in alias:
        return alias[k], "alias"
    return bm.suggest_component(text, comps)


def resolve_material(text, model, rules):
    k = extract.key(text)
    for pat, res in rules:
        if re.search(pat, k):
            name, uom, dim, sup = res
            return name.replace("{model}", model), uom, dim, sup
    raise SystemExit(f"Material belum dipetakan: {text!r} ({model})")


def color(c):
    c = extract.clean(c)
    return c or None


def build_model(d, comps, sups, batch):
    m = dict(batch["models"][d["file"]])
    rules = m.pop("mat", []) + batch.get("mat", []) + MAT
    model = m["name"]
    by_seq = {l["seq"]: l for l in d["lines"]}
    out = []                # baris hasil, urut Excel
    main_of = {}            # seq Excel -> index baris utama di out
    seen = {}               # (komponen, material, dimension) baris utama -> index
    for l in d["lines"]:
        parent = by_seq.get(l["parent_seq"])
        treat = "" if l["kind"] == "MAIN" else bm.classify_sub(l, parent)
        pc = extract.clean(parent["component"]).upper() if parent else ""
        # bagian outsole / midsole: gabung ke baris induk
        part_by_name = (batch.get("outsole_parts") and l["kind"] == "SUB" and "SOLE" in pc
                        and re.match(r"^(BASE|STUD|LOGO|CENTER INSERT|IN SIDE)", extract.clean(l["material"]).upper()))
        if l["kind"] == "SUB" and (treat.startswith("BAGIAN") or part_by_name) and "SOLE" in pc:
            p = out[main_of[parent["seq"]]]
            p["parts"].append(extract.clean(l["material"]).upper())
            for i, c in enumerate(l["colors"]):
                c = color(c)
                if c and c.upper() not in [x.upper() for x in p["part_colors"][i]]:
                    p["part_colors"][i].append(c)
            continue
        xcomp = extract.clean(l["component"]).upper()
        sub_of = batch.get("sub_of", {}).get((model, xcomp)) if l["kind"] == "MAIN" else None
        comp_pre = xcomp if sub_of else (comp_of(l["component"], comps, batch)[0] if l["kind"] == "MAIN" else None)
        mc = batch.get("mat_comp", {}).get((model, comp_pre))
        if mc:
            mat, uom, dim, sup_override = mc
        else:
            mat, uom, dim, sup_override = resolve_material(l["material"], model, rules)
        sup = sup_override or (SUP_CANON.get(extract.clean(l["supplier"]).upper(), (None, False))[0]
                               if l["supplier"] else None)
        if not sup and l["kind"] == "SUB" and parent:
            sup = out[main_of[parent["seq"]]]["supplier"]
        if not sup:
            raise SystemExit(f"Supplier kosong: {d['file']} baris {l['row']} {l['material']!r}")
        row = {"excel_row": l["row"], "material": mat, "uom": uom, "dimension": dim, "supplier": sup,
               "process": extract.clean(l["process"]).upper() or None, "colors": [color(c) for c in l["colors"]],
               "parts": [], "part_colors": [[] for _ in l["colors"]]}
        for pat in batch.get("process_from_text", []):          # ukuran dari teks material jadi remark Process
            mm = re.match(pat, extract.clean(l["material"]).upper())
            if mm:
                row["process"] = (row["process"] + " / " if row["process"] else "") + mm.group(1).strip()
        if sub_of:
            idx = max(i for i, r in enumerate(out) if r["kind"] == "MAIN" and r["component"] == sub_of[0])
            row.update(kind="SUB", parent=idx, sub_name=sub_of[1])
            main_of[l["seq"]] = len(out)
        elif l["kind"] == "MAIN":
            comp, how = comp_of(l["component"], comps, batch)
            if not comp:
                raise SystemExit(f"Komponen belum dipetakan: {l['component']!r}")
            row.update(kind="MAIN", component=comp)
            extra = batch.get("process", {}).get((model, comp))
            if extra:
                row["process"] = extra if not row["process"] else row["process"] + " / " + extra
            dup = seen.get((comp, mat, dim))
            if dup is not None:      # baris kedua komponen + material + dimension sama -> sub-baris
                row.update(kind="SUB", parent=dup, sub_name=comp)
            else:
                seen[(comp, mat, dim)] = len(out)
                main_of[l["seq"]] = len(out)
        else:
            p_idx = main_of[parent["seq"]]
            sub_name = extract.clean(l["material"]).upper()
            if l.get("material_from_parent"):
                sub_name = out[p_idx]["component"]
            row.update(kind="SUB", parent=p_idx, sub_name=sub_name)
        out.append(row)
    for row in out:              # warna bagian outsole -> baris outsole, nama bagian -> Process
        if row["parts"]:
            row["colors"] = [row["colors"][i] or (" / ".join(pc) if pc else None)
                             for i, pc in enumerate(row["part_colors"])]
            parts = " / ".join(row["parts"])
            row["process"] = parts if not row["process"] else row["process"] + " / " + parts
        row.pop("parts")
        row.pop("part_colors")
        key = (model, row.get("component"))
        if row["kind"] == "MAIN" and key in batch.get("colors", {}):     # warna kosong di Excel diisi keputusan user
            row["colors"] = [c or batch["colors"][key] for c in row["colors"]]
        if row["kind"] == "MAIN" and key in batch.get("process_set", {}):  # Process diganti seluruhnya
            row["process"] = batch["process_set"][key]
        fix = batch.get("color_fix", {})                                  # salah ketik warna di Excel
        row["colors"] = [fix.get(c.upper(), c) if c else c for c in row["colors"]]
        for a, b in batch.get("color_sub", []):                           # salah ketik di bagian warna
            row["colors"] = [re.sub(a, b.title() if a.isupper() else b, c, flags=re.I) if c else c for c in row["colors"]]
    arts = [{"colorway": a, "code": (d["article_codes"][i] or None) if i < len(d["article_codes"]) else None}
            for i, a in enumerate(d["articles"])]
    return {"file": d["file"], **m, "articles": arts, "lines": out}


def sql_str(s):
    return "NULL" if s is None else "'" + s.replace("'", "''") + "'"


def known_materials():
    """nama material -> (category, UoM, Process) dari master JSON, material baru semua batch, dan KNOWN_EXTRA."""
    k = {m["name"]: (m["category"], m["uom"], m["is_process"]) for m in bm.load_master("material.json")}
    for b in BATCHES.values():
        k.update({n: (c, u, p) for n, c, u, p in b["materials"]})
    k.update(KNOWN_EXTRA)
    return k


def main(batch_name, out_dir, part=None):
    batch = BATCHES[batch_name]
    master = bm.load_master
    comps = [c["name"] for c in master("component.json")] + [n for n, g in batch.get("components", [])]
    sups = [s["name"] for s in master("supplier.json")]
    every = extract.load_all()
    files = [d for d in every if d["file"] in batch["models"] and (not part or part.upper() in d["file"].upper())]
    # ejaan supplier dikelompokkan dari semua file (ROYAL QUCK = ROYAL QUICK), sama seperti workbook pemetaan
    import collections
    cnt = collections.Counter(extract.clean(l["supplier"]).upper() for d in every for l in d["lines"] if l["supplier"])
    SUP_CANON.update({k: v for k, v in bm.cluster_suppliers(cnt, sups).items() if v[1]})
    models = [build_model(d, comps, sups, batch) for d in files]
    # Master Options: yang baru + semua yang dipakai model (impor mendaftarkan yang belum ada)
    opts = list(batch["options"])
    for mdl in models:
        for kind, field in (("KATEGORI", "category"), ("CONSTRUCTION", "construction"), ("GENDER", "gender"),
                            ("LAST", "last"), ("OUTSOLE_MOLD", "outsole_mold")):
            if (kind, mdl[field]) not in opts:
                opts.append((kind, mdl[field]))
    # material: yang baru + semua yang dipakai baris (impor mendaftarkan yang belum ada)
    known = known_materials()
    mats = [{"name": n, "category": c, "uom": u, "is_process": p} for n, c, u, p in batch["materials"]]
    for x in mats:
        if x["name"] in batch.get("dict", {}):
            x["dict"] = batch["dict"][x["name"]]
    names = {x["name"] for x in mats}
    for mdl in models:
        for l in mdl["lines"]:
            if l["material"] in names:
                continue
            if l["material"] not in known:
                raise SystemExit(f"Category material belum diketahui: {l['material']!r}")
            c, u, p = known[l["material"]]
            mats.append({"name": l["material"], "category": c, "uom": u, "is_process": p})
            names.add(l["material"])
    data = {"user": USER, "season": SEASON, "stage": STAGE,
            "options": [{"kind": k, "value": v} for k, v in opts],
            "materials": mats, "models": models}
    if batch.get("components"):
        data["components"] = [{"name": n, "group": g} for n, g in batch["components"]]
    # kunci baris dipendekkan supaya SQL ringkas (k=jenis, c=komponen, s=nama sub, a=induk, m=material, u=UoM,
    # d=Dimension, p=supplier, r=Process, w=warna per article, x=baris Excel)
    short = {"kind": "k", "component": "c", "sub_name": "s", "parent": "a", "material": "m", "uom": "u",
             "dimension": "d", "supplier": "p", "process": "r", "colors": "w", "excel_row": "x"}
    for mdl in data["models"]:
        mdl["lines"] = [{short[k]: v for k, v in l.items() if v is not None and k in short} for l in mdl["lines"]]
    js = json.dumps(data, ensure_ascii=True, separators=(",", ":"))
    js = js.replace("},{", "},\n{")          # baris pendek supaya mudah dibaca / disalin
    # CEK cukup nama yang dirujuk (tanpa warna), tanpa duplikat
    cek = json.loads(js)
    seen = set()                 # nama yang dirujuk cukup sekali untuk seluruh batch
    for mdl in cek["models"]:
        lines = []
        for l in mdl["lines"]:
            t = {k: l[k] for k in ("k", "c", "m", "u", "p") if k in l and not (k == "c" and l["k"] == "SUB")}
            key = json.dumps(t, sort_keys=True)
            if key not in seen:
                seen.add(key)
                lines.append(t)
        mdl["lines"] = lines
        mdl.pop("articles")
    cjs = json.dumps(cek, ensure_ascii=True, separators=(",", ":")).replace("},{", "},\n{")
    with open(os.path.join(os.path.dirname(__file__), "impor_template.sql"), encoding="utf-8") as f:
        tpl = f.read()
    os.makedirs(out_dir, exist_ok=True)
    sfx = "_" + part.lower() if part else ""
    with open(os.path.join(out_dir, "impor" + sfx + ".sql"), "w", encoding="utf-8") as f:
        f.write(tpl.replace("__DATA__", js))
    with open(os.path.join(os.path.dirname(__file__), "cek_template.sql"), encoding="utf-8") as f:
        tpl = f.read()
    with open(os.path.join(out_dir, "cek" + sfx + ".sql"), "w", encoding="utf-8") as f:
        f.write(tpl.replace("__DATA__", cjs))
    for fn in ("impor" + sfx + ".sql", "cek" + sfx + ".sql"):          # DB Tools mengubah tanda kutip melengkung saat paste: kode harus ASCII
        with open(os.path.join(out_dir, fn), encoding="utf-8") as f:
            bad = [i for i, ln in enumerate(f, 1) if not ln.split("--")[0].isascii()]
        assert not bad, f"{fn}: karakter non-ASCII di baris {bad[:5]}"
    for m in data["models"]:
        print(m["name"], len(m["articles"]), "article,", sum(1 for l in m["lines"] if l["k"] == "MAIN"), "baris,",
              sum(1 for l in m["lines"] if l["k"] == "SUB"), "sub")
    print("JSON", len(js), "karakter")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in BATCHES:
        raise SystemExit("python gen_import.py <" + "|".join(BATCHES) + "> <out_dir> [bagian nama file]")
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
