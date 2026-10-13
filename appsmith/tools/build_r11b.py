# Build R11b: salin exports/export_r11.json (= export user "Product Management R11", 13 Okt 2026) -> edit di tempat
# -> exports/build_r11b.json. SQL: sql/R11b_harga_batal.sql (jalankan dulu). Isi: harga AKAN BERLAKU yang diakhiri
# tampil DIBATALKAN (temuan uji C) — hanya MaterialDetailCtrl yang berubah.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


BASE = f'{ROOT}/exports/export_r11.json'
OUT = f'{ROOT}/exports/build_r11b.json'
app = App(BASE)
app.d['exportedApplication']['name'] = 'Product Management R11b'
app.set_js('Material Detail', 'MaterialDetailCtrl', js('js/MaterialDetailCtrl.js'))
app.publish_all()
app.save(OUT)
