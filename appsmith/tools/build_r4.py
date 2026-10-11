# Build R4: salin build_r3.json -> edit di tempat -> exports/build_r4.json
# Model tanpa kode (dropdown, grid ukuran), penjaga pabrik di Model / Specsheet, BOM per varian (sel kuning,
# Daftarkan varian, + Supplier baru), export specsheet dengan Material Code.
import copy, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import (ROOT, TOKEN, rd, wr, sub1, add_event, set_binding, resize_modal, text_col_from, table_set_columns,
                  copy_widget_to_page, lock_manual_queries)

BASE = f'{ROOT}/exports/build_r3.json'
OUT = f'{ROOT}/exports/build_r4.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R4'

AUTH_VIEW = "(SELECT fn_auth({{appsmith.store.token}}, '%s')) IS NOT NULL"


def guard(page, name, perm, factory_expr):
    """WHERE (SELECT fn_auth(...)) IS NOT NULL -> WHERE fn_can_see_factory((SELECT fn_auth(...)), <pabrik>)"""
    body = app.action(page, name)['unpublishedAction']['actionConfiguration']['body']
    body = sub1(body, AUTH_VIEW % perm,
                f"fn_can_see_factory((SELECT fn_auth({TOKEN}, '{perm}')), {factory_expr})", f'{page}/{name}')
    app.set_query(page, name, body=body)


OPTIONS_Q = f'''SELECT o.id, o.kind, o.value, o.status
FROM (SELECT fn_auth({TOKEN}, 'view_model') AS me) a
JOIN model_option o ON o.factory_id IS NULL OR fn_can_see_factory(a.me, o.factory_id)
ORDER BY o.kind, o.sort_order NULLS LAST, o.value_key;'''
MODEL_SAVE_ARGS = '''{{this.params.name}}, nullif({{this.params.category_id || ''}}, '')::uuid,
                     nullif({{this.params.construction_id || ''}}, '')::uuid, nullif({{this.params.gender_id || ''}}, '')::uuid,
                     nullif({{this.params.last_id || ''}}, '')::uuid, nullif({{this.params.outsole_mold_id || ''}}, '')::uuid,
                     {{this.params.sizes || '[]'}}::jsonb, nullif({{this.params.sample_size || ''}}, '')::integer'''


def model_form(page, ctrl_default, ctrl_save):
    w = app.widget(page, 'cwModelForm')
    old_css = w['uncompiledSrcDoc']['css']
    css = rd('widgets/cwModelForm/style.css')
    app.set_cw_source(page, 'cwModelForm', html=rd('widgets/cwModelForm/index.html'),
                      js=rd('widgets/cwModelForm/script.js'), css=css)
    set_binding(w, 'defaultModel', ctrl_default)
    w['onSave'] = ctrl_save
    resize_modal(app, page, 'mdlModel', 720, 70)
    assert old_css.strip() in css, 'style.css cwModelForm harus = css lama + tambahan R4'


# ================================================================ Model List
PG = 'Model List'
app.set_query(PG, 'q_models', body=f'''SELECT v.id, v.name, v.category, v.factory_name AS factory, v.gender, v.size_range,
       v.season_count::int AS season_count, v.specsheet_id, v.season, v.article_count::int AS article_count, v.updated_at,
       v.spec_label, v.spec_active_articles::int AS spec_active_articles,
       v.spec_label_pub, v.spec_active_articles_pub::int AS spec_active_articles_pub
FROM (SELECT fn_auth({TOKEN}, 'view_model') AS me) a
JOIN v_model_list v ON fn_can_see_factory(a.me, v.factory_id)
WHERE (CASE WHEN {{{{selModelSeason.selectedOptionValue || ''}}}} = '' THEN v.is_latest_season
            ELSE v.season = {{{{selModelSeason.selectedOptionValue || ''}}}} END)
  AND ({{{{inpModelCari.text || ''}}}} = ''
       OR v.name ILIKE '%' || {{{{inpModelCari.text || ''}}}} || '%'
       OR v.factory_name ILIKE '%' || {{{{inpModelCari.text || ''}}}} || '%')
ORDER BY v.name, v.factory_name
LIMIT 500;''')
guard(PG, 'q_known_seasons', 'view_model', 'fn_model_factory(model_id)')
app.set_query(PG, 'a_model_add', body=f'''SELECT fn_model_save({TOKEN}, NULL, {MODEL_SAVE_ARGS}) AS id;''')
app.add_query(PG, 'q_model_options', 'q_known_seasons', OPTIONS_Q)
app.set_js(PG, 'ModelCtrl', rd('js/ModelCtrl.js'))
model_form(PG, '{{ModelCtrl.formModel()}}', '{{ModelCtrl.save()}}')
t = app.widget(PG, 'tblModels')
pc = t['primaryColumns']
del pc['code']
pc['factory']['label'] = 'Pabrik'
pc['name']['label'] = 'Model'
pc['size_range']['label'] = 'Ukuran'
pc['gender'] = text_col_from(pc['category'], 'tblModels', 'gender', 'Gender', 110.0)
order = [k for k in t['columnOrder'] if k != 'code']
order.insert(order.index('category') + 1, 'gender')
table_set_columns(t, order)
app.note('tblModels: kolom Kode dihapus, Factory -> Pabrik, + Gender')

# ================================================================ Model Detail
PG = 'Model Detail'
app.set_query(PG, 'q_model', body=f'''SELECT m.id, m.name, m.factory_name, m.category, m.gender, m.construction, m.last_no,
       m.outsole_mold, m.size_range, m.sample_size, m.sizes::text AS sizes, m.category_id, m.construction_id,
       m.gender_id, m.last_id, m.outsole_mold_id, m.updated_at, m.updated_by
FROM (SELECT fn_auth({TOKEN}, 'view_model') AS me) a
JOIN v_model m ON m.id::text = {{{{appsmith.URL.queryParams.id || ''}}}} AND fn_can_see_factory(a.me, m.factory_id);''')
guard(PG, 'q_seasons', 'view_model', 'fn_model_factory(s.model_id)')
guard(PG, 'q_articles', 'view_model', 'fn_model_factory(v.model_id)')
guard(PG, 'q_attachments', 'view_model', 'fn_article_factory(article_id)')
guard(PG, 'q_attachment_file', 'view_model', 'fn_article_factory(article_id)')
app.set_query(PG, 'a_model_update', body=f'''SELECT fn_model_save({TOKEN}, {{{{this.params.id}}}}::uuid, {MODEL_SAVE_ARGS}) AS id;''')
app.set_query(PG, 'a_season_add', body=f'''SELECT fn_season_add({TOKEN}, {{{{this.params.model_id}}}}::uuid, {{{{this.params.season}}}}) AS id;''')
app.set_query(PG, 'a_article_add', body=f'''SELECT fn_article_save({TOKEN}, NULL, {{{{this.params.specsheet_id}}}}::uuid, {{{{this.params.code}}}},
                       {{{{this.params.colorway}}}}) AS id;''')
app.set_query(PG, 'a_article_update', body=f'''SELECT fn_article_save({TOKEN}, {{{{this.params.id}}}}::uuid, NULL, {{{{this.params.code}}}},
                       {{{{this.params.colorway}}}}) AS id;''')
app.set_query(PG, 'a_article_delete', body=f'''SELECT fn_article_delete({TOKEN}, {{{{this.params.id}}}}::uuid) AS id;''')
app.set_query(PG, 'a_attachment_delete', body=f'''SELECT fn_attachment_delete({TOKEN}, {{{{this.params.id}}}}::uuid) AS id;''')
app.add_query(PG, 'q_model_options', 'q_seasons', OPTIONS_Q)
app.set_js(PG, 'ModelDetailCtrl', rd('js/ModelDetailCtrl.js'))
model_form(PG, '{{ModelDetailCtrl.modelFormModel()}}', '{{ModelDetailCtrl.saveModel()}}')

# ================================================================ Specsheet
PG = 'Specsheet'
app.set_query(PG, 'q_spec_models', body=f'''SELECT m.id, m.name, m.factory_name
FROM (SELECT fn_auth({TOKEN}, 'view_specsheet') AS me) a
JOIN v_model m ON fn_can_see_factory(a.me, m.factory_id)
ORDER BY m.name_key, m.factory_name;''')
app.set_query(PG, 'q_spec_model', body=f'''SELECT m.id, m.name, m.factory_name, m.factory, m.category, m.gender, m.outsole_mold,
       m.last_no, m.construction, m.size_range, m.sample_size
FROM (SELECT fn_auth({TOKEN}, 'view_specsheet') AS me) a
JOIN v_model m ON m.id::text = {{{{this.params.model_id || ''}}}} AND fn_can_see_factory(a.me, m.factory_id);''')
body = app.action(PG, 'q_spec_seasons')['unpublishedAction']['actionConfiguration']['body']
body = sub1(body, f"WHERE {AUTH_VIEW % 'view_specsheet'}\n  AND s.model_id",
            f"WHERE fn_can_see_factory((SELECT fn_auth({TOKEN}, 'view_specsheet')), fn_model_factory(s.model_id))\n  AND s.model_id", PG)
app.set_query(PG, 'q_spec_seasons', body=body)
guard(PG, 'q_revisions', 'view_specsheet', 'fn_sheet_factory(r.specsheet_id)')
guard(PG, 'q_rev_articles', 'view_specsheet', 'fn_sheet_factory(a.specsheet_id)')
guard(PG, 'q_bom_grid', 'view_specsheet', 'fn_rev_factory(g.revision_id)')
guard(PG, 'q_season_colors', 'view_specsheet', 'fn_sheet_factory(sp.id)')
guard(PG, 'q_change_log', 'view_specsheet', 'fn_rev_factory(cl.revision_id)')
guard(PG, 'q_change_log_images', 'view_specsheet', 'fn_rev_factory(cl.revision_id)')
guard(PG, 'q_publish_checklist', 'edit_specsheet', 'fn_rev_factory(revision_id)')
app.set_query(PG, 'q_bom_options', body=f'''SELECT
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'number', c.number, 'name', c.name) ORDER BY c.number), '[]'::jsonb)
     FROM component c WHERE c.status = 'ACTIVE') AS components,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('material_id', x.material_id, 'name', x.name, 'uom', x.uom,
                                                'thickness', x.thickness, 'variant_count', x.n)
                             ORDER BY x.name, x.thickness NULLS FIRST), '[]'::jsonb)
     FROM (SELECT m.id AS material_id, m.name, m.uom, v.thickness, count(v.id) AS n
             FROM material m
             LEFT JOIN material_variant v ON v.material_id = m.id AND v.status = 'ACTIVE'
            WHERE m.status = 'ACTIVE' AND m.factory_id = fn_user_factory(a.me)
            GROUP BY m.id, m.name, m.uom, v.thickness) x) AS materials,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'code', v.code, 'material_id', v.material_id,
                                                'material_name', m.name, 'thickness', v.thickness, 'color', v.color)
                             ORDER BY v.code), '[]'::jsonb)
     FROM material_variant v JOIN material m ON m.id = v.material_id
    WHERE v.status = 'ACTIVE' AND m.status = 'ACTIVE' AND v.factory_id = fn_user_factory(a.me)) AS variants,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) ORDER BY s.name_key), '[]'::jsonb)
     FROM supplier s WHERE s.status = 'ACTIVE') AS suppliers,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('material_id', ms.material_id, 'supplier_id', ms.supplier_id,
                                                'is_preferred', ms.is_preferred, 'status', ms.status)), '[]'::jsonb)
     FROM material_supplier ms JOIN material m ON m.id = ms.material_id
    WHERE m.factory_id = fn_user_factory(a.me)) AS links
FROM (SELECT fn_auth({TOKEN}, 'edit_specsheet') AS me) a;''')
app.set_query(PG, 'a_bom_add_line', body=f'''SELECT fn_bom_add_line({TOKEN}, {{{{this.params.revision_id}}}}::uuid,
                       nullif({{{{this.params.component_id}}}}, '')::uuid, nullif({{{{this.params.local_no}}}}, '')::integer,
                       {{{{this.params.local_name}}}}, {{{{this.params.material_id}}}}::uuid, {{{{this.params.thickness || ''}}}},
                       nullif({{{{this.params.supplier_id}}}}, '')::uuid, {{{{this.params.process}}}},
                       {{{{this.params.fill_color || ''}}}}) AS id;''')
app.set_query(PG, 'a_bom_add_sub', body=f'''SELECT fn_bom_add_sub({TOKEN}, {{{{this.params.parent_id}}}}::uuid, {{{{this.params.sub_name}}}},
                      {{{{this.params.material_id}}}}::uuid, {{{{this.params.thickness || ''}}}},
                      nullif({{{{this.params.supplier_id}}}}, '')::uuid, {{{{this.params.process}}}}) AS id;''')
app.set_query(PG, 'a_bom_replace_material', body=f'''SELECT fn_bom_replace_material({TOKEN}, {{{{this.params.line_id}}}}::uuid,
                               {{{{this.params.material_id}}}}::uuid, {{{{this.params.thickness || ''}}}}) AS id;''')
app.set_query(PG, 'a_bom_set_process', body=f'''SELECT fn_bom_set_process({TOKEN}, {{{{this.params.line_id}}}}::uuid,
                          {{{{this.params.process || ''}}}}) AS id;''')
# query modal Daftarkan varian & + Supplier baru (body sama dengan page Material Detail / Master Supplier)
for name, tpl, src_page in (('a_variant_save', 'a_cell_save', 'Material Detail'), ('q_code_hint', 'q_bom_options', 'Material Detail'),
                            ('a_supplier_insert', 'a_cell_save', 'Master Supplier'), ('q_similar', 'q_bom_options', 'Master Supplier')):
    app.add_query(PG, name, tpl, app.action(src_page, name)['unpublishedAction']['actionConfiguration']['body'])
for n in ('BomCtrl', 'SpecCtrl', 'SpecExportCtrl'):
    app.set_js(PG, n, rd(f'js/{n}.js'))
app.set_cw_source(PG, 'cwBomGrid', html=rd('widgets/cwBomGrid/index.html'), css=rd('widgets/cwBomGrid/style.css'),
                  js=rd('widgets/cwBomGrid/script.js'))

# modal Daftarkan varian (salinan mdlVarian Material Detail)
copy_widget_to_page(app, 'Material Detail', 'mdlVarian', PG,
                    {'mdlVarian': 'mdlVarianBaru', 'CanvasVarian': 'CanvasVarianBaru'})
w = app.widget(PG, 'cwVariantForm')
set_binding(w, 'defaultModel', '{{BomCtrl.variantFormModel()}}')
w['onSave'] = '{{BomCtrl.saveVariant()}}'
w['onCancel'] = "{{closeModal('mdlVarianBaru')}}"
add_event(w, 'onLookup', '{{BomCtrl.lookupVariantCode()}}')
resize_modal(app, PG, 'mdlVarianBaru', 560, 55)
# modal + Supplier baru (salinan mdlSupplier Master Supplier)
copy_widget_to_page(app, 'Master Supplier', 'mdlSupplier', PG,
                    {'mdlSupplier': 'mdlSupplierBaru', 'Canvas1': 'CanvasSupplierBaru'})
w = app.widget(PG, 'cwSupplierForm')
set_binding(w, 'defaultModel', '{{BomCtrl.supplierFormModel()}}')
w['onSave'] = '{{BomCtrl.saveSupplier()}}'
w['onCancel'] = "{{closeModal('mdlSupplierBaru')}}"
add_event(w, 'onSearch', '{{BomCtrl.searchSimilar()}}')
m = app.widget(PG, 'mdlSupplierBaru')
m['canOutsideClickClose'] = False

# ================================================================ Material Detail: cwVariantForm (opsi fixed)
for pg in ('Material Detail', 'Specsheet'):
    w = app.widget(pg, 'cwVariantForm')
    app.set_cw_source(pg, 'cwVariantForm', js=rd('widgets/cwVariantForm/script.js'))

# ================================================================ Cost Breakdown (CBD): model tanpa kode
PG = 'Cost Breakdown (CBD)'
app.set_query(PG, 'q_cbd_models', body=f'''SELECT m.id, m.name, m.factory_name
FROM (SELECT fn_auth({TOKEN}, 'view_cbd') AS me) a
JOIN v_model m ON fn_can_see_factory(a.me, m.factory_id)
ORDER BY m.name_key, m.factory_name;''')
app.set_query(PG, 'q_cbd_model', body=f'''SELECT m.id, m.name, m.factory_name, m.factory, m.category, m.gender, m.outsole_mold,
       m.last_no, m.construction, m.size_range, m.sample_size
FROM (SELECT fn_auth({TOKEN}, 'view_cbd') AS me) a
JOIN v_model m ON m.id::text = {{{{this.params.model_id || ''}}}} AND fn_can_see_factory(a.me, m.factory_id);''')
for n in ('CbdCtrl', 'CbdExportCtrl'):
    app.set_js(PG, n, rd(f'js/{n}.js'))

# ================================================================ Beranda: worklist per pabrik, tanpa kode model
PG = 'Beranda'
for q, view, perm, order in (('q_worklist_spec', 'v_worklist_spec', 'edit_specsheet', 'w.model_name, w.season'),
                             ('q_worklist_cbd', 'v_worklist_cbd', 'edit_cbd', 'w.model_name, w.season, w.article_code'),
                             ('q_worklist_gap', 'v_worklist_price_gap', 'edit_cbd', 'w.material_name, w.supplier_name')):
    app.set_query(PG, q, body=f'''SELECT w.*
FROM (SELECT fn_auth({TOKEN}, '{perm}') AS me) a
JOIN {view} w ON fn_can_see_factory(a.me, w.factory_id)
ORDER BY {order};''')
app.set_js(PG, 'BerandaCtrl', rd('js/BerandaCtrl.js'))

# ================================================================ simpan sumber widget final ke repo
for pg, n in (('Specsheet', 'cwBomGrid'), ('Model List', 'cwModelForm'), ('Specsheet', 'cwVariantForm')):
    s = app.widget(pg, n)['uncompiledSrcDoc']
    for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
        wr(f'widgets/{n}/{fn}', s[part])

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
