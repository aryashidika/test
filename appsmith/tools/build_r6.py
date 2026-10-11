# Build R6: salin build_r5.json -> edit di tempat -> exports/build_r6.json
# Tugas Saya (usulan ditolak, sel kuning, harga menunggu), filter pabrik Brand di Model List, sapu bersih pabrik.
import copy, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, sub1, lock_manual_queries

BASE = f'{ROOT}/exports/build_r5.json'
OUT = f'{ROOT}/exports/build_r6.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R6'

# ================================================================ Beranda
PG = 'Beranda'
app.add_query(PG, 'q_worklist_rejected', 'q_worklist_gap', f'''SELECT w.*
FROM (SELECT fn_auth({TOKEN}, 'edit_cbd') AS me) a
JOIN v_worklist_price_rejected w ON fn_can_see_factory(a.me, w.factory_id)
ORDER BY w.decided_at DESC;''')
for q in ('q_worklist_pub_spec', 'q_worklist_pub_cbd'):
    body = app.action(PG, q)['unpublishedAction']['actionConfiguration']['body']
    perm = 'view_specsheet' if q.endswith('spec') else 'view_cbd'
    body = sub1(body, f"(SELECT fn_auth({TOKEN}, '{perm}')) IS NOT NULL",
                f"fn_can_see_factory((SELECT fn_auth({TOKEN}, '{perm}')), factory_id)", q)
    app.set_query(PG, q, body=body)
app.set_js(PG, 'BerandaCtrl', rd('js/BerandaCtrl.js'))

# ================================================================ Model List: filter pabrik (Brand / System Admin)
PG = 'Model List'
app.add_query(PG, 'q_model_factories', 'q_known_seasons', f'''SELECT f.id, f.name
FROM factory f
WHERE (SELECT fn_auth({TOKEN}, 'view_model')) IS NOT NULL AND f.status = 'ACTIVE'
ORDER BY f.name;''')
body = app.action(PG, 'q_models')['unpublishedAction']['actionConfiguration']['body']
body = sub1(body, "  AND ({{inpModelCari.text || ''}} = ''",
            "  AND ({{selModelPabrik.selectedOptionValue || ''}} = '' OR v.factory_id::text = {{selModelPabrik.selectedOptionValue || ''}})\n"
            "  AND ({{inpModelCari.text || ''}} = ''", 'q_models')
app.set_query(PG, 'q_models', body=body)
app.set_js(PG, 'ModelCtrl', rd('js/ModelCtrl.js'))
app.replace_js(PG, 'Auth', [('return [q_known_seasons, q_models];', 'return [q_known_seasons, q_model_factories, q_models];')])
w = app.clone_widget(PG, 'selModelSeason', 'selModelPabrik')
w.update(sourceData='{{ModelCtrl.factoryOptions()}}', defaultOptionValue='', placeholderText='Semua pabrik',
         isVisible='{{ModelCtrl.canFilterFactory()}}', onOptionChange='{{q_models.run()}}',
         topRow=14.0, bottomRow=18.0, leftColumn=17.0, rightColumn=37.0,
         mobileTopRow=14.0, mobileBottomRow=18.0, mobileLeftColumn=17.0, mobileRightColumn=37.0)
for lk, key in (('dynamicBindingPathList', 'isVisible'), ('dynamicTriggerPathList', 'onOptionChange'),
                ('dynamicPropertyPathList', 'onOptionChange')):
    lst = w.setdefault(lk, [])
    if not any(x['key'] == key for x in lst):
        lst.append({'key': key})
app.note('Model List: selModelPabrik (hanya user tanpa pabrik) + q_model_factories, q_models difilter pabrik terpilih')

# ================================================================ CBD export: nama pabrik
app.set_js('Cost Breakdown (CBD)', 'CbdExportCtrl', rd('js/CbdExportCtrl.js'))

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
