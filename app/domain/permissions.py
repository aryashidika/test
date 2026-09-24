ROLES = ["MASTER_ADMIN", "VENDOR_SPEC", "VENDOR_CBD", "BRAND_VIEWER", "SYSTEM_ADMIN"]


def can_manage_master(role: str) -> bool:
    """Full CRUD + approve/reject + merge on master data."""
    return role == "MASTER_ADMIN"


def can_propose(role: str) -> bool:
    """Vendor roles may propose new material/component (status PROPOSED only)."""
    return role in ("VENDOR_SPEC", "VENDOR_CBD")


def is_read_only(role: str) -> bool:
    return role in ("BRAND_VIEWER", "SYSTEM_ADMIN")


def can_edit_specsheet(role: str) -> bool:
    """CRUD specsheet & menerbitkan revisi: hak VENDOR_SPEC (PRD Bagian 3)."""
    return role == "VENDOR_SPEC"


def can_edit_cbd(role: str) -> bool:
    """CRUD CBD & menerbitkan revisi: hak VENDOR_CBD (PRD Bagian 3)."""
    return role == "VENDOR_CBD"


def can_manage_material_supplier(role: str) -> bool:
    """Mendaftarkan supplier sebuah material (kode di supplier, supplier utama):
    tim specsheet yang menentukan supplier, Master Admin untuk koreksi."""
    return role in ("VENDOR_SPEC", "MASTER_ADMIN")


def can_approve_material_supplier(role: str) -> bool:
    """Approve / nonaktifkan link material–supplier yang diusulkan."""
    return role == "MASTER_ADMIN"


def can_view_price(role: str) -> bool:
    """Harga adalah data komersial tim CBD — tim specsheet tidak melihatnya."""
    return role != "VENDOR_SPEC"


def can_manage_price(role: str) -> bool:
    """Mengisi/mengubah/mengakhiri harga & metode harga di master harga: tim CBD,
    plus Master Admin sebagai pemilik master data (koreksi/impor harga)."""
    return role in ("VENDOR_CBD", "MASTER_ADMIN")
