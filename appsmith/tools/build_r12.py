# Build R12: salin exports/export_r11b.json (= export user "Product Management R11 (1)", 13 Okt 2026, identik dengan
# build_r11b) -> edit di tempat -> exports/build_r12.json. SQL: sql/R12_golive.sql (jalankan dulu).
# Isi: perbaikan pra-UAT dari review go-live — PLAN.md §9 T60–T67.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, lock_manual_queries


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def cw(app, page, name):
    app.set_cw_source(page, name, html=rd(f'widgets/{name}/index.html'), css=rd(f'widgets/{name}/style.css'),
                      js=rd(f'widgets/{name}/script.js'))


BASE = f'{ROOT}/exports/export_r11b.json'
OUT = f'{ROOT}/exports/build_r12.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R12'
CBD = 'Cost Breakdown (CBD)'
PAGES = [p['unpublishedPage']['name'] for p in d['pageList']]

# ---------------------------------------------------------------- T64 + T67: Util (semua page) & Auth (kecuali Login)
for pg in PAGES:
    app.set_js(pg, 'Util', js('js/Util.js'))
    if pg == 'Login':
        continue
    app.replace_js(pg, 'Auth', [("""			} catch (e) {
				showAlert(Util.cleanError(e && e.message), 'error');
			}
		}
		return true;""", """			} catch (e) {
				const msg = e && e.message;
				if (Util.isSessionError(msg)) {          // R12 (T64)
					await removeValue('token');
					showAlert('Sesi login habis. Silakan login lagi.', 'warning');
					navigateTo('Login');
					return false;
				}
				showAlert(Util.cleanError(msg), 'error');
			}
		}
		return true;""")])

# T64: tombol Cari / filter lewat Util.load (sesi habis -> Login)
for pg, wname, key, q in [
    ('Admin', 'btnAuditCari', 'onClick', 'q_audit'),
    ('Master Supplier', 'btnSupplierCari', 'onClick', 'q_suppliers'),
    ('Master Komponen', 'btnKomponenCari', 'onClick', 'q_components'),
    ('Master Material', 'btnMaterialCari', 'onClick', 'q_materials'),
    ('Master Pilihan', 'selPilihanJenis', 'onOptionChange', 'q_options'),
    ('Master Pilihan', 'btnPilihanCari', 'onClick', 'q_options'),
    ('Model List', 'btnModelCari', 'onClick', 'q_models'),
    ('Model List', 'selModelPabrik', 'onOptionChange', 'q_models'),
]:
    w = app.widget(pg, wname)
    assert w[key] == '{{' + q + '.run()}}', (pg, wname, w[key])
    app.set_prop(pg, wname, key, '{{Util.load(' + q + ')}}', trigger=True)

# ---------------------------------------------------------------- T62: antrean pemuatan Specsheet & CBD
app.set_js('Specsheet', 'SpecCtrl', js('js/SpecCtrl.js'))
app.set_js('Specsheet', 'BomCtrl', js('js/BomCtrl.js'))
app.set_js(CBD, 'CbdCtrl', js('js/CbdCtrl.js'))
app.set_js(CBD, 'CbdGridCtrl', js('js/CbdGridCtrl.js'))
# biaya tambahan disaring per revisi -> kolom cbd_revision_id
q = app.action(CBD, 'q_cbd_cost_items')['unpublishedAction']['actionConfiguration']['body']
old = 'SELECT c.id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order\n'
assert q.count(old) == 1
app.set_query(CBD, 'q_cbd_cost_items', body=q.replace(old, 'SELECT c.id, c.cbd_revision_id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order\n'))

# ---------------------------------------------------------------- T60: gambar riwayat satu per satu, lampiran 3,5 MB
for pg, perm, doc, fac in [('Specsheet', 'view_specsheet', 'SPECSHEET', 'fn_rev_factory'),
                           (CBD, 'view_cbd', 'CBD', 'fn_cbd_factory')]:
    app.set_query(pg, 'q_change_log_images', body=f'''-- R12 (T60): daftar saja - isi gambar lewat q_change_log_image satu per satu
SELECT a.id, a.file_name, a.mime_type, a.size_bytes
FROM change_log_attachment a
JOIN change_log cl ON cl.id = a.change_log_id
WHERE fn_can_see_factory((SELECT fn_auth({TOKEN}, '{perm}')), {fac}(cl.revision_id))
  AND cl.doc_type = '{doc}'
  AND cl.id::text = {{{{this.params.log_id || ''}}}}
ORDER BY a.created_at;''')
    app.add_query(pg, 'q_change_log_image', 'q_change_log_images', f'''-- R12 (T60): isi satu gambar change log (base64)
SELECT a.id, translate(encode(a.content, 'base64'), E'\\n', '') AS data
FROM change_log_attachment a
JOIN change_log cl ON cl.id = a.change_log_id
WHERE fn_can_see_factory((SELECT fn_auth({TOKEN}, '{perm}')), {fac}(cl.revision_id))
  AND cl.doc_type = '{doc}'
  AND a.id::text = {{{{this.params.id || ''}}}};''')
    cw(app, pg, 'cwPublishForm')

app.set_js('Model Detail', 'ModelDetailCtrl', js('js/ModelDetailCtrl.js'))
app.set_prop('Model Detail', 'fpLampiran', 'maxFileSize', 3.5)
w = app.widget('Model Detail', 'txtLampiranInfo')
assert 'maks. 5 MB' in w['text']
w['text'] = w['text'].replace('maks. 5 MB', 'maks. 3,5 MB')

# ---------------------------------------------------------------- T65: override CBD dihapus
app.delete_query(CBD, 'a_cbd_clear_override')
cw(app, CBD, 'cwCbdGrid')

# ---------------------------------------------------------------- T66: ExcelJS tidak dipakai (export = XlsxWriter, T43)
assert [l['name'] for l in d['customJSLibList']] == ['ExcelJS']
d['customJSLibList'] = []
ea = d['exportedApplication']
ea['unpublishedCustomJSLibs'] = [x for x in ea.get('unpublishedCustomJSLibs', []) if 'exceljs' not in x['uidString'].lower()]
ea['publishedCustomJSLibs'] = [x for x in ea.get('publishedCustomJSLibs', []) if 'exceljs' not in x['uidString'].lower()]

# ---------------------------------------------------------------- T67: tanggal export Excel WIB
app.set_js(CBD, 'CbdExportCtrl', js('js/CbdExportCtrl.js'))
app.set_js('Specsheet', 'SpecExportCtrl', js('js/SpecExportCtrl.js'))

# ---------------------------------------------------------------- T68: keseragaman modal & tabel
# Modal berisi form ketikan: klik di luar modal TIDAK menutup (isian tidak hilang)
for pg, m in [('Admin', 'mdlUser'), ('Admin', 'mdlPabrik'), ('Master Supplier', 'mdlSupplier'),
              ('Master Komponen', 'mdlKomponen'), ('Master Material', 'mdlMaterial'), ('Material Detail', 'mdlMaterial'),
              ('Material Detail', 'mdlLink'), ('Material Detail', 'mdlTolakHarga'), ('Master Pilihan', 'mdlPilihan'),
              ('Model Detail', 'mdlSeason'), ('Model Detail', 'mdlArticle')]:
    assert app.widget(pg, m)['type'] == 'MODAL_WIDGET'
    app.set_prop(pg, m, 'canOutsideClickClose', False)
# Kotak cari bawaan tabel: hanya di tabel tanpa kotak cari sendiri. Download: hanya tabel laporan.
app.set_prop('Model List', 'tblModels', 'isVisibleSearch', False)          # sudah ada inpModelCari
app.set_prop(CBD, 'tblCbdRiwayat', 'isVisibleSearch', True)                 # sama dengan tblRiwayat Specsheet
app.set_prop('Model Detail', 'tblLampiran', 'isVisibleDownload', False)     # daftar file, unduh lewat tombol baris

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
