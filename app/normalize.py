import re
from decimal import Decimal, InvalidOperation
from typing import Optional


def normalize_text(value: Optional[str]) -> str:
    """Lowercase, trim, collapse repeated spaces, and turn a decimal comma into a dot.

    Used only for duplicate-detection keys; the original text is always stored as typed.
    """
    if value is None:
        return ""
    text = value.strip().lower()
    text = text.replace(",", ".")
    text = re.sub(r"\s+", " ", text)
    return text


def parse_decimal(raw, field_name: str = "nilai") -> Optional[Decimal]:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    text = text.replace(",", ".")
    try:
        return Decimal(text)
    except InvalidOperation as exc:
        raise ValueError(f"{field_name} bukan angka yang valid: {raw}") from exc
