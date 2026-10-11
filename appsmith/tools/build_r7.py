# Build R7: salin build_r6.json -> edit di tempat -> exports/build_r7.json (build yang di-import)
# Copy lintas model: wizard Buat Revisi (model lain, pabrik & kategori sama), sumber copy CBD dari model asal.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, wr, sub1, resize_modal, lock_manual_queries

BASE = f'{ROOT}/exports/build_r6.json'
OUT = f'{ROOT}/exports/build_r7.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R7'

# ================================================================ Specsheet
PG = 'Specsheet'
app.add_query(PG, 'q_copy_model_sources', 'q_spec_seasons', f'''SELECT sh.id, pm.name AS model_name, oo.value AS outsole_mold, sh.season,
       r.stage || ' r' || r.revision_no AS label,
       (SELECT count(*)::int FROM bom_line l WHERE l.revision_id = r.id AND l.is_active) AS line_count
FROM (SELECT fn_auth({TOKEN}, 'edit_specsheet') AS me) a
JOIN product_model t ON t.id::text = {{{{this.params.model_id || ''}}}} AND fn_can_see_factory(a.me, t.factory_id)
JOIN product_model pm ON pm.factory_id = t.factory_id AND pm.category_id = t.category_id AND pm.id <> t.id
JOIN specsheet sh ON sh.model_id = pm.id
JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
LEFT JOIN model_option oo ON oo.id = pm.outsole_mold_id
ORDER BY pm.name_key, sh.season_sort DESC;''')
body = app.action(PG, 'q_revisions')['unpublishedAction']['actionConfiguration']['body']
body = sub1(body, "src.stage || ' r' || src.revision_no AS source_label, srcsp.season AS source_season",
            "src.stage || ' r' || src.revision_no AS source_label, srcsp.season AS source_season,\n"
            "       CASE WHEN srcsp.model_id IS DISTINCT FROM (SELECT x.model_id FROM specsheet x WHERE x.id = r.specsheet_id)\n"
            "            THEN (SELECT pm.name FROM product_model pm WHERE pm.id = srcsp.model_id) END AS source_model", 'q_revisions')
app.set_query(PG, 'q_revisions', body=body)
app.set_js(PG, 'SpecCtrl', rd('js/SpecCtrl.js'))
app.set_cw_source(PG, 'cwRevisionForm', html=rd('widgets/cwRevisionForm/index.html'), js=rd('widgets/cwRevisionForm/script.js'))
w = app.widget(PG, 'cwRevisionForm')
resize_modal(app, PG, 'mdlRevisi', int(app.widget(PG, 'mdlRevisi')['height']) + 120, int(w['bottomRow'] - w['topRow']) + 12)

# ================================================================ CBD: sumber copy = model sama + model asal specsheet
PG = 'Cost Breakdown (CBD)'
app.set_query(PG, 'q_cbd_sources', body=f'''SELECT a.id, a.code, a.colorway, sh.season, p.stage || ' r' || p.revision_no AS label,
       fn_cbd_article_spec_status(a.id) = 'DROPPED' AS dropped,
       pm.name AS model_name, (sh.model_id <> t.model_id) AS is_cross
FROM (SELECT fn_auth({TOKEN}, 'edit_cbd') AS me) x
JOIN article ta ON ta.id::text = {{{{this.params.article_id || ''}}}}
JOIN specsheet t ON t.id = ta.specsheet_id AND fn_can_see_factory(x.me, fn_model_factory(t.model_id))
JOIN specsheet sh ON sh.model_id = t.model_id OR sh.model_id = fn_sheet_origin_model(t.id)
JOIN product_model pm ON pm.id = sh.model_id
JOIN article a ON a.specsheet_id = sh.id AND a.id <> ta.id
JOIN LATERAL (
  SELECT r.stage, r.revision_no FROM cbd_revision r
   WHERE r.article_id = a.id AND r.status = 'PUBLISHED'
   ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
) p ON true
ORDER BY (sh.model_id <> t.model_id), sh.season_sort DESC, a.code;''')
app.set_js(PG, 'CbdCtrl', rd('js/CbdCtrl.js'))

# ================================================================ sumber widget final ke repo
for pg, n in (('Specsheet', 'cwRevisionForm'), ('Cost Breakdown (CBD)', 'cwCbdGrid'), ('Material Detail', 'cwPriceForm'),
              ('Persetujuan Harga', 'cwPriceApproval')):
    s = app.widget(pg, n)['uncompiledSrcDoc']
    for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
        wr(f'widgets/{n}/{fn}', s[part])

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
