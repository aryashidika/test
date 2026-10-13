# Build R11: salin exports/export_r10.json (= app user setelah R9 + tempelan manual R10) -> edit di tempat
# -> exports/build_r11.json. SQL: sql/R11_perbaikan.sql (jalankan dulu). Isi: PLAN.md §6 R11 + §9 T54–T59, A1, A4.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import (ROOT, TOKEN, rd, resize_modal, lock_manual_queries, copy_widget_to_page, set_binding, text_col_from,
                  table_set_columns)


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def cw(app, page, name):
    app.set_cw_source(page, name, html=rd(f'widgets/{name}/index.html'), css=rd(f'widgets/{name}/style.css'),
                      js=rd(f'widgets/{name}/script.js'))


BASE = f'{ROOT}/exports/export_r10.json'
OUT = f'{ROOT}/exports/build_r11.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R11'
CBD = 'Cost Breakdown (CBD)'

# ---------------------------------------------------------------- Admin: audit 90 hari (S5) + entitas cepat (S6)
app.set_query('Admin', 'q_audit', body=f'''SELECT id, created_at, user_email, entity, entity_id, action, before_data, after_data
FROM audit_log
WHERE (SELECT fn_auth({TOKEN}, 'view_audit')) IS NOT NULL
  AND created_at > now() - interval '90 days'
  AND ({{{{selAuditEntitas.selectedOptionValue || ''}}}} = '' OR entity = {{{{selAuditEntitas.selectedOptionValue || ''}}}})
  AND ({{{{inpAuditCari.text || ''}}}} = ''
       OR user_email ILIKE '%' || {{{{inpAuditCari.text || ''}}}} || '%'
       OR action     ILIKE '%' || {{{{inpAuditCari.text || ''}}}} || '%'
       OR entity_id  ILIKE '%' || {{{{inpAuditCari.text || ''}}}} || '%')
ORDER BY id DESC
LIMIT 200;''')
app.set_query('Admin', 'q_audit_entities', body=f'''-- R11 (S6): daftar entitas lewat index (entity, entity_id), tanpa membaca seluruh audit_log
WITH RECURSIVE e AS (
  SELECT min(entity) AS entity FROM audit_log
  UNION ALL
  SELECT (SELECT min(a.entity) FROM audit_log a WHERE a.entity > e.entity) FROM e WHERE e.entity IS NOT NULL
)
SELECT entity FROM e
WHERE entity IS NOT NULL AND (SELECT fn_auth({TOKEN}, 'view_audit')) IS NOT NULL
ORDER BY entity;''')
app.set_prop('Admin', 'txtAuditInfo', 'text', '{{q_audit.data.length}} catatan terbaru dalam 90 hari terakhir (maks. 200)')

# ---------------------------------------------------------------- Beranda: Query1 buatan user (T59) + audit log (S7/S8)
app.delete_query('Beranda', 'Query1')
app.set_js('Beranda', 'BerandaCtrl', js('js/BerandaCtrl.js'))

# ---------------------------------------------------------------- Model List & Master Material: 500 dari N (S9)
app.set_query('Model List', 'q_models', body=f'''SELECT v.id, v.name, v.category, v.factory_name AS factory, v.gender, v.size_range,
       v.season_count::int AS season_count, v.specsheet_id, v.season, v.article_count::int AS article_count, v.updated_at,
       v.spec_label, v.spec_active_articles::int AS spec_active_articles,
       v.spec_label_pub, v.spec_active_articles_pub::int AS spec_active_articles_pub,
       count(*) OVER () AS total_count
FROM (SELECT fn_auth({TOKEN}, 'view_model') AS me) a
JOIN v_model_list v ON fn_can_see_factory(a.me, v.factory_id)
WHERE (CASE WHEN {{{{selModelSeason.selectedOptionValue || ''}}}} = '' THEN v.is_latest_season
            ELSE v.season = {{{{selModelSeason.selectedOptionValue || ''}}}} END)
  AND ({{{{selModelPabrik.selectedOptionValue || ''}}}} = '' OR v.factory_id::text = {{{{selModelPabrik.selectedOptionValue || ''}}}})
  AND ({{{{inpModelCari.text || ''}}}} = ''
       OR v.name ILIKE '%' || {{{{inpModelCari.text || ''}}}} || '%'
       OR v.factory_name ILIKE '%' || {{{{inpModelCari.text || ''}}}} || '%')
ORDER BY v.name, v.factory_name
LIMIT 500;''')
app.set_query('Master Material', 'q_materials', body=f'''SELECT m.id, m.factory_name, m.name, m.category, m.uom, m.price_method, m.status,
       m.variant_count, m.active_variant_count, m.thicknesses, m.supplier_count, m.preferred_supplier,
       m.updated_at, m.updated_by, count(*) OVER () AS total_count
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
JOIN v_material_list m ON fn_can_see_factory(a.me, m.factory_id)
WHERE ({{{{inpMaterialCari.text || ''}}}} = ''
       OR m.name ILIKE '%' || {{{{inpMaterialCari.text || ''}}}} || '%'
       OR m.category ILIKE '%' || {{{{inpMaterialCari.text || ''}}}} || '%'
       OR m.codes ILIKE '%' || {{{{inpMaterialCari.text || ''}}}} || '%')
  AND ({{{{selMaterialStatus.selectedOptionValue || ''}}}} = '' OR m.status = {{{{selMaterialStatus.selectedOptionValue || ''}}}})
  AND ({{{{selMaterialKategori.selectedOptionValue || ''}}}} = '' OR m.category = {{{{selMaterialKategori.selectedOptionValue || ''}}}})
ORDER BY m.factory_name, m.name_key, m.uom
LIMIT 500;''')
for page, table in (('Model List', 'tblModels'), ('Master Material', 'tblMaterials')):
    t = app.widget(page, table)
    t['primaryColumns']['total_count'] = text_col_from(t['primaryColumns']['id'], table, 'total_count', 'Total', visible=False)
    table_set_columns(t, t['columnOrder'] + ['total_count'])
app.set_js('Model List', 'ModelCtrl', js('js/ModelCtrl.js'))
app.set_js('Master Material', 'MaterialCtrl', js('js/MaterialCtrl.js'))
for page, name, ctrl, top, left in (('Model List', 'txtModelLimit', 'ModelCtrl', 14.0, 38.0),
                                    ('Master Material', 'txtMaterialLimit', 'MaterialCtrl', 19.0, 17.0)):
    w = copy_widget_to_page(app, 'Admin', 'txtAuditInfo', page, {'txtAuditInfo': name})
    w.update(topRow=top, bottomRow=top + 4.0, leftColumn=left, rightColumn=64.0, originalTopRow=top,
             originalBottomRow=top + 4.0, mobileTopRow=top, mobileBottomRow=top + 4.0, mobileLeftColumn=left,
             mobileRightColumn=64.0, textColor='#B45309', minWidth=300.0)
    set_binding(w, 'text', f'{{{{{ctrl}.limitNote()}}}}')

# ---------------------------------------------------------------- Material Detail: pesan Akhiri harga (T54)
app.set_js('Material Detail', 'MaterialDetailCtrl', js('js/MaterialDetailCtrl.js'))

# ---------------------------------------------------------------- Specsheet: Batal ganti (T58); form terbit (kode sama)
cw(app, 'Specsheet', 'cwBomGrid')
cw(app, 'Specsheet', 'cwPublishForm')

# ---------------------------------------------------------------- CBD: Tanpa biaya (A1/T56), rincian perubahan (A4)
app.add_query(CBD, 'a_cbd_no_charge', 'a_cbd_line_set',
              f'''SELECT fn_cbd_set_no_charge({TOKEN}, {{{{this.params.line_id}}}}::uuid, {{{{this.params.on}}}}::boolean,
                            {{{{this.params.reason || ''}}}}) AS id;''')
app.add_query(CBD, 'q_cbd_bridge', 'q_cbd_recap',
              f'''SELECT seq, key, category, category_label, description, amount, prev_label, prev_fob, fob
FROM fn_cbd_bridge_view({TOKEN}, nullif({{{{this.params.revision_id || ''}}}}, '')::uuid)
ORDER BY seq;''')
app.set_query(CBD, 'a_cbd_publish', body=f'''SELECT fn_cbd_publish({TOKEN}, {{{{this.params.revision_id}}}}::uuid,
                      {{{{this.params.category}}}}, {{{{this.params.reason}}}}, {{{{this.params.bridge || '[]'}}}}::jsonb) AS id;''')
for ctrl in ('CbdCtrl', 'CbdGridCtrl', 'CbdExportCtrl'):
    app.set_js(CBD, ctrl, js(f'js/{ctrl}.js'))
cw(app, CBD, 'cwCbdGrid')
cw(app, CBD, 'cwPublishForm')
assert app.widget(CBD, 'mdlCbdTerbit')['children'][0]['children'][0]['widgetName'] == 'cwPublishForm'
resize_modal(app, CBD, 'mdlCbdTerbit', 900, 88)

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
