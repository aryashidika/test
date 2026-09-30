// cwPublishForm — modal Terbitkan revisi di page Specsheet (mdlTerbit). Hanya tampilan; checklist
// dihitung di DB (v_revision_checklist) dan disusun SpecCtrl.publishFormModel(). Terbit lewat
// SpecCtrl.publish() -> fn_revision_publish (checklist, kategori, dan alasan dicek lagi di DB).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let blocked = false;
let requiresReason = true;

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
    : `Perbaiki ${failed} hal di atas di grid BOM sebelum terbit.`;
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
  appsmith.updateModel({ category, reason });
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
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
