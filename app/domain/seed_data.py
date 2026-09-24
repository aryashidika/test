"""Data dummy untuk master data (Material, Supplier), dipakai saat database
masih kosong dan lewat tombol "Reset Data Prototipe". Istilah diambil dari contoh
specsheet SPECS (PDF referensi) supaya terasa realistis untuk demo/presentasi.

Komponen TIDAK ikut di-seed generik di sini lagi (dulu ada, dihapus) — komponen
master sekarang datang dari specsheet nyata yang di-seed di
`seed_specsheet_illuzion.py`, bernomor bersih mulai dari awal tiap rentang
grup (0/4000/6000/8000...) tanpa perlu berbagi rentang dengan komponen dummy
generik lagi.
"""
from .material_service import MaterialInput, create_material
from .supplier_service import SupplierInput, create_supplier

SEED_SUPPLIERS = [
    "MKU", "KINDO", "HWASUNG", "ASEMINDO", "WINFAITH", "SERIM", "HAN YOUNG", "IEM",
    "BHS", "UMK", "SUNTEX", "CBMJ", "BOO YOUNG", "JOIL", "MGE", "Emran",
    "Royal Quick", "PT KIM", "Rungkut Cahaya", "Pentabiz International",
]

# (name, category, thickness, uom)
SEED_MATERIALS = [
    ("PU Syntetic KD Techno", "Synthetic Leather", "1.2mm", "YD"),
    ("Bella Luna DE 107", "Synthetic Leather", "1.1mm", "YD"),
    ("Merry Mesh", "Mesh", None, "YD"),
    ("Merry KD UMT", "Synthetic Leather", "0.7mm", "YD"),
    ("EVA Hardness 40-45 Asker C", "Foam", "2.0mm", "YD"),
    ("Foam 50 Kg", "Foam", "6.0mm", "YD"),
    ("Super Light SL 560", "Reinforcement", "0.6mm", "YD"),
    ("Hysock 16 N", "Insole Board", "1.6mm", "YD"),
    ("TPU Injection Hardness 98 Shore D", "Outsole Compound", None, "KG"),
    ("NKLH 040 Star Bonded 210D/3Ply", "Sewing Thread", None, "CONE"),
    ("Lace Dual Width BYL G212", "Shoelace", "115cm", "PRS"),
    ("Standard Hangtag Price", "Hangtag", None, "PCS"),
    ("Heat Seal Size Label", "Label", None, "PCS"),
    ("Kertas Tissue Polos", "Packaging", None, "PCS"),
    ("Inner Box New Design 2023", "Packaging", None, "PCS"),
    ("Standard Carton Box", "Packaging", None, "PCS"),
    ("Silica Gel", "Packaging", "2gr", "PCS"),
    ("Isolatape", "Packaging", None, "ROLL"),
    ("Non Woven NW 260", "Reinforcement", "1.2mm", "YD"),
    ("Canvas 6 oz", "Toe Box Material", None, "YD"),
]


def seed_dummy_master_data(conn, actor: str = "SEED") -> None:
    for name in SEED_SUPPLIERS:
        create_supplier(conn, SupplierInput(name=name, status="APPROVED"), actor)

    for idx, (name, category, thickness, uom) in enumerate(SEED_MATERIALS, start=1):
        create_material(
            conn,
            MaterialInput(
                material_code=f"MTR-{idx:04d}", name=name, category=category,
                thickness=thickness, uom=uom, status="APPROVED",
            ),
            actor,
        )


def has_master_data(conn) -> bool:
    count = conn.execute("SELECT COUNT(*) c FROM material").fetchone()["c"]
    return count > 0
