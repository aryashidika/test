"""Perhitungan turunan CBD (PRD 6.4 formula block). Semua fungsi murni Decimal
in/Decimal out, tanpa akses DB — nilai turunan dihitung di sini saat dibaca,
tidak pernah disimpan (PRD: "Nilai turunan dihitung di service layer")."""

from decimal import Decimal, InvalidOperation
from typing import Iterable, Optional


def to_decimal(value) -> Optional[Decimal]:
    """Parse TEXT kolom DB (atau None/'') jadi Decimal, atau None kalau kosong."""
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except InvalidOperation:
        raise ValueError(f"Nilai '{value}' bukan angka yang valid.")


def to_text(value: Optional[Decimal]) -> Optional[str]:
    """Serialisasi Decimal jadi TEXT kanonik untuk disimpan ke DB."""
    if value is None:
        return None
    return str(Decimal(value))


def price_usd(price_original: Optional[Decimal], currency: Optional[str],
              exchange_rate: Optional[Decimal]) -> Optional[Decimal]:
    """Kolom USD bersifat sekunder/opsional — exchange rate boleh belum diisi
    (revisi 2), jadi konversi yang butuh rate cukup mengembalikan None, bukan
    error, saat rate belum ada."""
    if price_original is None or currency is None:
        return None
    if currency == "USD":
        return price_original
    if exchange_rate is None or exchange_rate <= 0:
        return None
    return price_original / exchange_rate


def price_idr(price_original: Optional[Decimal], currency: Optional[str],
              exchange_rate: Optional[Decimal]) -> Optional[Decimal]:
    """Rupiah adalah mata uang utama CBD (revisi 3) — baris berharga IDR tidak
    butuh exchange rate sama sekali; hanya baris USD yang butuh rate untuk
    dikonversi."""
    if price_original is None or currency is None:
        return None
    if currency == "IDR":
        return price_original
    if exchange_rate is None or exchange_rate <= 0:
        return None
    return price_original * exchange_rate


def usage_from_yield(yield_value: Optional[Decimal]) -> Optional[Decimal]:
    """Usage adalah persentase pemakaian material per pasang sepatu; Yield adalah
    jumlah pasang yang dihasilkan dari satu unit material. usage = 1 / yield —
    hanya Yield yang diinput pengguna, Usage selalu turunan (revisi permintaan)."""
    if yield_value is None:
        return None
    if yield_value == 0:
        raise ValueError("Yield harus lebih besar dari 0.")
    return Decimal(1) / yield_value


def cost_per_pair_idr(usage: Optional[Decimal], price_original: Optional[Decimal],
                       currency: Optional[str], loss_pct: Optional[Decimal],
                       exchange_rate: Optional[Decimal]) -> Optional[Decimal]:
    """Cost per pair dihitung dalam Rupiah (revisi 3) — baris IDR tidak perlu
    exchange rate; baris USD butuh rate untuk ikut terjumlah."""
    if usage is None or price_original is None or currency is None:
        return None
    idr = price_idr(price_original, currency, exchange_rate)
    if idr is None:
        return None
    loss = loss_pct if loss_pct is not None else Decimal(0)
    return usage * idr * (1 + loss / Decimal(100))


def material_cost_idr(lines: Iterable[dict], exchange_rate: Optional[Decimal]) -> Decimal:
    """`lines`: dict per baris dengan keys status/usage/price_original/currency/loss_pct
    (Decimal atau None). Hanya baris ACTIVE yang dijumlahkan; baris tanpa harga/usage
    lengkap (atau baris USD saat rate belum diisi) dianggap 0 (belum siap
    dipublish, tapi tidak menggagalkan kalkulasi draft)."""
    total = Decimal(0)
    for line in lines:
        if line.get("status") != "ACTIVE":
            continue
        cost = cost_per_pair_idr(
            line.get("usage"), line.get("price_original"), line.get("currency"),
            line.get("loss_pct"), exchange_rate,
        )
        if cost is not None:
            total += cost
    return total


def variance(value_a: Optional[Decimal], value_b: Optional[Decimal]) -> Optional[Decimal]:
    if value_a is None or value_b is None:
        return None
    return value_a - value_b


def variance_label(variance_value: Optional[Decimal]) -> Optional[str]:
    """Label kualitatif selisih Actual FOB vs Target FOB (revisi 4)."""
    if variance_value is None:
        return None
    if variance_value > 0:
        return "OVER"
    if variance_value < 0:
        return "UNDER"
    return "SESUAI"


def total_cost(material_cost: Decimal, amortization: Optional[Decimal],
               adjustment: Optional[Decimal]) -> Decimal:
    return material_cost + (amortization or Decimal(0)) + (adjustment or Decimal(0))


def margin_pct(selling_price: Optional[Decimal], cost: Decimal) -> Optional[Decimal]:
    """Margin = (Selling Price - Total Cost) / Selling Price * 100. Bukan bagian
    dari PRD (permintaan tambahan). Selling Price dan Margin % saling terhubung
    dua arah (revisi 4): lihat `selling_price_from_margin` untuk arah sebaliknya."""
    if selling_price is None or selling_price == 0:
        return None
    return (selling_price - cost) / selling_price * Decimal(100)


def selling_price_from_margin(cost: Decimal, margin_value: Decimal) -> Decimal:
    """Kebalikan dari `margin_pct`: diberi Margin % dan Total Cost, hitung Selling
    Price yang menghasilkan margin tsb. S = cost / (1 - margin/100)."""
    if margin_value >= 100:
        raise ValueError("Margin harus kurang dari 100%.")
    return cost / (1 - margin_value / Decimal(100))
