# Build R8: salin export_r7.json (app user setelah E2E-R + perbaikan manual) -> edit di tempat -> exports/build_r8.json
# Catatan uji E2E-R: Manager Costing langsung berlaku, riwayat harga, article tanpa batas, awalan kode wajib sama,
# ajukan harga master dari CBD. SQL: sql/R8_catatan_uji.sql.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, set_binding, resize_modal, lock_manual_queries


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


BASE = f'{ROOT}/exports/export_r7.json'
OUT = f'{ROOT}/exports/build_r8.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R8'

# ================================================================ 1 + 2: Material Detail (harga)
PG = 'Material Detail'
app.set_js(PG, 'MaterialDetailCtrl', js('js/MaterialDetailCtrl.js'))
app.set_cw_source(PG, 'cwPriceForm', js=rd('widgets/cwPriceForm/script.js'))
set_binding(app.widget(PG, 'btnHargaTambah'), 'text',
            "{{MaterialDetailCtrl.canApprovePrice() ? '+ Tambah Harga' : '+ Ajukan Harga'}}")

# ================================================================ 3: article tanpa batas
PG = 'Model Detail'
app.set_js(PG, 'ModelDetailCtrl', js('js/ModelDetailCtrl.js'))
app.set_cw_source(PG, 'cwArticleForm', js=rd('widgets/cwArticleForm/script.js'))
set_binding(app.widget(PG, 'btnArticleTambah'), 'text', "{{'+ Article (' + ModelDetailCtrl.articles().length + ')'}}")

# ================================================================ 4: awalan Material Code (form varian di 2 page)
for pg in ('Material Detail', 'Specsheet'):
    app.set_cw_source(pg, 'cwVariantForm', js=rd('widgets/cwVariantForm/script.js'))

# ================================================================ 5: ajukan harga master dari CBD
PG = 'Cost Breakdown (CBD)'
app.add_query(PG, 'a_cbd_price_propose', 'a_cbd_set_quotation', f'''SELECT fn_cbd_price_propose({TOKEN}, {{{{this.params.line_id}}}}::uuid,
                            nullif({{{{this.params.price}}}}, '')::numeric, nullif({{{{this.params.currency}}}}, ''),
                            nullif({{{{this.params.valid_from}}}}, '')::date, {{{{this.params.reference}}}}) AS batch_id;''')
app.set_js(PG, 'CbdGridCtrl', js('js/CbdGridCtrl.js'))
app.set_cw_source(PG, 'cwCbdGrid', js=rd('widgets/cwCbdGrid/script.js'))
app.set_cw_source(PG, 'cwCbdPriceForm', html=rd('widgets/cwCbdPriceForm/index.html'), js=rd('widgets/cwCbdPriceForm/script.js'))
resize_modal(app, PG, 'mdlCbdHarga', 520, 50)

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
