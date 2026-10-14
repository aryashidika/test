// cwPriceApproval - page Persetujuan Harga (R3, Manager Costing). Hanya tampilan; keputusan lewat
// ApprovalCtrl.decide() -> fn_price_decide (semua atau tidak sama sekali, aturan final di DB).
// Model masuk: { loaded, loading, busy, message, focusBatch,
//   batches: [{ batch_id, material_id, material_name, uom, proposed_by, proposed_at,
//     items: [{ id, code, color, thickness_label, supplier_name, price, currency, valid_from, reference,
//               cur_price, cur_currency, cur_valid_from, problem }] }] }
// Event keluar: onDecide (setelah updateModel({ action: { decision: 'APPROVE'|'REJECT', ids, reason, batch_id } })),
//   onOpenMaterial (setelah updateModel({ material_id })), onRefresh.
// Usulan ber-"problem" tidak bisa disetujui (DB menolak) - hanya bisa ditolak.

const $ = id => document.getElementById(id);
const selected = new Map();   // batch_id -> Set(id)
const rejectOpen = new Map(); // batch_id -> teks alasan (ada = panel tolak terbuka)
let armed = null;             // { batch, kind } tombol setujui yang menunggu klik kedua
let armTimer = null;
let busy = false;
let lastFocus = null;
let lastModel = {};

function applyTheme(theme) {
  const t = theme || {};
  const root = document.documentElement.style;
  if (t.primaryColor) root.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) root.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') {
    root.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
  }
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = String(text);
  return e;
}

function fmt(n) {
  return Number(n).toLocaleString('id-ID', { minimumFractionDigits: 0, maximumFractionDigits: 4 });
}

function fmtDate(iso) {
  const [y, m, d] = String(iso || '').slice(0, 10).split('-');
  return d ? `${d}-${m}-${y}` : '-';
}

function fmtDateTime(iso) {
  const t = new Date(iso);
  if (isNaN(t)) return '-';
  const p = n => String(n).padStart(2, '0');
  return `${p(t.getDate())}-${p(t.getMonth() + 1)}-${t.getFullYear()} ${p(t.getHours())}:${p(t.getMinutes())}`;
}

function diffCell(it) {
  const td = el('td', 'num');
  if (it.cur_price === null || it.cur_price === undefined || it.cur_price === '') {
    td.textContent = 'baru';
    return td;
  }
  if (it.cur_currency !== it.currency) {
    td.textContent = 'different currency';
    return td;
  }
  const pct = (Number(it.price) - Number(it.cur_price)) / Number(it.cur_price) * 100;
  const span = el('span', pct > 0 ? 'up' : pct < 0 ? 'down' : '', `${pct > 0 ? '+' : ''}${pct.toFixed(1).replace('.', ',')}%`);
  td.appendChild(span);
  return td;
}

function sel(batchId) {
  if (!selected.has(batchId)) selected.set(batchId, new Set());
  return selected.get(batchId);
}

function decide(batch, decision, ids, reason) {
  if (busy || !ids.length) return;
  armed = null;
  appsmith.updateModel({ action: { decision, ids, reason: reason || '', batch_id: batch.batch_id } });
  appsmith.triggerEvent('onDecide');
}

// Klik pertama = "mempersenjatai" tombol (teks berubah), klik kedua dalam 5 detik = jalankan
function armOrRun(batch, kind, run) {
  if (armed && armed.batch === batch.batch_id && armed.kind === kind) {
    clearTimeout(armTimer);
    run();
    return;
  }
  armed = { batch: batch.batch_id, kind };
  clearTimeout(armTimer);
  armTimer = setTimeout(() => {
    armed = null;
    renderBatches(lastModel);
  }, 5000);
  renderBatches(lastModel);
}

function batchCard(b, focus) {
  const items = b.items || [];
  const s = sel(b.batch_id);
  const okIds = items.filter(it => !it.problem).map(it => it.id);
  const chosen = items.filter(it => s.has(it.id));
  const chosenBad = chosen.some(it => it.problem);
  const card = el('div', 'card' + (focus ? ' focus' : ''));
  card.id = 'b-' + b.batch_id;

  const head = el('div', 'card-head');
  const left = el('div');
  left.appendChild(el('h3', '', `${b.material_name}${b.uom ? ' (' + b.uom + ')' : ''}`));
  const suppliers = [...new Set(items.map(it => it.supplier_name))].join(', ');
  left.appendChild(el('div', 'meta',
    `Proposed by ${b.proposed_by || '-'} · ${fmtDateTime(b.proposed_at)} · ${items.length} price(s) · Supplier ${suppliers}`));
  const openBtn = el('button', 'link', 'Open material →');
  openBtn.type = 'button';
  openBtn.addEventListener('click', () => {
    appsmith.updateModel({ material_id: b.material_id });
    appsmith.triggerEvent('onOpenMaterial');
  });
  head.append(left, openBtn);
  card.appendChild(head);

  const wrap = el('div', 'table-wrap');
  const table = el('table');
  const thead = el('thead');
  const hr = el('tr');
  const thAll = el('th');
  const all = document.createElement('input');
  all.type = 'checkbox';
  all.title = 'Select all';
  all.checked = items.length > 0 && chosen.length === items.length;
  all.disabled = busy;
  all.addEventListener('change', () => {
    items.forEach(it => (all.checked ? s.add(it.id) : s.delete(it.id)));
    renderBatches(lastModel);
  });
  thAll.appendChild(all);
  hr.appendChild(thAll);
  [['Material Code'], ['Color'], ['Thickness'], ['Supplier'], ['Active price', 'num'], ['Proposal', 'num'],
   ['Difference', 'num'], ['Valid from'], ['Reference'], ['']].forEach(([t, c]) => hr.appendChild(el('th', c || '', t)));
  thead.appendChild(hr);
  table.appendChild(thead);
  const tbody = el('tbody');
  items.forEach(it => {
    const tr = el('tr', (s.has(it.id) ? 'sel' : '') + (it.problem ? ' bad' : ''));
    const td0 = el('td');
    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = s.has(it.id);
    cb.disabled = busy;
    cb.addEventListener('change', () => {
      if (cb.checked) s.add(it.id);
      else s.delete(it.id);
      renderBatches(lastModel);
    });
    td0.appendChild(cb);
    tr.appendChild(td0);
    tr.appendChild(el('td', '', it.code));
    tr.appendChild(el('td', '', it.color));
    tr.appendChild(el('td', '', it.thickness_label));
    tr.appendChild(el('td', '', it.supplier_name));
    tr.appendChild(el('td', 'num', it.cur_price !== null && it.cur_price !== undefined && it.cur_price !== ''
      ? `${fmt(it.cur_price)} ${it.cur_currency} (${fmtDate(it.cur_valid_from)})` : '-'));
    const tdNew = el('td', 'num');
    tdNew.appendChild(el('b', '', `${fmt(it.price)} ${it.currency}`));
    tr.appendChild(tdNew);
    tr.appendChild(diffCell(it));
    tr.appendChild(el('td', '', fmtDate(it.valid_from)));
    const ref = el('td', 'ref', it.reference || '-');
    ref.title = it.reference || '';
    tr.appendChild(ref);
    const tdP = el('td');
    if (it.problem) tdP.appendChild(el('span', 'badge', it.problem));
    tr.appendChild(tdP);
    tbody.appendChild(tr);
  });
  table.appendChild(tbody);
  wrap.appendChild(table);
  card.appendChild(wrap);

  const acts = el('div', 'actions');
  const bad = items.length - okIds.length;
  acts.appendChild(el('span', 'hint', bad
    ? `${bad} proposal(s) cannot be approved (see the red note). Reject them.`
    : 'The old price stays active until the proposal is approved.'));

  const isArmed = kind => armed && armed.batch === b.batch_id && armed.kind === kind;
  const btnAll = el('button', 'btn primary' + (isArmed('all') ? ' armed' : ''),
    isArmed('all') ? `Click again: approve ${okIds.length} price(s)` : (bad ? `Approve valid ones (${okIds.length})` : `Approve all (${okIds.length})`));
  btnAll.type = 'button';
  btnAll.disabled = busy || okIds.length === 0;
  btnAll.addEventListener('click', () => armOrRun(b, 'all', () => decide(b, 'APPROVE', okIds)));

  const selIds = chosen.map(it => it.id);
  const btnSel = el('button', 'btn' + (isArmed('sel') ? ' armed' : ''),
    isArmed('sel') ? `Click again: approve ${selIds.length} price(s)` : `Approve selected (${selIds.length})`);
  btnSel.type = 'button';
  btnSel.disabled = busy || selIds.length === 0 || chosenBad;
  if (chosenBad) btnSel.title = 'The selection has proposals that cannot be approved.';
  btnSel.addEventListener('click', () => armOrRun(b, 'sel', () => decide(b, 'APPROVE', selIds)));

  const btnRej = el('button', 'btn danger', `Reject selected (${selIds.length})`);
  btnRej.type = 'button';
  btnRej.disabled = busy || selIds.length === 0;
  btnRej.addEventListener('click', () => {
    armed = null;
    if (!rejectOpen.has(b.batch_id)) rejectOpen.set(b.batch_id, '');
    renderBatches(lastModel);
    const ta = document.getElementById('r-' + b.batch_id);
    if (ta) ta.focus();
  });
  acts.append(btnSel, btnRej, btnAll);
  card.appendChild(acts);

  if (rejectOpen.has(b.batch_id)) {
    const box = el('div', 'reject');
    const lbl = el('label', '', `Reject reason for ${selIds.length} selected price(s) (required)`);
    lbl.htmlFor = 'r-' + b.batch_id;
    const ta = document.createElement('textarea');
    ta.id = 'r-' + b.batch_id;
    ta.maxLength = 300;
    ta.placeholder = 'e.g. Price does not match the latest quotation';
    ta.value = rejectOpen.get(b.batch_id);
    ta.disabled = busy;
    const ra = el('div', 'actions');
    const cancel = el('button', 'btn', 'Cancel');
    cancel.type = 'button';
    cancel.disabled = busy;
    cancel.addEventListener('click', () => {
      rejectOpen.delete(b.batch_id);
      renderBatches(lastModel);
    });
    const ok = el('button', 'btn danger solid', `Reject ${selIds.length} price(s)`);
    ok.type = 'button';
    const sync = () => {
      ok.disabled = busy || selIds.length === 0 || ta.value.trim() === '';
    };
    ta.addEventListener('input', () => {
      rejectOpen.set(b.batch_id, ta.value);
      sync();
    });
    sync();
    ok.addEventListener('click', () => decide(b, 'REJECT', selIds, ta.value.trim()));
    ra.append(cancel, ok);
    box.append(lbl, ta, ra);
    card.appendChild(box);
  }
  return card;
}

function renderBatches(m) {
  const box = $('batches');
  const batches = m.batches || [];
  // buang pilihan / panel milik usulan yang sudah tidak ada (sudah diproses)
  const live = new Map(batches.map(b => [b.batch_id, new Set((b.items || []).map(it => it.id))]));
  [...selected.keys()].forEach(k => {
    if (!live.has(k)) selected.delete(k);
    else [...selected.get(k)].forEach(id => { if (!live.get(k).has(id)) selected.get(k).delete(id); });
  });
  [...rejectOpen.keys()].forEach(k => { if (!live.has(k) || !selected.get(k) || !selected.get(k).size) rejectOpen.delete(k); });

  const ordered = [...batches].sort((a, b) => (b.batch_id === m.focusBatch) - (a.batch_id === m.focusBatch));
  box.innerHTML = '';
  ordered.forEach(b => box.appendChild(batchCard(b, b.batch_id === m.focusBatch)));
}

function render(model) {
  const m = model || {};
  lastModel = m;
  busy = !!m.busy;
  const batches = m.batches || [];
  const total = batches.reduce((n, b) => n + (b.items || []).length, 0);
  $('subtitle').textContent = m.loaded
    ? (batches.length ? `${batches.length} submission(s) · ${total} price(s) waiting for your approval.` : '')
    : 'Loading…';
  $('refresh').disabled = !!m.loading || busy;
  $('refresh').textContent = m.loading ? 'Loading…' : '↻ Reload';
  const msg = $('msg');
  if (m.message && m.message.text) {
    msg.className = `msg ${m.message.type || 'info'}`;
    msg.textContent = m.message.text;
    msg.hidden = false;
  } else {
    msg.hidden = true;
  }
  $('loading').hidden = !!m.loaded;
  $('batches').hidden = !m.loaded || !batches.length;
  $('none').hidden = !m.loaded || batches.length > 0;
  if (m.loaded) renderBatches(m);
  if (m.loaded && m.focusBatch && m.focusBatch !== lastFocus) {
    lastFocus = m.focusBatch;
    const card = document.getElementById('b-' + m.focusBatch);
    if (card) card.scrollIntoView({ block: 'start' });
  }
}

appsmith.onReady(() => {
  $('refresh').addEventListener('click', () => appsmith.triggerEvent('onRefresh'));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
