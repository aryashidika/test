"""Menu Laporan lama. Where-Used dan Histori Harga sekarang jadi tab di detail
Material (Master Data); route di sini hanya mengarahkan URL lama ke sana."""

from flask import Blueprint, redirect, request, url_for

from ...domain import permissions
from ..auth import guard_blueprint, require_permission

laporan_bp = Blueprint("laporan", __name__, url_prefix="/laporan")
guard_blueprint(laporan_bp, permissions.can_view_reports)


def _to_material(tab, **extra):
    material_id = request.args.get("material_id")
    if not material_id:
        return redirect(url_for("master.material_page"))
    return redirect(url_for("master.material_detail", material_id=material_id, tab=tab, **extra))


@laporan_bp.route("")
@laporan_bp.route("/where-used")
def where_used_page():
    return _to_material("dipakai")


@laporan_bp.route("/histori-harga")
@require_permission(permissions.can_view_price, "Histori harga tidak tersedia untuk role Anda.")
def histori_harga_page():
    return _to_material("histori", stage=request.args.get("stage") or None)
