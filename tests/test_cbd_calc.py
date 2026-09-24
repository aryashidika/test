from decimal import Decimal

import pytest

from app.domain.cbd_calc import (
    cost_per_pair_idr,
    margin_pct,
    material_cost_idr,
    price_idr,
    price_usd,
    selling_price_from_margin,
    to_decimal,
    to_text,
    total_cost,
    usage_from_yield,
    variance,
    variance_label,
)


def test_to_decimal_and_to_text_roundtrip():
    assert to_decimal(None) is None
    assert to_decimal("") is None
    assert to_decimal("14.7") == Decimal("14.7")
    assert to_text(None) is None
    assert to_text(Decimal("14.70")) == "14.70"


def test_to_decimal_rejects_garbage():
    with pytest.raises(ValueError):
        to_decimal("abc")


def test_price_usd_and_idr_use_currency_correctly():
    rate = Decimal("16300")
    assert price_usd(Decimal("14.7"), "USD", rate) == Decimal("14.7")
    assert price_usd(Decimal("239610"), "IDR", rate) == Decimal("239610") / rate
    assert price_idr(Decimal("14.7"), "USD", rate) == Decimal("14.7") * rate
    assert price_idr(Decimal("239610"), "IDR", rate) == Decimal("239610")


def test_idr_priced_lines_never_need_exchange_rate():
    # Rupiah is the primary currency (revision 3) - IDR lines compute fine
    # even when the exchange rate hasn't been filled in yet (revision 2).
    assert price_idr(Decimal("239610"), "IDR", None) == Decimal("239610")


def test_usd_conversion_returns_none_instead_of_raising_when_rate_missing():
    # Exchange rate is now optional at CBD creation time, so a missing/zero
    # rate must degrade gracefully (None), not raise, when displaying values.
    assert price_usd(Decimal("100"), "IDR", None) is None
    assert price_usd(Decimal("100"), "IDR", Decimal("0")) is None
    assert price_idr(Decimal("14.7"), "USD", None) is None
    assert price_idr(Decimal("14.7"), "USD", Decimal("0")) is None


def test_cost_per_pair_idr_matches_formula():
    # usage * priceIdr * (1 + lossPct/100)
    rate = Decimal("16300")
    cost = cost_per_pair_idr(Decimal("0.1"), Decimal("14.7"), "USD", Decimal("1.01"), rate)
    expected_idr = Decimal("14.7") * rate
    assert cost == Decimal("0.1") * expected_idr * (Decimal(1) + Decimal("1.01") / Decimal(100))


def test_cost_per_pair_idr_needs_no_rate_for_idr_lines():
    cost = cost_per_pair_idr(Decimal("0.1"), Decimal("100000"), "IDR", Decimal("0"), None)
    assert cost == Decimal("0.1") * Decimal("100000")


def test_cost_per_pair_idr_none_when_incomplete():
    assert cost_per_pair_idr(None, Decimal("1"), "USD", None, Decimal("1")) is None


def test_material_cost_idr_sums_only_active_lines():
    lines = [
        {"status": "ACTIVE", "usage": Decimal("1"), "price_original": Decimal("10000"),
         "currency": "IDR", "loss_pct": Decimal("0")},
        {"status": "MISSING_IN_SPEC", "usage": Decimal("100"), "price_original": Decimal("100000"),
         "currency": "IDR", "loss_pct": Decimal("0")},
        {"status": "ACTIVE", "usage": None, "price_original": None, "currency": None, "loss_pct": None},
    ]
    assert material_cost_idr(lines, None) == Decimal("10000")


def test_material_cost_idr_skips_usd_lines_when_rate_not_yet_filled():
    lines = [
        {"status": "ACTIVE", "usage": Decimal("1"), "price_original": Decimal("10"),
         "currency": "USD", "loss_pct": Decimal("0")},
    ]
    assert material_cost_idr(lines, None) == Decimal("0")


def test_variance_and_label():
    assert variance(Decimal("321806.67"), Decimal("365308")) == Decimal("321806.67") - Decimal("365308")
    assert variance_label(Decimal("10")) == "OVER"
    assert variance_label(Decimal("-10")) == "UNDER"
    assert variance_label(Decimal("0")) == "SESUAI"
    assert variance_label(None) is None


def test_usage_from_yield_is_reciprocal():
    assert usage_from_yield(Decimal("10")) == Decimal(1) / Decimal("10")
    assert usage_from_yield(None) is None


def test_usage_from_yield_rejects_zero():
    with pytest.raises(ValueError):
        usage_from_yield(Decimal("0"))


def test_total_cost_sums_material_amortization_adjustment():
    assert total_cost(Decimal("10"), Decimal("2"), Decimal("1")) == Decimal("13")
    assert total_cost(Decimal("10"), None, None) == Decimal("10")


def test_margin_pct_against_selling_price():
    # margin = (selling - cost) / selling * 100
    assert margin_pct(Decimal("100"), Decimal("80")) == Decimal(20)
    assert margin_pct(None, Decimal("80")) is None
    assert margin_pct(Decimal("0"), Decimal("80")) is None


def test_selling_price_from_margin_is_inverse_of_margin_pct():
    cost = Decimal("80")
    margin = Decimal("20")
    selling_price = selling_price_from_margin(cost, margin)
    assert margin_pct(selling_price, cost) == margin


def test_selling_price_from_margin_rejects_margin_at_or_above_100():
    with pytest.raises(ValueError):
        selling_price_from_margin(Decimal("80"), Decimal("100"))
