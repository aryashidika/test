# Build R5: salin build_r4.json -> edit di tempat -> exports/build_r5.json
# CBD per varian (status harga menunggu, blokir terbit), PO SMS, simulasi harga jual Brand, penjaga pabrik CBD.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, wr, sub1, lock_manual_queries

BASE = f'{ROOT}/exports/build_r4.json'
OUT = f'{ROOT}/exports/build_r5.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R5'
AUTH = "(SELECT fn_auth({{appsmith.store.token}}, '%s')) IS NOT NULL"


def guard(page, name, perm, factory_expr, extra=None):
    body = app.action(page, name)['unpublishedAction']['actionConfiguration']['body']
    body = sub1(body, f'WHERE {AUTH % perm}', f"WHERE fn_can_see_factory((SELECT fn_auth({TOKEN}, '{perm}')), {factory_expr})",
                f'{page}/{name}')
    for old, new in (extra or []):
        body = sub1(body, old, new, f'{page}/{name}')
    app.set_query(page, name, body=body)


PG = 'Cost Breakdown (CBD)'
guard(PG, 'q_cbd_seasons', 'view_cbd', 'fn_model_factory(s.model_id)')
guard(PG, 'q_cbd_articles', 'view_cbd', 'fn_sheet_factory(v.specsheet_id)')
guard(PG, 'q_cbd_revisions', 'view_cbd', 'fn_article_factory(r.article_id)')
guard(PG, 'q_cbd_lines', 'view_cbd', 'fn_cbd_factory(g.cbd_revision_id)',
      [('pc.master_price, pc.master_currency', 'pc.master_price, pc.master_currency, coalesce(pc.pending, false) AS pending')])
guard(PG, 'q_cbd_sources', 'edit_cbd', 'fn_model_factory(sh.model_id)')
guard(PG, 'q_cbd_recap', 'view_cbd', 'fn_cbd_factory(v.cbd_revision_id)')
guard(PG, 'q_cbd_checklist', 'edit_cbd', 'fn_cbd_factory(cbd_revision_id)')
guard(PG, 'q_cbd_change_log', 'view_cbd', 'fn_article_factory(r.article_id)')
guard(PG, 'q_cbd_cost_items', 'view_cbd', 'fn_cbd_factory(c.cbd_revision_id)')
guard(PG, 'q_change_log_images', 'view_cbd', 'fn_cbd_factory(cl.revision_id)')
for n in ('CbdGridCtrl', 'CbdCtrl', 'CbdExportCtrl'):
    app.set_js(PG, n, rd(f'js/{n}.js'))
app.set_cw_source(PG, 'cwCbdGrid', js=rd('widgets/cwCbdGrid/script.js'))

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
