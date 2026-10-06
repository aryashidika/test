// cwPublishForm — modal Terbitkan revisi: Specsheet (mdlTerbit, F6) dan CBD (mdlCbdTerbit, F8). Hanya tampilan;
// checklist dihitung di DB (v_revision_checklist / v_cbd_checklist) dan disusun <Page>Ctrl.publishFormModel().
// Terbit lewat SpecCtrl.publish() / CbdCtrl.publish() (checklist, kategori, dan alasan dicek lagi di DB).
// F10b: gambar opsional (tempel Ctrl+V / pilih file; PNG/JPG ≤ 5 MB, maks. model.maxImages) -> model.images
//   [{ name, data (base64 tanpa awalan) }]; dilampirkan ke change log oleh <Page>Ctrl setelah terbit.
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let blocked = false;
let requiresReason = true;
let images = [];           // { name, type, size, data, url }
let maxImages = 5;
const MAX_BYTES = 5 * 1024 * 1024;

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
  const sel = $('category');
  sel.innerHTML = '<option value="">— pilih kategori —</option>';
  (m.categories || []).forEach(c => {
    const opt = document.createElement('option');
    opt.value = c.value;
    opt.textContent = c.label;
    sel.appendChild(opt);
  });
  sel.value = m.defaultCategory || '';
  sel.classList.remove('invalid');
  requiresReason = m.requiresReason !== false;
  $('reasonReq').hidden = !requiresReason;
  $('reason').value = '';
  $('reason').classList.remove('invalid');
  $('reason').placeholder = requiresReason ? 'Apa yang berubah dibanding revisi sebelumnya?' : 'Kosongkan = "Revisi awal."';
  $('reasonHint').textContent = requiresReason ? '' : 'Opsional untuk revisi awal.';
  $('reasonHint').hidden = requiresReason;
  maxImages = Number(m.maxImages) || 5;
  images = [];
  renderImages();
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
  $('imgHint').textContent = `PNG / JPG, maks. 5 MB per gambar, maks. ${maxImages} gambar`
    + (images.length ? ` · ${images.length} dipilih` : '') + '.';
}

function addFiles(files) {
  const list = Array.from(files || []).filter(f => f && f.type && f.type.indexOf('image/') === 0);
  if (!list.length) return false;
  let error = '';
  list.forEach(f => {
    if (images.length >= maxImages) { error = `Maksimal ${maxImages} gambar.`; return; }
    if (f.type !== 'image/png' && f.type !== 'image/jpeg') { error = 'Hanya gambar PNG atau JPG.'; return; }
    if (f.size > MAX_BYTES) { error = `${f.name || 'Gambar'} lebih dari 5 MB.`; return; }
    const slot = { name: '', type: f.type, size: f.size, data: '', url: '' };
    const ext = f.type === 'image/png' ? 'png' : 'jpg';
    slot.name = f.name && f.name !== 'image.png' ? f.name : `gambar-${images.length + 1}.${ext}`;
    images.push(slot);
    const reader = new FileReader();
    reader.onload = () => {
      slot.url = String(reader.result || '');
      slot.data = slot.url.replace(/^data:[^,]*,/, '');
      renderImages();
    };
    reader.readAsDataURL(f);
  });
  renderImages();
  showMessage(error ? { type: 'error', text: error } : null);
  return true;
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
  if (!category) {
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
  appsmith.updateModel({ category, reason, images: images.map(i => ({ name: i.name, data: i.data })) });
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
