// cwPublishForm — modal Terbitkan revisi: Specsheet (mdlTerbit, F6) dan CBD (mdlCbdTerbit, F8). Hanya tampilan;
// checklist dihitung di DB (v_revision_checklist / v_cbd_checklist) dan disusun <Page>Ctrl.publishFormModel().
// Terbit lewat SpecCtrl.publish() / CbdCtrl.publish() (checklist, kategori, dan alasan dicek lagi di DB).
// F10b: gambar opsional (tempel Ctrl+V / pilih file; PNG/JPG, maks. model.maxImages) -> model.images
//   [{ name, data (base64 tanpa awalan) }]; dilampirkan ke change log oleh <Page>Ctrl setelah terbit.
// R11 (A4, hanya CBD): model.bridge = rincian perubahan [{ key, category, description, amount }] + model.bridgeInfo
//   { prevLabel, prevFob, fob }. Bila ada: tabel rincian (kategori & uraian boleh diubah, nilai dari DB) menggantikan
//   pilihan kategori, alasan jadi opsional; hasil -> model.bridge [{ key, category, description }].
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let blocked = false;
let requiresReason = true;
let images = [];           // { name, type, size, data, url }
let maxImages = 5;
// R12 (T60): gambar > 1 MB diperkecil di browser (sisi terpanjang maks. 2000 px, JPEG 85%) sebelum dikirim.
// Batas setelah diperkecil = 3,5 MB (sama dengan fn_change_log_attach); file asli boleh sampai 20 MB.
const MAX_BYTES = 3.5 * 1024 * 1024;
const MAX_INPUT = 20 * 1024 * 1024;
const SHRINK_OVER = 1024 * 1024;
const MAX_SIDE = 2000;
let bridge = [];             // R11: [{ key, category, description, amount }] — isian kategori/uraian user
let categories = [];

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

function showMessage(m) {
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

function renderChecks(m) {
  const list = $('checks');
  list.innerHTML = '';
  const checks = m.checks || [];
  checks.forEach(c => {
    const li = document.createElement('li');
    li.className = c.ok ? 'ok' : (c.blocking ? 'fail' : 'warn');
    li.innerHTML = '<span class="icon" aria-hidden="true"></span><div><strong></strong><div class="detail"></div></div>';
    li.querySelector('.icon').textContent = c.ok ? '✓' : (c.blocking ? '✕' : '!');
    li.querySelector('strong').textContent = c.label;
    li.querySelector('.detail').textContent = c.detail || '';
    li.querySelector('.detail').hidden = !c.detail;
    list.appendChild(li);
  });
  const failed = checks.filter(c => c.blocking && !c.ok).length;
  blocked = !!m.blocked || failed > 0 || !checks.length;
  $('blocked').textContent = !checks.length ? 'Checklist belum termuat. Tutup lalu buka lagi.'
    : `Perbaiki ${failed} hal di atas ${m.blockedWhere || 'di grid BOM'} sebelum terbit.`;
  $('blocked').hidden = !blocked;
  $('formBox').hidden = blocked;
  $('btnSave').hidden = blocked;
}

// Isi ulang hanya saat modal dibuka (key berubah) — busy/message tidak menghapus isian user
function fillForm(m) {
  $('title').textContent = m.title || 'Terbitkan Revisi';
  categories = m.categories || [];
  const sel = $('category');
  sel.innerHTML = '<option value="">— pilih kategori —</option>';
  categories.forEach(c => {
    const opt = document.createElement('option');
    opt.value = c.value;
    opt.textContent = c.label;
    sel.appendChild(opt);
  });
  sel.value = m.defaultCategory || '';
  sel.classList.remove('invalid');
  bridge = (Array.isArray(m.bridge) ? m.bridge : []).map(r => ({
    key: r.key, category: r.category || '', description: r.description || '', amount: Number(r.amount) || 0,
  }));
  const hasBridge = bridge.length > 0;
  $('catBox').hidden = hasBridge;
  requiresReason = !hasBridge && m.requiresReason !== false;
  $('reasonLabel').firstChild.textContent = hasBridge ? 'Ringkasan ' : 'Alasan perubahan ';
  $('reasonReq').hidden = !requiresReason;
  $('reason').value = '';
  $('reason').classList.remove('invalid');
  $('reason').placeholder = hasBridge ? 'Kosongkan = ringkasan otomatis per kategori'
    : requiresReason ? 'Apa yang berubah dibanding revisi sebelumnya?' : 'Kosongkan = "Revisi awal."';
  $('reasonHint').textContent = hasBridge ? 'Opsional — rincian di atas ikut tersimpan.' : requiresReason ? '' : 'Opsional untuk revisi awal.';
  $('reasonHint').hidden = requiresReason;
  renderBridge(m.bridgeInfo || {});
  maxImages = Number(m.maxImages) || 5;
  images = [];
  renderImages();
}

// ---------------------------------------------------------------- R11: rincian perubahan (cost bridge)
function money(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return '-';
  return (n > 0 ? '+' : '') + n.toLocaleString('id-ID', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function plain(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n.toLocaleString('id-ID', { maximumFractionDigits: 2 }) : '-';
}

function renderBridge(info) {
  const box = $('bridgeBox');
  box.hidden = !bridge.length;
  const body = $('bridgeRows');
  body.innerHTML = '';
  if (!bridge.length) return;
  $('bridgeHead').textContent = info.prevLabel ? `(dibanding ${info.prevLabel} terbit)` : '';
  bridge.forEach((r, n) => {
    const tr = document.createElement('tr');
    const sel = document.createElement('select');
    sel.setAttribute('aria-label', `Kategori baris ${n + 1}`);
    categories.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c.value;
      opt.textContent = c.label;
      sel.appendChild(opt);
    });
    sel.value = r.category;
    sel.addEventListener('change', () => { r.category = sel.value; });
    const inp = document.createElement('input');
    inp.type = 'text';
    inp.maxLength = 300;
    inp.value = r.description;
    inp.setAttribute('aria-label', `Uraian baris ${n + 1}`);
    inp.addEventListener('input', () => { r.description = inp.value; inp.classList.remove('invalid'); });
    const c1 = document.createElement('td');
    c1.appendChild(sel);
    const c2 = document.createElement('td');
    c2.appendChild(inp);
    const c3 = document.createElement('td');
    c3.className = 'n' + (r.amount < 0 ? ' neg' : '');
    c3.textContent = money(r.amount);
    tr.appendChild(c1);
    tr.appendChild(c2);
    tr.appendChild(c3);
    body.appendChild(tr);
  });
  const total = bridge.reduce((t, r) => t + r.amount, 0);
  const known = info.fob !== null && info.fob !== undefined && info.prevFob !== null && info.prevFob !== undefined;
  $('bridgeTotal').textContent = money(total);
  $('bridgeTotalLabel').textContent = 'Selisih Actual FOB' + (known ? ` (${plain(info.prevFob)} → ${plain(info.fob)})` : '');
}

// ---------------------------------------------------------------- gambar
function renderImages() {
  const box = $('thumbs');
  box.innerHTML = '';
  images.forEach((img, n) => {
    const t = document.createElement('div');
    t.className = 'thumb';
    t.title = `${img.name} (${Math.ceil(img.size / 1024)} KB)`;
    const pic = document.createElement('img');
    pic.src = img.url;
    pic.alt = img.name;
    const x = document.createElement('button');
    x.type = 'button';
    x.textContent = '✕';
    x.title = 'Hapus gambar ini';
    x.addEventListener('click', () => {
      images.splice(n, 1);
      renderImages();
    });
    t.appendChild(pic);
    t.appendChild(x);
    box.appendChild(t);
  });
  $('imgHint').textContent = `PNG / JPG, maks. ${maxImages} gambar · gambar besar otomatis diperkecil`
    + (images.length ? ` · ${images.length} dipilih` : '') + '.';
}

function addFiles(files) {
  const list = Array.from(files || []).filter(f => f && f.type && f.type.indexOf('image/') === 0);
  if (!list.length) return false;
  let error = '';
  list.forEach(f => {
    if (images.length >= maxImages) { error = `Maksimal ${maxImages} gambar.`; return; }
    if (f.type !== 'image/png' && f.type !== 'image/jpeg') { error = 'Hanya gambar PNG atau JPG.'; return; }
    if (f.size > MAX_INPUT) { error = `${f.name || 'Gambar'} lebih dari 20 MB.`; return; }
    const slot = { name: '', type: f.type, size: f.size, data: '', url: '' };
    const ext = f.type === 'image/png' ? 'png' : 'jpg';
    slot.name = f.name && f.name !== 'image.png' ? f.name : `gambar-${images.length + 1}.${ext}`;
    images.push(slot);
    const drop = text => {
      const n = images.indexOf(slot);
      if (n >= 0) images.splice(n, 1);
      renderImages();
      showMessage({ type: 'error', text });
    };
    const reader = new FileReader();
    reader.onload = () => {
      shrink(String(reader.result || ''), f.size).then(url => {
        const data = url.replace(/^data:[^,]*,/, '');
        const bytes = Math.floor(data.length * 3 / 4);
        if (bytes > MAX_BYTES) return drop(`${slot.name} masih lebih dari 3,5 MB setelah diperkecil.`);
        if (url.indexOf('data:image/jpeg') === 0 && slot.type !== 'image/jpeg') {
          slot.type = 'image/jpeg';
          slot.name = slot.name.replace(/\.[^.]*$/, '') + '.jpg';
        }
        slot.url = url;
        slot.data = data;
        slot.size = bytes;
        renderImages();
      }, () => drop(`${slot.name} tidak bisa dibaca sebagai gambar.`));
    };
    reader.onerror = () => drop(`${slot.name} tidak bisa dibaca.`);
    reader.readAsDataURL(f);
  });
  renderImages();
  showMessage(error ? { type: 'error', text: error } : null);
  return true;
}

// R12 (T60): file > 1 MB -> gambar diperkecil (sisi terpanjang maks. MAX_SIDE) dan disimpan sebagai JPEG 85%
// (latar putih untuk PNG transparan). File kecil dikirim apa adanya.
function shrink(url, size) {
  return new Promise((resolve, reject) => {
    if (size <= SHRINK_OVER) { resolve(url); return; }
    const img = new Image();
    img.onload = () => {
      const w = img.naturalWidth;
      const h = img.naturalHeight;
      if (!w || !h) { reject(new Error('kosong')); return; }
      const k = Math.min(1, MAX_SIDE / Math.max(w, h));
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(w * k));
      c.height = Math.max(1, Math.round(h * k));
      const g = c.getContext('2d');
      g.fillStyle = '#ffffff';
      g.fillRect(0, 0, c.width, c.height);
      g.drawImage(img, 0, 0, c.width, c.height);
      const out = c.toDataURL('image/jpeg', 0.85);
      resolve(out.length < url.length ? out : url);   // tidak lebih kecil -> pakai asli
    };
    img.onerror = () => reject(new Error('decode'));
    img.src = url;
  });
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Menerbitkan…' : 'Terbitkan';
}

function render(model) {
  const m = model || {};
  if (m.key !== lastKey) {
    lastKey = m.key;
    fillForm(m);
  }
  renderChecks(m);
  showMessage(m.message);
  setBusy(!!m.busy);
}

function submit() {
  if (busy || blocked) return;
  const category = $('category').value;
  const reason = $('reason').value.trim();
  if (bridge.length) {
    const empty = bridge.findIndex(r => !String(r.description || '').trim());
    if (empty >= 0) {
      const inp = $('bridgeRows').querySelectorAll('input')[empty];
      if (inp) { inp.classList.add('invalid'); inp.focus(); }
      showMessage({ type: 'error', text: 'Uraian rincian perubahan tidak boleh kosong.' });
      return;
    }
  } else if (!category) {
    $('category').classList.add('invalid');
    $('category').focus();
    showMessage({ type: 'error', text: 'Pilih kategori perubahan.' });
    return;
  }
  if (requiresReason && !reason) {
    $('reason').classList.add('invalid');
    $('reason').focus();
    showMessage({ type: 'error', text: 'Alasan perubahan wajib diisi untuk revisi ini.' });
    return;
  }
  if (images.some(i => !i.data)) {
    showMessage({ type: 'error', text: 'Gambar masih dimuat, coba lagi sebentar.' });
    return;
  }
  showMessage(null);
  appsmith.updateModel({
    category: bridge.length ? '' : category, reason,
    bridge: bridge.map(r => ({ key: r.key, category: r.category, description: String(r.description || '').trim() })),
    images: images.map(i => ({ name: i.name, data: i.data })),
  });
  appsmith.triggerEvent('onPublish');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('category').addEventListener('change', () => $('category').classList.remove('invalid'));
  $('reason').addEventListener('input', () => $('reason').classList.remove('invalid'));
  // Tempel gambar di mana pun di form (teks biasa tetap tertempel normal)
  document.addEventListener('paste', e => {
    if (busy || blocked) return;
    const files = Array.from((e.clipboardData && e.clipboardData.items) || [])
      .filter(it => it.kind === 'file').map(it => it.getAsFile());
    if (files.length && addFiles(files)) e.preventDefault();
  });
  $('btnPick').addEventListener('click', () => $('file').click());
  $('file').addEventListener('change', () => {
    addFiles($('file').files);
    $('file').value = '';
  });
  const drop = $('paste');
  drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over'); });
  drop.addEventListener('dragleave', () => drop.classList.remove('over'));
  drop.addEventListener('drop', e => {
    e.preventDefault();
    drop.classList.remove('over');
    addFiles(e.dataTransfer && e.dataTransfer.files);
  });
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
