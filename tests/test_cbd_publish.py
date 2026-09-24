from decimal import Decimal

import pytest

from app.domain.cbd_calc import margin_pct
from app.domain.cbd_service import (
    create_cbd_no_source,
    get_cbd_change_log,
    list_cbd_lines,
    publish_cbd_revision,
    update_exchange_rate,
    update_margin_pct,
    override_price,
    update_selling_price,
    update_yield,
)


def _fill(conn, line, actor="TEST"):
    update_yield(conn, line["id"], "10", actor)
    override_price(conn, line["id"], "14.7", "USD", "harga test", actor)


def test_publish_allows_lines_without_price(conn, cbd_ctx):
    # Baris tanpa harga boleh terbit (mis. proses yang harganya termasuk di baris
    # lain) — cost-nya 0, tanpa perlu ditandai.
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")
    row = conn.execute("SELECT status FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["status"] == "PUBLISHED"


def test_publish_rejects_priced_line_without_yield(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, revision_id)[0]
    override_price(conn, line["id"], "14.7", "USD", "harga test", "TEST")
    with pytest.raises(ValueError, match="belum lengkap"):
        publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")
    update_yield(conn, line["id"], "10", "TEST")
    publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")


def test_publish_requires_exchange_rate_even_though_creation_did_not(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "", "TEST")
    _fill(conn, list_cbd_lines(conn, revision_id)[0])
    with pytest.raises(ValueError, match="Exchange rate"):
        publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")
    update_exchange_rate(conn, revision_id, "16300", "TEST")
    publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")


def test_margin_and_selling_price_are_bidirectional(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, revision_id)[0]
    update_yield(conn, line["id"], "10", "TEST")
    override_price(conn, line["id"], "100000", "IDR", "harga test", "TEST")
    # material cost/pair = 0.1 * 100000 = 10000 (Actual FOB, no amortisasi/adjustment)

    update_selling_price(conn, revision_id, "20000", "TEST")
    row = conn.execute("SELECT selling_price FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["selling_price"] == "20000"
    expected_margin = margin_pct(Decimal("20000"), Decimal("10000"))
    assert expected_margin == Decimal(50)

    update_margin_pct(conn, revision_id, "50", "TEST")
    row = conn.execute("SELECT selling_price FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert Decimal(row["selling_price"]) == Decimal("20000")


def test_publish_first_revision_does_not_require_reason(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    _fill(conn, list_cbd_lines(conn, revision_id)[0])
    publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")
    row = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["status"] == "PUBLISHED"
    assert row["published_at"] is not None


def test_publish_second_revision_requires_reason(conn, cbd_ctx):
    from app.domain.cbd_service import create_cbd_same_stage

    first_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    _fill(conn, list_cbd_lines(conn, first_id)[0])
    publish_cbd_revision(conn, first_id, "OTHER", "", "TEST")

    second_id = create_cbd_same_stage(conn, cbd_ctx["article_id"], "TEST")
    with pytest.raises(ValueError, match="Alasan"):
        publish_cbd_revision(conn, second_id, "OTHER", "", "TEST")
    # with a reason, it publishes fine
    publish_cbd_revision(conn, second_id, "OTHER", "koreksi harga", "TEST")


def test_publish_rejects_invalid_category(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    _fill(conn, list_cbd_lines(conn, revision_id)[0])
    with pytest.raises(ValueError, match="Kategori"):
        publish_cbd_revision(conn, revision_id, "NOT_A_CATEGORY", "", "TEST")


def test_publish_writes_change_log_with_correct_doc_type(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    _fill(conn, list_cbd_lines(conn, revision_id)[0])
    publish_cbd_revision(conn, revision_id, "MATERIAL", "", "TEST")
    logs = get_cbd_change_log(conn, revision_id)
    assert len(logs) == 1
    assert logs[0]["doc_type"] == "CBD"
    assert logs[0]["category"] == "MATERIAL"


def test_publish_diff_reports_changed_price(conn, cbd_ctx):
    from app.domain.cbd_service import create_cbd_same_stage

    first_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, first_id)[0]
    _fill(conn, line)
    publish_cbd_revision(conn, first_id, "OTHER", "", "TEST")

    second_id = create_cbd_same_stage(conn, cbd_ctx["article_id"], "TEST")
    second_line = list_cbd_lines(conn, second_id)[0]
    override_price(conn, second_line["id"], "20.0", "USD", "harga test", "TEST")
    diff = publish_cbd_revision(conn, second_id, "MATERIAL", "harga naik", "TEST")
    assert second_line["line_key"] in diff["changed"]
    assert "Harga asli" in diff["changed"][second_line["line_key"]]["fields"]


def test_ensure_cbd_draft_blocks_edits_after_publish(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, revision_id)[0]
    _fill(conn, line)
    publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")
    with pytest.raises(ValueError, match="sudah diterbitkan"):
        update_yield(conn, line["id"], "99", "TEST")
    with pytest.raises(ValueError, match="sudah diterbitkan"):
        update_exchange_rate(conn, revision_id, "17000", "TEST")


def test_selling_price_and_margin_pct_stay_editable_after_publish(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, revision_id)[0]
    update_yield(conn, line["id"], "10", "TEST")
    override_price(conn, line["id"], "100000", "IDR", "harga test", "TEST")
    publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")

    # material cost/pair = 0.1 * 100000 = 10000 (Actual FOB, no amortisasi/adjustment)
    update_selling_price(conn, revision_id, "20000", "TEST")
    row = conn.execute("SELECT selling_price FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["selling_price"] == "20000"

    update_margin_pct(conn, revision_id, "50", "TEST")
    row = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["status"] == "PUBLISHED"
    assert Decimal(row["selling_price"]) == Decimal("20000")
