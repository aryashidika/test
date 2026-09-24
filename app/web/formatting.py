"""Format angka untuk TAMPILAN (bukan input): pemisah ribuan titik, desimal koma
(format Indonesia). Input yang bisa diedit tetap memakai nilai mentah."""

from decimal import ROUND_HALF_UP, Decimal, InvalidOperation


def fmt_num(value, decimals=2, trim=False, empty="-"):
    """`decimals` digit di belakang koma. `trim=True` membuang nol di belakang
    (dipakai untuk kuantitas seperti usage/yield yang presisinya bervariasi)."""
    if value is None or value == "":
        return empty
    try:
        d = Decimal(str(value))
    except InvalidOperation:
        return str(value)
    q = d.quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP) if decimals else d.quantize(
        Decimal(1), rounding=ROUND_HALF_UP)
    text = f"{q:,.{decimals}f}"
    if trim and "." in text:
        text = text.rstrip("0").rstrip(".")
    return text.replace(",", "_").replace(".", ",").replace("_", ".")


def fmt_rupiah(value, decimals=0, empty="-"):
    text = fmt_num(value, decimals, empty=empty)
    return text if text == empty else f"Rp {text}"
