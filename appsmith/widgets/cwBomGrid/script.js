// cwBomGrid — grid BOM page Specsheet: No, Komponen, Material, Supplier, UoM, Thickness, Remarks + satu kolom per article.
// F10b: sel warna & Remarks = kotak teks yang membungkus (terbaca semua); Remarks boleh beberapa baris (Shift+Enter);
//   saran warna = daftar sendiri (panah atas/bawah lalu Enter memilih saran — ketikan setengah jadi tidak tersimpan);
//   kolom Thickness (dari master material).
// Hanya tampilan & input. Setiap perubahan dikirim sebagai model.action + event onAction (BomCtrl.onAction());
// BomCtrl menjalankan query lalu memuat ulang data. Aturan final di DB (fn_bom_*).
// Teks yang diketik dicocokkan ke master di sini (seperti bom_service.py resolve_*):
//   komponen "10 - Vamp" / "10" / nama unik -> master APPROVED; selain itu komponen lokal (No. wajib)
//   material "KODE · Nama" / kode / nama unik (tidak termasuk INACTIVE); supplier = nama (kosong = tanpa supplier)
const $ = id => document.getElementById(id);
const SEP = ' · ';
let M = {};                 // model terakhir
let seq = 0;
let lastMsg = null;         // object message dari model (untuk mendeteksi pesan baru)
let localMsg = null;        // pesan validasi di widget
let lastOkKey = null;
let subParent = null;       // id baris induk yang sedang dibuka form "+ Sub"
let addState = {};          // isian baris tambah (dipertahankan saat render ulang)
let subState = {};
let dropArmed = null;       // article yang tombol drop-nya menunggu klik kedua
let dropTimer = null;
let delArmed = null;        // baris yang tombol Hapus-nya menunggu klik kedua
let delTimer = null;

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

// = fn_normalize: huruf kecil, koma -> titik, spasi dirapatkan, trim
function norm(s) {
  return String(s ?? '').toLowerCase().replace(/,/g, '.').replace(/\s+/g, ' ').trim();
}

function tidy(s) {
  return String(s ?? '').replace(/\s+/g, ' ').trim();
}

// Remarks: baris dipertahankan, spasi di dalam baris dirapatkan, baris kosong dibuang
function tidyLines(s) {
  return String(s ?? '').split(/\r?\n/).map(x => x.replace(/\s+/g, ' ').trim()).filter(x => x).join('\n');
}

// Tinggi kotak teks mengikuti isi
function autosize(t) {
  if (!t || t.tagName !== 'TEXTAREA') return;
  t.style.height = 'auto';
  t.style.height = `${t.scrollHeight + 2}px`;
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = text;
  return e;
}

// ---------------------------------------------------------------- master & saran
const compLabel = c => `${c.number} - ${c.name}`;
const matLabel = m => `${m.code}${SEP}${m.name}`;

function resolveComponent(text) {
  const key = norm(text);
  if (!key) return { error: 'Komponen wajib diisi.' };
  const comps = M.components || [];
  let c = comps.find(x => norm(compLabel(x)) === key);
  if (c) return { comp: c };
  if (/^\d+$/.test(key)) {
    c = comps.find(x => Number(x.number) === Number(key));
    return c ? { comp: c } : { error: `Komponen nomor ${key} tidak ada di master. Untuk komponen baru, ketik namanya lalu isi No.` };
  }
  const byName = comps.filter(x => norm(x.name) === key);
  return byName.length === 1 ? { comp: byName[0] } : { local: tidy(text) };
}

function resolveMaterial(text) {
  const raw = tidy(text);
  if (!raw) return { error: 'Material wajib diisi.' };
  const key = norm(raw);
  const codePart = norm(raw.split(SEP.trim())[0]);
  const mats = M.materials || [];
  const m = mats.find(x => norm(matLabel(x)) === key || norm(x.code) === key || norm(x.code) === codePart);
  if (m) return { mat: m };
  const byName = mats.filter(x => norm(x.name) === key);
  if (byName.length === 1) return { mat: byName[0] };
  if (byName.length > 1) return { error: `Ada beberapa material bernama "${raw}". Pilih dari daftar supaya kodenya ikut terisi.` };
  return { error: `Material "${raw}" tidak ada di master (atau INACTIVE). Pilih dari daftar, atau daftarkan dulu di Master Material.` };
}

function resolveSupplier(text) {
  const raw = tidy(text);
  if (!raw) return { id: null };
  const s = (M.suppliers || []).find(x => norm(x.name) === norm(raw));
  return s ? { id: s.id } : { error: `Supplier "${raw}" tidak ada di Master Supplier (atau nonaktif).` };
}

function linksOf(materialId) {
  return (M.links || []).filter(l => l.material_id === materialId);
}

// Supplier utama, atau satu-satunya supplier aktif material ini
function defaultSupplier(materialId) {
  const active = linksOf(materialId).filter(l => l.status !== 'INACTIVE');
  const pref = active.find(l => l.is_preferred) || (active.length === 1 ? active[0] : null);
  if (!pref) return '';
  const s = (M.suppliers || []).find(x => x.id === pref.supplier_id);
  return s ? s.name : '';
}

// Datalist supplier per material: supplier terdaftar dulu (utama paling atas), link INACTIVE tidak ditawarkan
function supplierListId(materialId) {
  const id = `dlSup-${materialId || 'all'}`;
  if (document.getElementById(id)) return id;
  const links = materialId ? linksOf(materialId) : [];
  const byId = {};
  links.forEach(l => { byId[l.supplier_id] = l; });
  const linked = [];
  const others = [];
  (M.suppliers || []).forEach(s => {
    const l = byId[s.id];
    if (l && l.status === 'INACTIVE') return;
    (l ? linked : others).push({ s, l });
  });
  linked.sort((a, b) => (b.l.is_preferred ? 1 : 0) - (a.l.is_preferred ? 1 : 0) || a.s.name.localeCompare(b.s.name));
  const dl = el('datalist');
  dl.id = id;
  linked.concat(others).forEach(({ s, l }) => {
    const o = el('option');
    o.value = s.name;
    if (l) o.textContent = l.is_preferred ? 'utama' : (l.status === 'PROPOSED' ? 'terdaftar (usulan)' : 'terdaftar');
    dl.appendChild(o);
  });
  $('dlSuppliers').appendChild(dl);
  return id;
}

function fillDatalists() {
  const fill = (dl, items) => {
    dl.innerHTML = '';
    items.forEach(([v, t]) => {
      const o = el('option');
      o.value = v;
      if (t) o.textContent = t;
      dl.appendChild(o);
    });
  };
  fill($('dlComponents'), (M.components || []).map(c => [compLabel(c)]));
  fill($('dlMaterials'), (M.materials || []).map(m =>
    [matLabel(m), [m.uom, m.thickness, m.status === 'PROPOSED' ? 'usulan' : ''].filter(x => x).join(' · ')]));
  fill($('dlColors'), (M.colors || []).map(c => [c]));
  $('dlSuppliers').innerHTML = '';
}

// ---------------------------------------------------------------- aksi
function send(type, data) {
  localMsg = null;
  showMessage();
  seq += 1;
  appsmith.updateModel({ action: Object.assign({ type, seq }, data) });
  appsmith.triggerEvent('onAction');
}

function fail(input, text) {
  if (input) input.classList.add('invalid');
  localMsg = { type: 'error', text };
  showMessage();
}

function showMessage() {
  const m = localMsg || M.message;
  const box = $('msg');
  if (!m || !m.text) {
    box.hidden = true;
    box.textContent = '';
    return;
  }
  box.className = `msg ${m.type || 'info'}`;
  box.textContent = m.text;
  box.hidden = false;
}

// Input sel yang disimpan saat berubah (change = Enter / Tab / klik di luar).
// opts.multiline: kotak teks yang membungkus · opts.keepLines: Shift/Alt+Enter = baris baru (Remarks)
// · opts.suggest: daftar saran sendiri (warna)
function cellInput(key, value, opts) {
  const multi = !!(opts.multiline || opts.keepLines);
  const i = el(multi ? 'textarea' : 'input', 'cell');
  if (multi) {
    i.rows = 1;
    i.spellcheck = false;
    i.addEventListener('input', () => autosize(i));
  } else {
    i.type = 'text';
  }
  i.autocomplete = 'off';
  i.value = value || '';
  const clean = opts.keepLines ? tidyLines : tidy;
  i.dataset.key = key;
  i.dataset.orig = i.value;
  if (opts.col) i.dataset.col = opts.col;
  if (opts.list) i.setAttribute('list', opts.list);
  if (opts.placeholder) i.placeholder = opts.placeholder;
  if (opts.title) i.title = opts.title;
  if (opts.label) i.setAttribute('aria-label', opts.label);
  i.addEventListener('input', () => i.classList.remove('invalid'));
  if (opts.onCommit) {
    i.addEventListener('change', () => {
      if (!i.isConnected) return;              // elemen sudah diganti render ulang: jangan simpan ketikan setengah jadi
      if (clean(i.value) === clean(i.dataset.orig)) return;
      opts.onCommit(i);
    });
  }
  if (opts.suggest) attachSuggest(i, opts.suggest);
  i.addEventListener('keydown', e => {
    if (e.defaultPrevented) return;            // sudah ditangani daftar saran
    if (e.key === 'Escape') {
      i.value = i.dataset.orig;
      i.classList.remove('invalid');
      autosize(i);
      i.blur();
    } else if (e.key === 'Enter' && opts.keepLines && (e.shiftKey || e.altKey)) {
      if (e.altKey) {                          // Alt+Enter seperti Excel
        e.preventDefault();
        const p = i.selectionStart;
        i.value = `${i.value.slice(0, p)}\n${i.value.slice(i.selectionEnd)}`;
        i.setSelectionRange(p + 1, p + 1);
        autosize(i);
      }                                        // Shift+Enter: baris baru bawaan kotak teks
    } else if (e.key === 'Enter' && multi && !opts.col) {
      e.preventDefault();                      // baris tambah/sub: Enter ditangani formRow
    } else if (e.key === 'Enter' && opts.col) {
      e.preventDefault();
      moveDown(i);
    }
  });
  return i;
}

// ---------------------------------------------------------------- daftar saran (warna)
let sugTarget = null;
let sugItems = [];
let sugIndex = -1;

function hideSuggest() {
  sugTarget = null;
  sugItems = [];
  sugIndex = -1;
  $('suggest').hidden = true;
}

function showSuggest(input, source) {
  const key = norm(input.value);
  const all = typeof source === 'function' ? source() : (source || []);
  sugItems = all.filter(c => norm(c) !== key && (!key || norm(c).includes(key))).slice(0, 8);
  sugTarget = input;
  sugIndex = -1;
  const box = $('suggest');
  box.innerHTML = '';
  if (!sugItems.length) {
    box.hidden = true;
    return;
  }
  sugItems.forEach((c, n) => {
    const o = el('div', 'opt', c);
    o.addEventListener('mousedown', e => {     // mousedown: sebelum kotak teks kehilangan fokus
      e.preventDefault();
      pickSuggest(n);
    });
    box.appendChild(o);
  });
  const r = input.getBoundingClientRect();
  box.style.left = `${Math.max(0, Math.min(r.left, window.innerWidth - 260))}px`;
  box.style.minWidth = `${Math.max(r.width, 180)}px`;
  box.hidden = false;
  const below = window.innerHeight - r.bottom;
  if (below < box.offsetHeight + 4 && r.top > box.offsetHeight) {
    box.style.top = `${r.top - box.offsetHeight - 2}px`;
  } else {
    box.style.top = `${r.bottom + 2}px`;
  }
}

function markSuggest() {
  Array.from($('suggest').children).forEach((o, n) => o.classList.toggle('on', n === sugIndex));
}

function pickSuggest(n) {
  const input = sugTarget;
  if (!input || !sugItems[n]) return;
  input.value = sugItems[n];
  autosize(input);
  hideSuggest();
}

function attachSuggest(input, source) {
  input.addEventListener('focus', () => showSuggest(input, source));
  input.addEventListener('input', () => showSuggest(input, source));
  input.addEventListener('blur', () => { if (sugTarget === input) hideSuggest(); });
  input.addEventListener('keydown', e => {
    if (sugTarget !== input || $('suggest').hidden) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const n = sugItems.length;
      sugIndex = e.key === 'ArrowDown' ? (sugIndex + 1) % n : (sugIndex - 1 + n) % n;
      markSuggest();
    } else if (e.key === 'Enter' && sugIndex >= 0) {
      pickSuggest(sugIndex);                   // Enter tetap lanjut: simpan & pindah ke baris berikutnya
    } else if (e.key === 'Escape') {
      e.preventDefault();
      hideSuggest();
    }
  });
}

// Enter di sel -> simpan (blur) lalu pindah ke sel yang sama di baris berikutnya
function moveDown(input) {
  const inputs = Array.from(document.querySelectorAll(`#tbody .cell[data-col="${input.dataset.col}"]`));
  const next = inputs[inputs.indexOf(input) + 1];
  if (next) {
    next.focus();
    next.select();
  } else {
    input.blur();
  }
}

function commitMaterial(line, input) {
  const r = resolveMaterial(input.value);
  if (r.error) return fail(input, r.error);
  if (r.mat.id === line.material_id) {
    input.value = input.dataset.orig;
    return;
  }
  input.dataset.orig = input.value;
  send('replaceMaterial', { line_id: line.id, material_id: r.mat.id });
}

function commitSupplier(line, input) {
  const r = resolveSupplier(input.value);
  if (r.error) return fail(input, r.error);
  if ((r.id || null) === (line.supplier_id || null)) {
    input.value = input.dataset.orig;
    return;
  }
  input.dataset.orig = input.value;
  send('setSupplier', { line_id: line.id, supplier_id: r.id || '' });
}

function commitProcess(line, input) {
  input.dataset.orig = input.value;
  send('setProcess', { line_id: line.id, process: tidyLines(input.value) });
}

function commitCell(line, article, input) {
  input.dataset.orig = input.value;
  send('setCell', { line_id: line.id, article_id: article.id, color: tidy(input.value) });
}

function armDrop(btn, art) {
  if (dropArmed === art.id) {
    clearTimeout(dropTimer);
    dropArmed = null;
    send('dropArticle', { article_id: art.id });
    return;
  }
  dropArmed = art.id;
  btn.classList.add('confirm');
  btn.textContent = 'Drop?';
  clearTimeout(dropTimer);
  dropTimer = setTimeout(() => {
    dropArmed = null;
    const b = document.querySelector(`#thead .drop[data-art="${art.id}"]`);
    if (b) {
      b.classList.remove('confirm');
      b.textContent = '✕';
    }
  }, 3000);
}

// Hapus baris: klik pertama -> "Yakin?" (3 detik), klik kedua -> kirim. Baris induk ikut menghapus subkomponennya.
function armDelete(btn, line, hasSubs) {
  if (delArmed === line.id) {
    clearTimeout(delTimer);
    delArmed = null;
    send('deleteLine', { line_id: line.id });
    return;
  }
  delArmed = line.id;
  btn.classList.add('confirm');
  btn.textContent = hasSubs ? 'Hapus + sub?' : 'Yakin?';
  clearTimeout(delTimer);
  delTimer = setTimeout(() => {
    delArmed = null;
    const b = document.querySelector(`#tbody .link.danger[data-line="${line.id}"]`);
    if (b) {
      b.classList.remove('confirm');
      b.textContent = 'Hapus';
    }
  }, 3000);
}

// ---------------------------------------------------------------- baris tambah & subkomponen
// Input yang dipakai baris tambah/sub: komponen/nama, No., material, supplier, remarks
function formInputs(prefix, state, isSub) {
  const f = {};
  const mk = (name, opts) => {
    const i = cellInput(`${prefix}:${name}`, state[name] || '', opts);
    i.addEventListener('input', () => { state[name] = i.value; });
    f[name] = i;
    return i;
  };
  if (isSub) {
    mk('name', { placeholder: 'Nama subkomponen', label: 'Nama subkomponen' });
  } else {
    mk('comp', { list: 'dlComponents', placeholder: 'Ketik komponen…', label: 'Komponen' });
    mk('no', { placeholder: 'No.', label: 'No. komponen lokal', title: 'Hanya untuk komponen baru yang tidak ada di master' });
  }
  mk('mat', { list: 'dlMaterials', placeholder: 'Kode / nama material…', label: 'Material' });
  mk('sup', { list: supplierListId(null), placeholder: 'Supplier…', label: 'Supplier' });
  mk('rem', { placeholder: 'Remarks', label: 'Remarks', keepLines: true, title: 'Shift+Enter / Alt+Enter = baris baru' });
  f.uom = el('span', 'ro none', '-');
  f.thk = el('span', 'ro none', '-');

  const syncMaterial = () => {
    const r = resolveMaterial(f.mat.value);
    const mat = r.mat || null;
    f.uom.textContent = mat ? mat.uom : '-';
    f.thk.textContent = mat && mat.thickness ? mat.thickness : '-';
    f.sup.setAttribute('list', supplierListId(mat ? mat.id : null));
    if (mat && !tidy(f.sup.value)) {
      f.sup.value = defaultSupplier(mat.id);
      state.sup = f.sup.value;
    }
  };
  f.mat.addEventListener('change', syncMaterial);
  if (state.mat) syncMaterial();

  if (!isSub) {
    const syncLocal = () => {
      const r = resolveComponent(f.comp.value);
      f.no.disabled = !r.local;
      if (!r.local) {
        f.no.value = '';
        state.no = '';
      }
    };
    f.comp.addEventListener('input', syncLocal);
    f.comp.addEventListener('change', syncLocal);
    syncLocal();
  }
  return f;
}

function submitAdd(f) {
  Object.values(f).forEach(i => i.classList && i.classList.remove('invalid'));
  const c = resolveComponent(f.comp.value);
  if (c.error) return fail(f.comp, c.error);
  const data = { component_id: '', local_no: '', local_name: '' };
  if (c.comp) {
    data.component_id = c.comp.id;
  } else {
    const no = tidy(f.no.value);
    if (!/^\d+$/.test(no)) return fail(f.no, `"${c.local}" tidak ada di master komponen — isi No. (angka) untuk komponen lokal ini.`);
    if (Number(no) % 10 === 0) return fail(f.no, 'No. komponen lokal tidak boleh kelipatan 10.');
    data.local_no = no;
    data.local_name = c.local;
  }
  const m = resolveMaterial(f.mat.value);
  if (m.error) return fail(f.mat, m.error);
  const s = resolveSupplier(f.sup.value);
  if (s.error) return fail(f.sup, s.error);
  send('addLine', Object.assign(data, { material_id: m.mat.id, supplier_id: s.id || '', process: tidyLines(f.rem.value) }));
}

function submitSub(parent, f) {
  Object.values(f).forEach(i => i.classList && i.classList.remove('invalid'));
  if (!tidy(f.name.value)) return fail(f.name, 'Nama subkomponen wajib diisi.');
  const m = resolveMaterial(f.mat.value);
  if (m.error) return fail(f.mat, m.error);
  const s = resolveSupplier(f.sup.value);
  if (s.error) return fail(f.sup, s.error);
  send('addSub', {
    parent_id: parent.id, sub_name: tidy(f.name.value), material_id: m.mat.id,
    supplier_id: s.id || '', process: tidyLines(f.rem.value),
  });
}

// ---------------------------------------------------------------- render
function td(cls, child) {
  const c = el('td', cls);
  if (child !== undefined) c.appendChild(typeof child === 'string' ? el('span', 'ro', child) : child);
  return c;
}

function supplierCell(line, editable) {
  const c = el('td', 'c-sup');
  if (editable) {
    c.appendChild(cellInput(`sup:${line.id}`, line.supplier_name, {
      col: 'sup', list: supplierListId(line.material_id), placeholder: 'Supplier…', label: 'Supplier',
      onCommit: i => commitSupplier(line, i),
    }));
  } else {
    c.appendChild(el('span', 'ro' + (line.supplier_name ? '' : ' none'), line.supplier_name || '-'));
  }
  if (line.supplier_id && line.supplier_status === 'PROPOSED') {
    const b = el('span', 'badge proposed', 'supplier usulan');
    b.title = 'Supplier baru — menunggu approval Master Admin. Specsheet baru bisa terbit setelah disetujui.';
    c.appendChild(b);
  } else if (line.supplier_id && line.link_status === 'PROPOSED') {
    const b = el('span', 'badge proposed', 'usulan');
    b.title = 'Kombinasi material + supplier ini baru — menunggu approval Master Admin. Specsheet baru bisa terbit setelah disetujui.';
    c.appendChild(b);
  } else if (line.supplier_id && line.link_status === 'INACTIVE') {
    const b = el('span', 'badge inactive', '⚠ nonaktif');
    b.title = 'Supplier ini sudah dinonaktifkan untuk material ini — pilih supplier lain.';
    c.appendChild(b);
  }
  return c;
}

function materialCell(line, editable) {
  const c = el('td', 'c-mat');
  const label = `${line.material_code}${SEP}${line.material_name}`;
  const title = [line.thickness, line.uom].filter(x => x).join(' · ');
  if (editable) {
    c.appendChild(cellInput(`mat:${line.id}`, label, {
      col: 'mat', list: 'dlMaterials', title: `${title}. Ketik material lain untuk Ganti Material.`, label: 'Material',
      onCommit: i => commitMaterial(line, i),
    }));
  } else {
    const s = el('span', 'ro', label);
    s.title = title;
    c.appendChild(s);
  }
  if (line.material_status === 'INACTIVE') c.appendChild(el('span', 'badge inactive', '⚠ material INACTIVE'));
  else if (line.material_status === 'PROPOSED') c.appendChild(el('span', 'badge proposed', 'material usulan'));
  return c;
}

function lineRow(line, arts, editable, hasSubs) {
  const tr = el('tr', line.is_sub ? 'sub' : '');
  tr.appendChild(td('c-no', String(line.display_no ?? '')));
  const comp = el('td', 'c-comp');
  const name = el('span', 'ro name', line.display_name || '');
  if (line.is_local) name.appendChild(el('span', 'local', 'lokal'));
  comp.appendChild(name);
  tr.appendChild(comp);
  tr.appendChild(materialCell(line, editable));
  tr.appendChild(supplierCell(line, editable));
  tr.appendChild(td('c-uom', line.uom || '-'));
  tr.appendChild(td('c-thk', line.thickness || '-'));
  const rem = el('td', 'c-rem');
  if (editable) {
    rem.appendChild(cellInput(`rem:${line.id}`, line.process, {
      col: 'rem', placeholder: '', label: 'Remarks', keepLines: true,
      title: 'Shift+Enter / Alt+Enter = baris baru · Enter = simpan', onCommit: i => commitProcess(line, i),
    }));
  } else {
    rem.appendChild(el('span', 'ro lines' + (line.process ? '' : ' none'), line.process || '-'));
  }
  tr.appendChild(rem);
  if (editable) {
    const act = el('td', 'c-act');
    if (!line.is_sub) {
      const b = el('button', 'link', '+ Sub');
      b.type = 'button';
      b.title = 'Tambah subkomponen di bawah baris ini';
      b.addEventListener('click', () => {
        subParent = subParent === line.id ? null : line.id;
        subState = {};
        render(M, true);
        const first = document.querySelector('tr.subform input');
        if (first) first.focus();
      });
      act.appendChild(b);
    }
    const del = el('button', 'link danger', delArmed === line.id ? (hasSubs ? 'Hapus + sub?' : 'Yakin?') : 'Hapus');
    if (delArmed === line.id) del.classList.add('confirm');
    del.type = 'button';
    del.dataset.line = line.id;
    del.title = hasSubs ? 'Hapus baris ini beserta subkomponennya (klik dua kali)' : 'Hapus baris ini (klik dua kali)';
    del.addEventListener('click', () => armDelete(del, line, hasSubs));
    act.appendChild(del);
    tr.appendChild(act);
  }
  const cells = typeof line.cells === 'string' ? JSON.parse(line.cells || '{}') : (line.cells || {});
  arts.forEach(a => {
    const c = el('td', 'c-art');
    const v = cells[a.id] || '';
    if (editable) {
      c.appendChild(cellInput(`cell:${line.id}:${a.id}`, v, {
        col: `art:${a.id}`, multiline: true, suggest: () => M.colors || [], label: `Warna ${a.code}`,
        onCommit: i => commitCell(line, a, i),
      }));
    } else {
      c.appendChild(el('span', 'ro' + (v ? '' : ' none'), v || '-'));
    }
    tr.appendChild(c);
  });
  return tr;
}

function formRow(cls, f, first, button, cancel, arts) {
  const tr = el('tr', cls);
  tr.appendChild(td('c-no', first.no || el('span')));
  const comp = el('td', 'c-comp');
  comp.appendChild(first.comp);
  if (first.hint) comp.appendChild(el('span', 'hint', first.hint));
  tr.appendChild(comp);
  const mat = el('td', 'c-mat');
  mat.appendChild(f.mat);
  tr.appendChild(mat);
  const sup = el('td', 'c-sup');
  sup.appendChild(f.sup);
  tr.appendChild(sup);
  const uom = el('td', 'c-uom');
  uom.appendChild(f.uom);
  tr.appendChild(uom);
  const thk = el('td', 'c-thk');
  thk.appendChild(f.thk);
  tr.appendChild(thk);
  const rem = el('td', 'c-rem');
  rem.appendChild(f.rem);
  tr.appendChild(rem);
  const act = el('td', 'c-act');
  act.appendChild(button);
  if (cancel) act.appendChild(cancel);
  tr.appendChild(act);
  arts.forEach(() => tr.appendChild(el('td', 'c-art')));
  [f.mat, f.sup, f.rem, first.input, f.no].forEach(i => i && i.addEventListener('keydown', e => {
    if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
      e.preventDefault();
      button.click();
    }
  }));
  return tr;
}

function render(model, keepState) {
  // simpan fokus, scroll, dan ketikan yang belum disimpan
  const active = document.activeElement;
  const focusKey = active && active.dataset ? active.dataset.key : null;
  const selStart = focusKey && typeof active.selectionStart === 'number' ? active.selectionStart : null;
  const dirty = {};
  document.querySelectorAll('#tbody .cell[data-key]').forEach(i => {
    if (i.value !== i.dataset.orig && !/^(add|sub):/.test(i.dataset.key)) dirty[i.dataset.key] = i.value;
  });
  hideSuggest();
  const scroll = $('scroll');
  const pos = [scroll.scrollLeft, scroll.scrollTop];

  M = model || {};
  if (!keepState) {
    if (M.message !== lastMsg) {
      lastMsg = M.message;
      localMsg = null;
    }
    if (M.okKey !== lastOkKey) {
      if (lastOkKey !== null) {     // aksi tambah berhasil -> kosongkan form
        addState = {};
        subState = {};
        subParent = null;
      }
      lastOkKey = M.okKey;
    }
  }
  const editable = !!M.editable;
  const arts = M.articles || [];
  const lines = M.lines || [];
  fillDatalists();

  // header
  const thead = $('thead');
  thead.innerHTML = '';
  const hr = el('tr');
  [['c-no', 'No'], ['c-comp', 'Komponen'], ['c-mat', 'Material'], ['c-sup', 'Supplier'], ['c-uom', 'UoM'], ['c-thk', 'Thickness'], ['c-rem', 'Remarks']]
    .forEach(([c, t]) => hr.appendChild(el('th', c, t)));
  if (editable) hr.appendChild(el('th', 'c-act', ''));
  arts.forEach(a => {
    const th = el('th', 'c-art');
    const box = el('div', 'art-head');
    const txt = el('span');
    txt.appendChild(el('span', 'art-code', a.code));
    txt.appendChild(el('span', 'art-cw', a.colorway));
    box.appendChild(txt);
    if (editable) {
      const b = el('button', 'drop', dropArmed === a.id ? 'Drop?' : '✕');
      if (dropArmed === a.id) b.classList.add('confirm');
      b.type = 'button';
      b.dataset.art = a.id;
      b.title = `Drop article ${a.code} dari revisi ini (klik dua kali)`;
      b.addEventListener('click', () => armDrop(b, a));
      box.appendChild(b);
    }
    th.appendChild(box);
    hr.appendChild(th);
  });
  thead.appendChild(hr);

  // isi
  const tbody = $('tbody');
  tbody.innerHTML = '';
  const cols = 7 + (editable ? 1 : 0) + arts.length;
  if (!lines.length && !editable) {
    const tr = el('tr');
    const c = el('td', 'empty', M.emptyText || 'Belum ada baris BOM.');
    c.colSpan = cols;
    tr.appendChild(c);
    tbody.appendChild(tr);
  }
  const parents = new Set(lines.filter(l => l.is_sub).map(l => l.parent_line_key));
  lines.forEach(line => {
    tbody.appendChild(lineRow(line, arts, editable, !line.is_sub && parents.has(line.line_key)));
    if (editable && subParent === line.id) {
      const f = formInputs('sub', subState, true);
      const ok = el('button', 'btn', 'Tambah');
      ok.type = 'button';
      ok.disabled = !!M.busy;
      ok.addEventListener('click', () => submitSub(line, f));
      const cancel = el('button', 'link muted', 'Batal');
      cancel.type = 'button';
      cancel.addEventListener('click', () => { subParent = null; subState = {}; render(M, true); });
      tbody.appendChild(formRow('subform', f, { comp: f.name, input: f.name }, ok, cancel, arts));
    }
  });
  if (editable) {
    const f = formInputs('add', addState, false);
    const ok = el('button', 'btn', '+ Tambah');
    ok.type = 'button';
    ok.disabled = !!M.busy;
    ok.addEventListener('click', () => submitAdd(f));
    tbody.appendChild(formRow('add', f, {
      no: f.no, comp: f.comp, input: f.comp,
      hint: 'Tidak ada di master → komponen lokal, isi No. (bukan kelipatan 10).',
    }, ok, null, arts));
  }

  // pulihkan ketikan, fokus, scroll
  document.querySelectorAll('#tbody .cell[data-key]').forEach(i => {
    if (dirty[i.dataset.key] !== undefined) i.value = dirty[i.dataset.key];
    autosize(i);
  });
  if (focusKey) {
    const i = document.querySelector(`#tbody [data-key="${CSS.escape(focusKey)}"]`);
    if (i && !i.disabled) {
      i.focus();
      if (selStart !== null) {
        try { i.setSelectionRange(selStart, selStart); } catch (e) { /* abaikan */ }
      }
    }
  }
  scroll.scrollLeft = pos[0];
  scroll.scrollTop = pos[1];

  const n = lines.length;
  $('status').textContent = (M.busy ? 'Menyimpan… · ' : '')
    + `${n} baris · ${arts.length} article` + (editable ? '' : ' · hanya baca');
  showMessage();
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  $('scroll').addEventListener('scroll', hideSuggest);
  render(appsmith.model);
  appsmith.onModelChange(m => render(m));
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
