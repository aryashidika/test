"""Seed specsheet nyata: ACC ILLUZION IV ELITE FG (PRM-097), FH26, stage PROD,
digitalisasi persis dari "SS_SPECS_FH26_FOOTBALL_ACC ILLUZION IV ELITE FG_PROD.pdf".

Ditambahkan sebagai pengganti model/specsheet/CBD dummy sebelumnya (M1-M4 QA
data). Master data (material/komponen/supplier) yang belum ada di database
ditambahkan di sini juga — tidak menghapus/mengubah master data yang sudah ada.

Catatan digitalisasi (deviasi dari sumber PDF, atas arahan pengguna):
- PDF menomori baris 1-37 tapi ada duplikat nomor "13" (Toe Box & Eyestay Reinf
  IN sama-sama "13") — dinomori ulang berurutan 1-38 di sini karena
  `local_component_no`/`Component.number` wajib unik.
- Semua baris komponen didaftarkan sebagai Component MASTER (bukan komponen
  lokal), karena nama-namanya representasi part generik yang bisa dipakai
  ulang lintas model (sesuai prinsip "material/komponen hanya dipilih dari
  master"). Diberi nomor bersih mulai dari awal tiap rentang grup
  (0/4000/6000/8000...) — komponen dummy generik lama (Upper, Tongue, dst,
  yang dulu memakai rentang ini) dihapus karena sudah tidak dipakai
  specsheet manapun dan digantikan sepenuhnya oleh 38 komponen nyata ini.
- Baris proses/dekorasi (Laminating, W/Coating, Hot Stamping, Printing, HF
  Welding, dsb) dibuat sebagai baris Subkomponen. Materialnya disederhanakan
  jadi 5 material proses generik (Printing, Laminating, HF Welding, Upper
  Molded, "Coating FA7300 / 50 Micron + Sticker") — detail spesifik tiap
  baris (mis. jenis motif, kode warna, catatan "Sesuai Artwork") dipindah ke
  nama subkomponen, bukan ke material terpisah (arahan pengguna).
- Sel warna yang di PDF tertulis literal "None" (artinya "material ini tanpa
  kode warna", BUKAN "tidak dipakai") ditulis sebagai "Tanpa Warna" — karena
  app ini menafsirkan teks "none" pada sel sebagai BARIS TIDAK DIPAKAI
  (`bom_service.NONE_VALUES`), jadi tidak bisa dipakai literal.
- CBD TIDAK ikut di-seed di sini (PDF ini murni specsheet, tanpa data
  harga) — CBD dibuat & diisi lewat aplikasi sendiri saat dibutuhkan. Begitu
  juga master harga: link material–supplier dari BOM ikut terbentuk (langsung
  APPROVED), tapi harganya diisi tim CBD lewat Master Material.
- Kode Article per colorway: SPE1010566 (White/True Red) dan SPE1010568
  (Safety Yellow/Ice Flow), sesuai konfirmasi pengguna.
- Supplier untuk baris Carton Box + String Pin tidak diisi (kolom Source of
  Material kosong di sumber PDF, dibiarkan tanpa supplier).
- Kode material memakai format seragam `MTR-NNNN`, melanjutkan nomor material
  dummy di `seed_data.py` (MTR-0001..0020) mulai MTR-0021 — tanpa sisipan
  khusus seperti "ILZ".
- Revisi specsheet dibiarkan DRAFT (belum diterbitkan), jadi CBD-nya juga belum
  bisa/pernah dibuat — kondisi awal sebelum tim specsheet submit.
"""

from .article_service import add_article
from .bom_service import add_component_line, add_subcomponent_line, update_cell_value
from .component_service import create_component
from .material_service import MaterialInput, create_material
from .model_service import ModelInput, create_model
from .revision_service import create_empty_revision
from .specsheet_service import create_specsheet
from .supplier_service import SupplierInput, create_supplier

MODEL_CODE = "PRM-097"

# ---------------- Master data tambahan ----------------

SUPPLIERS_NEEDED = ["DAE YOUNG", "GMT", "DAEWON", "SU INDONESIA", "PELANGI", "JING XING"]

# (material_code, name, category, thickness, uom)
MATERIALS_NEEDED = [
    # 5 material proses generik (arahan pengguna: detail spesifik -> nama subkomponen)
    ("MTR-0021", "Printing", "Proses Dekorasi", None, "PRS"),
    ("MTR-0022", "Laminating", "Proses Produksi", None, "PRS"),
    ("MTR-0023", "HF Welding", "Proses Produksi", None, "PRS"),
    ("MTR-0024", "Upper Molded", "Proses Dekorasi", None, "PRS"),
    ("MTR-0025", "Coating FA7300 / 50 Micron + Sticker", "Proses Produksi", None, "PRS"),
    # material utama per baris BOM
    ("MTR-0026", "HS ALPHA DE 107", "Synthetic Leather", "0.3mm", "M"),
    ("MTR-0027", "Hotmelt FA7100 Paper 200 UM + Sticker", "Adhesive Film", "200um", "M"),
    ("MTR-0028", "Hotmelt FA7100 Paper 100 UM + Sticker", "Adhesive Film", "100um", "M"),
    ("MTR-0029", "Darmi MESH", "Mesh", None, "M"),
    ("MTR-0030", "Elastic Knit UW240801", "Knit Fabric", None, "PRS"),
    ("MTR-0031", "HASI 022T 160", "Lining Fabric", None, "M"),
    ("MTR-0032", "Hydlon Suede", "Suede", "0.8mm", "M"),
    ("MTR-0033", "Foam 50+5KG (SHL)", "Foam", "10mm", "M"),
    ("MTR-0034", "Foam 50+5KG (SHL)", "Foam", "4mm", "M"),
    ("MTR-0035", "HI SPENCO", "Foam Backer", None, "M"),
    ("MTR-0036", "Hasi Poly Page II", "Reinforcement", None, "M"),
    ("MTR-0037", "Eva Hardness 40-45 Asker C", "EVA Foam", "2.0mm", "M"),
    ("MTR-0038", "Foam 50KG", "Foam", "2mm", "M"),
    ("MTR-0039", "Punch Oval Hole Diameter 1.5X5mm", "Hardware", None, "PRS"),
    ("MTR-0040", "Lace Dual Width 32353", "Shoelace", None, "PRS"),
    ("MTR-0041", "Merry Mesh", "Mesh", None, "PRS"),
    ("MTR-0042", "Sockliner Molded SM 04", "Insole Board", "2.5-2.8mm", "PRS"),
    ("MTR-0043", "Transpaper Logo ALPHA 60mm X 7mm", "Label", None, "PRS"),
    ("MTR-0044", "NKLH 040 Star Bonded 210D/3Ply", "Sewing Thread", None, "M"),
    ("MTR-0045", "NKLH 040 Star Bonded 280D/3Ply", "Sewing Thread", None, "M"),
    ("MTR-0046", "CM 02", "Heel Counter", None, "EA"),
    ("MTR-0047", "Hysock 16 N", "Insole Board", "1.6mm", "M"),
    ("MTR-0048", "Base TPU Hardness 98A + IN Lay 98A", "Outsole Compound", None, "PRS"),
    ("MTR-0049", "Stud Tip TPU Hardness 95A", "Outsole Compound", None, "PRS"),
    ("MTR-0050", "Standard Hangtag Price", "Hangtag", None, "PRS"),
    ("MTR-0051", "Heat Seal Size Label", "Label", None, "PRS"),
    ("MTR-0052", "Kertas Tissue Polos", "Packaging", None, "PRS"),
    ("MTR-0053", "Kertas Tissue Polos (Kualitas Lebih Baik)", "Packaging", None, "PRS"),
    ("MTR-0054", "Inner Box New Design 2023", "Packaging", None, "EA"),
    ("MTR-0055", "Standard Carton Box", "Packaging", None, "EA"),
    ("MTR-0056", "Standard Sticker Inner Box", "Packaging", None, "PRS"),
    ("MTR-0057", "Standard Isolatape", "Packaging", None, "PRS"),
    ("MTR-0058", "String Pin", "Packaging Accessory", None, "PRS"),
    ("MTR-0059", "Silica Gel", "Packaging", "2gr", "PRS"),
]

# (number, name, group_code)
COMPONENTS_NEEDED = [
    (0, "Upper Overlay", "a"), (10, "Tongue Logo", "a"), (20, "Heel Seamsiling", "a"),
    (30, "Eyestay Insert", "a"), (40, "Vamp Backer", "a"), (50, "Upper Underlay", "a"),
    (60, "Tongue Collar", "a"), (70, "Upper Lining", "a"), (80, "Collar Lining", "a"),
    (90, "Collar Foam", "a"), (100, "Collar Foam 2", "a"), (110, "Collar Foam Backer", "a"),
    (120, "Toe Box", "a"), (130, "Eyestay Reinf IN", "a"), (140, "Eyestay Reinf OUT", "a"),
    (150, "Collar Reinf IN / OUT", "a"), (160, "Upper Foam", "a"), (170, "Punch Hole", "a"),
    (180, "Shoe Lace", "a"),
    (4000, "Sockliner Cover", "c"), (4010, "Cup Insole SM 04", "c"), (4020, "Sockliner Logo", "c"),
    (4030, "Heel Counter", "c"), (4040, "Insole", "c"), (4050, "Outsole PRM-097", "c"),
    (6000, "Hangtag Price", "d"), (6010, "Size Label", "d"), (6020, "Tissue Paper", "d"),
    (6030, "Wrapping Paper", "d"), (6040, "Inner Box", "d"), (6050, "Carton Box", "d"),
    (6060, "Sticker Inner Box", "d"),
    (8000, "Sewing Thread (Aksen)", "e"), (8010, "Sewing Thread (Utama)", "e"),
    (8020, "Thread Stroble", "e"), (8030, "Isolatape", "e"), (8040, "String Pin", "e"),
    (8050, "Silica Gel", "e"),
]

TRUE_RED = "True Red 19-1664 TPG"
ICE_FLOW = "Ice Flow 13-4404 TPG"
WHITE_C = "White C"
SAFETY_YELLOW = "Neon Safety Yellow 13-0630 TN"
NONE_COLOR = "Tanpa Warna"

# Tiap baris: (component_number, material_code, supplier_name_or_None, color1, color2, process, subcomponents)
# subcomponents: list of (sub_name, material_code, supplier_name_or_None, color1, color2)
BOM_ROWS = [
    (0, "MTR-0026", "HWASUNG", WHITE_C, SAFETY_YELLOW, "", [
        ("Upper Molded (Sesuai Artwork)", "MTR-0024", "MGE", NONE_COLOR, NONE_COLOR),
        ("Logo Flash Lateral - TPU Clear 1.0mm (Sesuai Artwork)", "MTR-0023", "MGE", NONE_COLOR, NONE_COLOR),
        ("Block Motif Area Lateral (Sesuai Artwork)", "MTR-0021", "MGE", NONE_COLOR, NONE_COLOR),
        ("Holographic Coloring", "MTR-0021", "MGE", "Holographic Coloring", "Holographic Coloring"),
        ("Clear Glossy", "MTR-0021", "MGE", "Clear Glossy", "Clear Glossy"),
    ]),
    (10, "MTR-0026", "HWASUNG", WHITE_C, SAFETY_YELLOW, "", [
        ("Print Block + Logo Illuzion (Negatif Film, Sesuai Artwork)", "MTR-0021", "MGE", NONE_COLOR, NONE_COLOR),
        ("Print Block - Logo Illuzion Base Material", "MTR-0021", "MGE", TRUE_RED, ICE_FLOW),
    ]),
    (20, "MTR-0026", "HWASUNG", WHITE_C, SAFETY_YELLOW, "", [
        ("Printing Block (Sesuai Artwork)", "MTR-0021", "MGE", TRUE_RED, ICE_FLOW),
        ('Printing Logo "Z" (Sesuai Artwork)', "MTR-0021", "MGE", WHITE_C, SAFETY_YELLOW),
    ]),
    (30, "MTR-0027", "ASEMINDO", "Clear", "Clear", "Hot Stamping", []),
    (40, "MTR-0028", "ASEMINDO", "Clear", "Clear", "Hot Stamping", []),
    (50, "MTR-0029", "DAE YOUNG", "White", "White", "", []),
    (60, "MTR-0030", "GMT",
     f"Base: {WHITE_C} / RIB + Deco Line: {TRUE_RED}",
     f"Base: {SAFETY_YELLOW} / RIB + Deco Line: {ICE_FLOW}", "", []),
    (70, "MTR-0031", "HWASUNG", "White", "White", "", [
        ("Laminating", "MTR-0022", "ASEMINDO", NONE_COLOR, NONE_COLOR),
        ("W/ Coating FA7300 / 50 Micron + Sticker", "MTR-0025", "ASEMINDO", NONE_COLOR, NONE_COLOR),
    ]),
    (80, "MTR-0032", "DAEWON", WHITE_C, SAFETY_YELLOW, "", []),
    (90, "MTR-0033", "SERIM", "White", "White", "Coating", [
        ("Laminating", "MTR-0022", "ASEMINDO", NONE_COLOR, NONE_COLOR),
        ("W/ Coating FA7300 / 50 Micron + Sticker", "MTR-0025", "ASEMINDO", NONE_COLOR, NONE_COLOR),
    ]),
    (100, "MTR-0034", "SERIM", "White", "White", "Coating", []),
    (110, "MTR-0035", "SU INDONESIA", "White", "White", "", [
        ("Laminating", "MTR-0022", "ASEMINDO", NONE_COLOR, NONE_COLOR),
        ("W/ Coating FA7300 / 50 Micron + Sticker", "MTR-0025", "ASEMINDO", NONE_COLOR, NONE_COLOR),
    ]),
    (120, "MTR-0031", "HWASUNG", "White", "White", "Hot Stamping", [
        ("Laminating", "MTR-0022", "ASEMINDO", NONE_COLOR, NONE_COLOR),
        ("W/ Coating FA7300 / 50 Micron + Sticker", "MTR-0025", "ASEMINDO", NONE_COLOR, NONE_COLOR),
    ]),
    (130, "MTR-0036", "HAN YOUNG", "White", "White", "", [
        ("Laminating", "MTR-0022", "ASEMINDO", NONE_COLOR, NONE_COLOR),
        ("W/ Coating FA7300 / 50 Micron + Sticker", "MTR-0025", "ASEMINDO", NONE_COLOR, NONE_COLOR),
    ]),
    (140, "MTR-0036", "HAN YOUNG", "White", "White", "", [
        ("Laminating", "MTR-0022", "ASEMINDO", NONE_COLOR, NONE_COLOR),
        ("W/ Coating FA7300 / 50 Micron + Sticker", "MTR-0025", "ASEMINDO", NONE_COLOR, NONE_COLOR),
    ]),
    (150, "MTR-0037", "MKU", "White", "White", "", []),
    (160, "MTR-0038", "SERIM", "White", "White", "", [
        ("Laminating", "MTR-0022", "ASEMINDO", NONE_COLOR, NONE_COLOR),
        ("W/ Coating FA7300 / 50 Micron + Sticker", "MTR-0025", "ASEMINDO", NONE_COLOR, NONE_COLOR),
    ]),
    (170, "MTR-0039", "UMK", NONE_COLOR, NONE_COLOR, "", []),
    (180, "MTR-0040", "PELANGI",
     f"Base: {WHITE_C} / Deco: {TRUE_RED}", f"Base: {SAFETY_YELLOW} / Deco: {ICE_FLOW}",
     "37-40: 110cm / 41-45: 115cm (panjang tali per size)", []),
    (4000, "MTR-0041", "MKU", TRUE_RED, ICE_FLOW, "", []),
    (4010, "MTR-0042", "MKU", "Black", "Black", "", []),
    (4020, "MTR-0043", "MKU", "White", SAFETY_YELLOW, "", []),
    (8000, "MTR-0044", "IEM", "White", SAFETY_YELLOW, "", []),
    (8010, "MTR-0044", "IEM", "White", "White", "", []),
    (8020, "MTR-0045", "IEM", "White", "White", "", []),
    (4030, "MTR-0046", "JING XING", "White", "White", "", []),
    (4040, "MTR-0047", "HAN YOUNG", "White", "White", "", []),
    (4050, "MTR-0048", "WINFAITH",
     f"Base: {WHITE_C} / IN LAY: {TRUE_RED}", f"Base: {SAFETY_YELLOW} / IN LAY: {ICE_FLOW}",
     "Outsole Mould SPE1010566 / Ref PRM-097", [
        ("Stud Tip", "MTR-0049", "WINFAITH", "Transuluent 50% White C", "Transuluent 50% White C"),
    ]),
    (6000, "MTR-0050", "Emran", "Red / Black", "Red / Black", "", []),
    (6010, "MTR-0051", "Emran", "White / Black", "White / Black", "", []),
    (6020, "MTR-0052", "Royal Quick", "Natural", "Natural", "", []),
    (6030, "MTR-0053", "Royal Quick", "Natural", "Natural", "", []),
    (6040, "MTR-0054", "PT KIM", "Red / White", "Red / White",
     "A3 (300x200x110mm) size 37-40 / A6 (310x215x110mm) size 41-44 / A7 (330x220x115mm) size 45", []),
    (6050, "MTR-0055", None, "Brown / Red", "Brown / Red",
     "B3 (620x465x320mm) size 37-40 / B6 (665x475x340mm) size 41-44 / B7 (680x485x350mm) size 45", []),
    (6060, "MTR-0056", "Emran", "Brown / Black", "Brown / Black",
     "Komposisi: Bagian Atas 100% Syntetic, Bagian Bawah 100% Plastik", []),
    (8030, "MTR-0057", "Rungkut Cahaya", "Brown / Red", "Brown / Red", "", []),
    (8040, "MTR-0058", None, "Clear", "Clear", "", []),
    (8050, "MTR-0059", "Pentabiz International", "Natural", "Natural", "", []),
]

ARTICLES = [
    ("SPE1010566", f"{WHITE_C} / {TRUE_RED}"),
    ("SPE1010568", f"{SAFETY_YELLOW} / {ICE_FLOW}"),
]


def _get_or_create_supplier(conn, name, actor):
    row = conn.execute("SELECT id FROM supplier WHERE name=?", (name,)).fetchone()
    if row:
        return row["id"]
    return create_supplier(conn, SupplierInput(name=name, status="APPROVED", default_currency="IDR"), actor)


def _get_or_create_material(conn, code, name, category, thickness, uom, actor):
    row = conn.execute("SELECT id FROM material WHERE material_code=?", (code,)).fetchone()
    if row:
        return row["id"]
    # Material proses (printing, laminating, dst) harganya tergantung desain &
    # warna tiap model -> metode harga QUOTATION (diisi per CBD).
    price_method = "QUOTATION" if category.lower().startswith("proses") else "CATALOG"
    return create_material(
        conn, MaterialInput(material_code=code, name=name, category=category,
                             thickness=thickness, uom=uom, status="APPROVED", price_method=price_method),
        actor,
    )


def _get_or_create_component(conn, number, name, group_code, actor):
    row = conn.execute("SELECT id FROM component WHERE number=?", (number,)).fetchone()
    if row:
        return row["id"]
    group = conn.execute("SELECT id FROM component_group WHERE code=?", (group_code,)).fetchone()
    return create_component(conn, number, name, group["id"], "APPROVED", actor)


def ensure_illuzion_specsheet_seeded(conn, actor: str = "SEED") -> None:
    """Idempoten: tidak melakukan apa-apa bila Model PRM-097 sudah ada."""
    if conn.execute("SELECT 1 FROM product_model WHERE code=?", (MODEL_CODE,)).fetchone():
        return

    for name in SUPPLIERS_NEEDED:
        _get_or_create_supplier(conn, name, actor)
    material_ids = {
        code: _get_or_create_material(conn, code, name, category, thickness, uom, actor)
        for code, name, category, thickness, uom in MATERIALS_NEEDED
    }
    component_ids = {
        number: _get_or_create_component(conn, number, name, group_code, actor)
        for number, name, group_code in COMPONENTS_NEEDED
    }
    supplier_ids = {
        row["name"]: row["id"]
        for row in conn.execute("SELECT id, name FROM supplier").fetchall()
    }

    model_id = create_model(
        conn,
        ModelInput(
            code=MODEL_CODE, name="ACC Illuzion IV Elite FG", factory="PT. Unimitra Kharisma",
            category=None, outsole_mold="SPE1010566", last_no="PRL-025",
            construction="Stroble + Toe Last", size_range="37 - 44", sample_size="41",
        ),
        actor,
    )
    specsheet_id = create_specsheet(conn, model_id, "FH26", actor)
    revision_id = create_empty_revision(conn, specsheet_id, actor, stage="PROD")

    article_ids = [
        add_article(conn, revision_id, specsheet_id, code, colorway, actor)
        for code, colorway in ARTICLES
    ]

    for component_number, material_code, supplier_name, color1, color2, process, subcomponents in BOM_ROWS:
        supplier_id = supplier_ids.get(supplier_name) if supplier_name else None
        line_id = add_component_line(
            conn, revision_id, component_ids[component_number], material_ids[material_code],
            process, actor, supplier_id=supplier_id,
        )
        update_cell_value(conn, line_id, article_ids[0], color1, actor)
        update_cell_value(conn, line_id, article_ids[1], color2, actor)

        for sub_name, sub_material_code, sub_supplier_name, sub_color1, sub_color2 in subcomponents:
            sub_supplier_id = supplier_ids.get(sub_supplier_name) if sub_supplier_name else None
            sub_line_id = add_subcomponent_line(
                conn, revision_id, line_id, sub_name, material_ids[sub_material_code],
                "", actor, supplier_id=sub_supplier_id,
            )
            update_cell_value(conn, sub_line_id, article_ids[0], sub_color1, actor)
            update_cell_value(conn, sub_line_id, article_ids[1], sub_color2, actor)

    # Sengaja TIDAK diterbitkan: specsheet contoh ini dalam keadaan belum
    # di-submit tim specsheet (DRAFT), sehingga belum ada CBD sama sekali.

    # Link material–supplier yang terbentuk otomatis dari BOM di atas berstatus
    # PROPOSED (alur normal tim spec); untuk data contoh langsung dianggap sudah
    # di-approve Master Admin. Harga sengaja tidak di-seed (PDF tanpa harga).
    conn.execute(
        "UPDATE material_supplier SET status='APPROVED' WHERE status='PROPOSED' AND created_by=?", (actor,)
    )
    conn.commit()
