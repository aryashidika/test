from flask import Blueprint, abort, g, render_template, request, url_for

from ...domain import permissions
from ...domain import material_price_service as prices
from ...domain.bom_service import resolve_supplier_text
from ...domain.component_service import (
    ComponentNumberError,
    create_component,
    list_components,
    set_status as set_component_status,
    suggest_next_number,
    update_component,
)
from ...domain.material_service import (
    DuplicateMaterialCodeError,
    DuplicateMaterialError,
    MaterialInput,
    create_material,
    list_materials,
    set_status as set_material_status,
    suggest_next_material_code,
    update_material,
)
from ...domain.supplier_service import (
    DuplicateSupplierError,
    SupplierInput,
    create_supplier,
    list_suppliers,
    rename_supplier,
    set_default_currency,
    set_status as set_supplier_status,
)
from ...domain.report_service import price_history, where_used
from ...domain.revision_service import STAGES
from ...domain.worklist_service import approval_queue, proposal_counts
from ..auth import guard_blueprint, require_permission, require_session

master_bp = Blueprint("master", __name__, url_prefix="/master")
guard_blueprint(master_bp, permissions.can_view_master)

STATUS_VALUES = ["PROPOSED", "APPROVED", "INACTIVE"]


def _role_ctx():
    role = g.session.role
    can_manage = permissions.can_manage_master(role)
    return {
        "can_manage": can_manage,
        "can_propose": permissions.can_propose(role) or can_manage,
        "read_only": permissions.is_read_only(role),
        "can_view_price": permissions.can_view_price(role),
        "can_manage_price": permissions.can_manage_price(role),
        "can_manage_links": permissions.can_manage_material_supplier(role),
        "can_approve_links": permissions.can_approve_material_supplier(role),
        "can_view_drafts": permissions.can_view_drafts(role),
        # Badge jumlah di sub-tab "Persetujuan" (khusus Master Admin).
        "approval_count": sum(proposal_counts(g.db).values()) if can_manage else 0,
    }


def _require(allowed):
    if not allowed:
        abort(403)


# ---------------- Material ----------------

def _material_list_ctx(error=None):
    search = request.args.get("q", "")
    price_filter = request.args.get("harga", "")
    status_filter = request.args.get("status", "")
    if status_filter not in STATUS_VALUES:
        status_filter = ""
    materials = list_materials(g.db, search=search or None, status=status_filter or None)
    role_ctx = _role_ctx()
    if price_filter == "kosong" and role_ctx["can_view_price"]:
        without_price = prices.materials_without_price(g.db)
        materials = [m for m in materials if m["id"] in without_price]
    return {
        "materials": materials, "search": search, "price_filter": price_filter,
        "status_filter": status_filter, "error": error,
        "summary": prices.supplier_summary_by_material(g.db),
        "next_material_code": suggest_next_material_code(g.db), **role_ctx,
    }


@master_bp.route("/material")
@require_session
def material_page():
    return render_template("master/material.html", **_material_list_ctx())


@master_bp.route("/material", methods=["POST"])
@require_session
def material_create():
    role = g.session.role
    _require(permissions.can_manage_master(role) or permissions.can_propose(role))
    status = "APPROVED" if permissions.can_manage_master(role) else "PROPOSED"
    data = MaterialInput(
        material_code=request.form.get("material_code", ""),
        name=request.form.get("name", ""),
        category=request.form.get("category", ""),
        thickness=request.form.get("thickness") or None,
        uom=request.form.get("uom", ""),
        status=status,
    )
    error = None
    try:
        create_material(g.db, data, g.session.actor_label)
    except (DuplicateMaterialError, DuplicateMaterialCodeError, ValueError) as exc:
        error = str(exc)
    return render_template("master/material.html", **_material_list_ctx(error=error))


@master_bp.route("/material/<material_id>/status", methods=["POST"])
@require_session
def material_set_status(material_id):
    _require(permissions.can_manage_master(g.session.role))
    new_status = request.form.get("status")
    error = None
    try:
        set_material_status(g.db, material_id, new_status, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("master/material.html", **_material_list_ctx(error=error))


@master_bp.route("/material/<material_id>/edit", methods=["POST"])
@require_session
def material_edit(material_id):
    _require(permissions.can_manage_master(g.session.role))
    form = {k: request.form.get(k, "") for k in ("material_code", "name", "category", "thickness", "uom")}
    try:
        update_material(g.db, material_id, MaterialInput(
            material_code=form["material_code"], name=form["name"], category=form["category"],
            thickness=form["thickness"] or None, uom=form["uom"],
        ), g.session.actor_label)
    except (DuplicateMaterialError, DuplicateMaterialCodeError, ValueError) as exc:
        return _render_detail(material_id, error=str(exc), material_form=form, tab="info")
    return _render_detail(material_id, notice="Data material disimpan.", tab="info")


# ---------------- Material detail: Supplier & Harga ----------------

def _group_prices(material_prices, today):
    """Per link: harga berlaku/akan berlaku (belum ditutup per hari ini) dan
    riwayat (sudah ditutup, termasuk koreksi berdurasi nol)."""
    grouped = {}
    for p in material_prices:
        entry = grouped.setdefault(p["material_supplier_id"], {"current": [], "history": []})
        if p["valid_to"] is None or p["valid_to"] > today:
            entry["current"].append(p)
        else:
            entry["history"].append(p)
    return grouped


MATERIAL_TABS = ("supplier", "info", "dipakai", "histori")


def _material_tab(tab, role_ctx, editing_material):
    tab = tab or request.args.get("tab") or ("info" if editing_material else "supplier")
    if tab not in MATERIAL_TABS or (tab == "histori" and not role_ctx["can_view_price"]):
        tab = "supplier"
    return tab


def _material_detail_ctx(material_id, error=None, notice=None, form=None, material_form=None, tab=None):
    material = g.db.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not material:
        abort(404)
    role_ctx = _role_ctx()
    editing_material = bool(request.args.get("edit") or material_form)
    tab = _material_tab(tab, role_ctx, editing_material)
    # Tab "Dipakai di" & "Histori Harga" (dulu menu Laporan terpisah).
    usage = where_used(g.db, material_id, published_only=not permissions.can_view_drafts(g.session.role)) \
        if tab == "dipakai" else []
    history_stage = request.args.get("stage") if request.args.get("stage") in STAGES else "PROD"
    history = price_history(g.db, material_id, stage=history_stage) if tab == "histori" else []
    links = prices.list_material_suppliers(g.db, material_id)
    today = prices.today_iso()
    grouped = _group_prices(prices.list_prices(g.db, material_id), today) if role_ctx["can_view_price"] else {}
    linked_ids = {l["supplier_id"] for l in links}
    addable_suppliers = [s for s in list_suppliers(g.db) if s["status"] != "INACTIVE" and s["id"] not in linked_ids]
    priceable_links = [l for l in links if l["status"] != "INACTIVE"]

    # Isi awal form "+ Harga": dari tombol Duplikat (?dup=<price_id>), dari
    # tombol Ubah (?ubah=<price_id> — supplier, warna, harga, currency sama;
    # disimpan sebagai harga baru yang menutup harga lama), dari tombol "+ Harga"
    # per supplier (?link=<link_id>), atau dari input sebelumnya yang gagal
    # disimpan (`form`).
    price_form = {"link_id": "", "color": "", "price": "", "currency": "", "valid_from": today}
    dup = request.args.get("dup")
    edit_price = request.args.get("ubah")
    source = prices.get_price(g.db, dup or edit_price) if (dup or edit_price) else None
    if source and source["material_id"] == material_id:
        price_form.update(link_id=source["material_supplier_id"], currency=source["currency"])
        if edit_price:
            price_form.update(color=source["color"] or "", price=source["price"])
            if source["valid_from"] > today:
                price_form["valid_from"] = source["valid_from"]
    if request.args.get("link"):
        price_form["link_id"] = request.args["link"]
    if form:
        price_form.update(form)
    if not price_form["currency"]:
        chosen = next((l for l in priceable_links if l["id"] == price_form["link_id"]), None)
        price_form["currency"] = chosen["default_currency"] if chosen else "IDR"

    selected_link = next((l for l in priceable_links if l["id"] == price_form["link_id"]), None)
    color_suggestions = prices.color_suggestions_for_price(
        g.db, material_id, selected_link["supplier_id"] if selected_link else None
    ) if role_ctx["can_manage_price"] else []

    return {
        "material": material, "links": links, "grouped_prices": grouped, "today": today,
        "addable_suppliers": addable_suppliers, "priceable_links": priceable_links,
        "price_form": price_form, "color_suggestions": color_suggestions,
        "focus_price_form": bool(dup or edit_price or request.args.get("link") or form),
        "editing_price": bool(edit_price and source),
        "material_form": material_form or {k: material[k] or "" for k in
                                           ("material_code", "name", "category", "thickness", "uom")},
        "editing_material": editing_material,
        "tab": tab, "usage": usage, "history": history, "history_stage": history_stage, "stages": STAGES,
        "error": error, "notice": notice, **role_ctx,
    }


def _render_detail(material_id, **kwargs):
    # Form di halaman ini di-boost htmx: tanpa HX-Push-Url, URL POST-nya yang
    # masuk ke history browser dan reload halaman jadi 405.
    ctx = _material_detail_ctx(material_id, **kwargs)
    html = render_template("master/material_detail.html", **ctx)
    tab = ctx["tab"] if ctx["tab"] != "supplier" else None
    return html, 200, {"HX-Push-Url": url_for("master.material_detail", material_id=material_id, tab=tab)}


@master_bp.route("/material/<material_id>")
@require_session
def material_detail(material_id):
    return _render_detail(material_id)


@master_bp.route("/material/<material_id>/supplier", methods=["POST"])
@require_session
def material_supplier_add(material_id):
    _require(permissions.can_manage_material_supplier(g.session.role))
    status ="APPROVED" if permissions.can_approve_material_supplier(g.session.role) else "PROPOSED"
    try:
        supplier_id = resolve_supplier_text(g.db, request.form.get("supplier_text", ""))
        if not supplier_id:
            raise ValueError("Supplier wajib diisi.")
        prices.add_material_supplier(
            g.db, material_id, supplier_id, request.form.get("supplier_material_code", ""),
            bool(request.form.get("is_preferred")), status, g.session.actor_label,
        )
    except ValueError as exc:
        return _render_detail(material_id, error=str(exc))
    return _render_detail(material_id, notice="Supplier ditambahkan.")


@master_bp.route("/material/<material_id>/supplier/<link_id>/code", methods=["POST"])
@require_session
def material_supplier_code(material_id, link_id):
    _require(permissions.can_manage_material_supplier(g.session.role))
    try:
        prices.update_supplier_material_code(g.db, link_id, request.form.get("supplier_material_code", ""),
                                             g.session.actor_label)
    except ValueError as exc:
        return _render_detail(material_id, error=str(exc))
    return _render_detail(material_id, notice="Kode di supplier disimpan.")


@master_bp.route("/material/<material_id>/supplier/<link_id>/preferred", methods=["POST"])
@require_session
def material_supplier_preferred(material_id, link_id):
    _require(permissions.can_manage_material_supplier(g.session.role))
    try:
        prices.set_preferred_supplier(g.db, link_id, g.session.actor_label)
    except ValueError as exc:
        return _render_detail(material_id, error=str(exc))
    return _render_detail(material_id, notice="Supplier utama diperbarui.")


@master_bp.route("/material/<material_id>/supplier/<link_id>/status", methods=["POST"])
@require_session
def material_supplier_status(material_id, link_id):
    _require(permissions.can_approve_material_supplier(g.session.role))
    try:
        prices.set_material_supplier_status(g.db, link_id, request.form.get("status"), g.session.actor_label)
    except ValueError as exc:
        return _render_detail(material_id, error=str(exc))
    return _render_detail(material_id, notice="Status supplier diperbarui.")


@master_bp.route("/material/<material_id>/price-method", methods=["POST"])
@require_session
def material_price_method(material_id):
    _require(permissions.can_manage_price(g.session.role))
    method = request.form.get("price_method")
    try:
        prices.set_price_method(g.db, material_id, method, g.session.actor_label)
    except ValueError as exc:
        return _render_detail(material_id, error=str(exc), tab="info")
    label = "Quotation (harga diisi per CBD)" if method == "QUOTATION" else "Katalog (harga dari master)"
    return _render_detail(material_id, notice=f"Metode harga diubah ke {label}.", tab="info")


@master_bp.route("/material/<material_id>/price", methods=["POST"])
@require_session
def material_price_add(material_id):
    _require(permissions.can_manage_price(g.session.role))
    form = {k: request.form.get(k, "") for k in ("link_id", "color", "price", "currency", "valid_from")}
    link = g.db.execute(
        "SELECT * FROM material_supplier WHERE id=? AND material_id=?", (form["link_id"], material_id)
    ).fetchone()
    try:
        if not link:
            raise ValueError("Pilih supplier untuk harga ini.")
        prices.add_price(g.db, link["id"], form["color"], form["price"], form["currency"], form["valid_from"],
                         None, g.session.actor_label)
    except ValueError as exc:
        return _render_detail(material_id, error=str(exc), form=form)
    target = f"warna {form['color'].strip()}" if form["color"].strip() else "semua warna"
    return _render_detail(material_id, notice=f"Harga {target} disimpan. CBD DRAFT yang memakainya perlu "
                                              f"'Refresh Harga dari Master'.")


@master_bp.route("/material/<material_id>/price/<price_id>/end", methods=["POST"])
@require_session
def material_price_end(material_id, price_id):
    _require(permissions.can_manage_price(g.session.role))
    try:
        prices.end_price(g.db, price_id, g.session.actor_label)
    except ValueError as exc:
        return _render_detail(material_id, error=str(exc))
    return _render_detail(material_id, notice="Harga diakhiri per hari ini.")


# ---------------- Persetujuan (Master Admin) ----------------

_APPROVAL_SETTERS = {
    "material": set_material_status,
    "komponen": set_component_status,
    "supplier-material": prices.set_material_supplier_status,
}


def _approval_ctx(error=None, notice=None):
    return {"queue": approval_queue(g.db), "error": error, "notice": notice, **_role_ctx()}


@master_bp.route("/persetujuan")
@require_session
@require_permission(permissions.can_manage_master, "Antrian persetujuan hanya untuk Master Admin.")
def approval_page():
    return render_template("master/approval.html", **_approval_ctx())


@master_bp.route("/persetujuan/<kind>/<item_id>", methods=["POST"])
@require_session
@require_permission(permissions.can_manage_master, "Antrian persetujuan hanya untuk Master Admin.")
def approval_decide(kind, item_id):
    setter = _APPROVAL_SETTERS.get(kind)
    status = request.form.get("status")
    if setter is None or status not in ("APPROVED", "INACTIVE"):
        abort(400)
    error = notice = None
    try:
        setter(g.db, item_id, status, g.session.actor_label)
        notice = "Disetujui." if status == "APPROVED" else "Ditolak (dinonaktifkan)."
    except ValueError as exc:
        error = str(exc)
    html = render_template("master/approval.html", **_approval_ctx(error=error, notice=notice))
    return html, 200, {"HX-Push-Url": url_for("master.approval_page")}


# ---------------- Komponen ----------------

@master_bp.route("/komponen")
@require_session
def component_page():
    return render_template("master/component.html", **_component_ctx())


def _component_ctx(error=None, selected_group=None, edit_id=None, edit_form=None):
    groups = g.db.execute("SELECT * FROM component_group ORDER BY sort_order").fetchall()
    gid_filter = selected_group or request.args.get("group_id") or None
    components = list_components(g.db, group_id=gid_filter or None)
    group_name_by_id = {gr["id"]: gr["name"] for gr in groups}
    return {
        "groups": groups, "components": components, "group_name_by_id": group_name_by_id,
        "selected_group": gid_filter or "", "error": error,
        "edit_id": edit_id or request.args.get("edit") or "", "edit_form": edit_form, **_role_ctx(),
    }


@master_bp.route("/komponen/next-number")
@require_session
def component_next_number():
    group_id = request.args.get("group_id")
    nxt = suggest_next_number(g.db, group_id) if group_id else None
    return render_template("master/_number_field.html", value=nxt if nxt is not None else "")


@master_bp.route("/komponen", methods=["POST"])
@require_session
def component_create():
    role = g.session.role
    _require(permissions.can_manage_master(role) or permissions.can_propose(role))
    status = "APPROVED" if permissions.can_manage_master(role) else "PROPOSED"
    group_id = request.form.get("group_id")
    error = None
    try:
        number = int(request.form.get("number", ""))
        create_component(g.db, number, request.form.get("name", ""), group_id, status, g.session.actor_label)
    except (ComponentNumberError, ValueError) as exc:
        error = str(exc)
    except TypeError:
        error = "Nomor harus berupa angka."
    return render_template("master/component.html", **_component_ctx(error=error, selected_group=group_id))


@master_bp.route("/komponen/<component_id>/status", methods=["POST"])
@require_session
def component_set_status(component_id):
    _require(permissions.can_manage_master(g.session.role))
    new_status = request.form.get("status")
    error = None
    try:
        set_component_status(g.db, component_id, new_status, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("master/component.html", **_component_ctx(error=error))


@master_bp.route("/komponen/<component_id>/edit", methods=["POST"])
@require_session
def component_edit(component_id):
    _require(permissions.can_manage_master(g.session.role))
    form = {k: request.form.get(k, "") for k in ("number", "name", "group_id")}
    try:
        try:
            number = int(form["number"])
        except ValueError:
            raise ValueError("Nomor harus berupa angka.")
        update_component(g.db, component_id, number, form["name"], form["group_id"], g.session.actor_label)
    except (ComponentNumberError, ValueError) as exc:
        html = render_template("master/component.html",
                               **_component_ctx(error=str(exc), edit_id=component_id, edit_form=form))
    else:
        html = render_template("master/component.html", **_component_ctx())
    return html, 200, {"HX-Push-Url": url_for("master.component_page")}


# ---------------- Supplier ----------------

@master_bp.route("/supplier")
@require_session
def supplier_page():
    return render_template("master/supplier.html", **_supplier_ctx())


def _supplier_ctx(error=None, search="", edit_id=None, edit_name=None):
    suppliers = list_suppliers(g.db, search=search or None)
    return {"suppliers": suppliers, "search": search, "error": error,
            "edit_id": edit_id or request.args.get("edit") or "", "edit_name": edit_name, **_role_ctx()}


@master_bp.route("/supplier", methods=["POST"])
@require_session
def supplier_create():
    _require(permissions.can_manage_master(g.session.role))
    error = None
    try:
        create_supplier(
            g.db,
            SupplierInput(
                name=request.form.get("name", ""),
                default_currency=request.form.get("default_currency", "IDR"),
            ),
            g.session.actor_label,
        )
    except (DuplicateSupplierError, ValueError) as exc:
        error = str(exc)
    return render_template("master/supplier.html", **_supplier_ctx(error=error))


@master_bp.route("/supplier/<supplier_id>/status", methods=["POST"])
@require_session
def supplier_set_status(supplier_id):
    _require(permissions.can_manage_master(g.session.role))
    new_status = request.form.get("status")
    error = None
    try:
        set_supplier_status(g.db, supplier_id, new_status, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("master/supplier.html", **_supplier_ctx(error=error))


@master_bp.route("/supplier/<supplier_id>/currency", methods=["POST"])
@require_session
def supplier_set_currency(supplier_id):
    _require(permissions.can_manage_master(g.session.role))
    error = None
    try:
        set_default_currency(g.db, supplier_id, request.form.get("default_currency"), g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("master/supplier.html", **_supplier_ctx(error=error))


@master_bp.route("/supplier/<supplier_id>/edit", methods=["POST"])
@require_session
def supplier_edit(supplier_id):
    _require(permissions.can_manage_master(g.session.role))
    name = request.form.get("name", "")
    try:
        rename_supplier(g.db, supplier_id, name, g.session.actor_label)
    except (DuplicateSupplierError, ValueError) as exc:
        html = render_template("master/supplier.html",
                               **_supplier_ctx(error=str(exc), edit_id=supplier_id, edit_name=name))
    else:
        html = render_template("master/supplier.html", **_supplier_ctx())
    return html, 200, {"HX-Push-Url": url_for("master.supplier_page")}
