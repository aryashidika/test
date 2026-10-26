// cwBomGrid - grid BOM page Specsheet: No, Komponen, Material, Supplier, UoM, Thickness, Remarks + satu kolom per article.
// F10b: sel warna & Remarks = kotak teks yang membungkus (terbaca semua); Remarks boleh beberapa baris (Shift+Enter);
//   saran warna = daftar sendiri (panah atas/bawah lalu Enter memilih saran - ketikan setengah jadi tidak tersimpan).
// R4: baris = material INDUK + thickness ("NAMA · THICKNESS"); sel = WARNA, varian (Material Code) dicari DB.
//   Material Code boleh diketik di kolom Material (mengisi induk + thickness, menawarkan isi warna ke semua article
//   di baris tambah) atau di sel (diganti warnanya; kode material/thickness lain ditolak). Sel berwarna tanpa varian =
//   SEL KUNING + tombol Daftarkan (action registerVariant). Tombol "+ Supplier baru" (action newSupplier).
// R16: thickness diketik apa adanya lalu dibakukan (= fn_clean_thickness, canonThickness); "NAMA · THICKNESS" dengan thickness
//   baru untuk induk yang ada = baris baru, selnya kuning sampai kodenya didaftarkan. Induk yang belum ada: tombol
//   "+ New material" (action newMaterial). Typo: pesan "Did you mean".
// R16 (20 Okt 2026, permintaan user): material yang tidak ketemu (Enter / + Add / ganti material di sel) -> tombol
//   "+ New material" langsung di sel Material baris itu. Setelah material disimpan di modal (model.matAdded berubah), aksi baris
//   itu diulang otomatis dengan nama yang disimpan: baris tambah / sub ditambahkan, atau material baris diganti.
// Hanya tampilan & input. Setiap perubahan dikirim sebagai model.action + event onAction (BomCtrl.onAction());
// BomCtrl menjalankan query lalu memuat ulang data. Aturan final di DB (fn_bom_*).
// Antrean aksi: aksi dikirim SATU PER SATU; berikutnya baru dikirim setelah BomCtrl membalas doneSeq >= seq aksi
//   (ack). Tanpa ack 5 detik -> kirim ulang (BomCtrl mengabaikan seq yang sudah selesai). Nilai yang sudah dikirim
//   ditampilkan (optimistic) sampai antrean kosong, supaya render ulang tidak memunculkan nilai lama.
// Teks yang diketik dicocokkan ke master di sini:
//   komponen "10 - Vamp" / "10" / nama unik -> master ACTIVE; selain itu komponen lokal (No. wajib)
//   material "NAMA · THICKNESS" / Material Code / nama unik; supplier = nama (kosong = tanpa supplier)
const $ = id => document.getElementById(id);
const SEP = ' · ';
let M = {};                 // model terakhir
let seq = 0;
let queue = [];             // aksi menunggu ack BomCtrl (model.doneSeq); queue[0] = yang sedang dikirim
let retryTimer = null;
let optimistic = {};        // key input -> nilai yang sudah dikirim tapi belum kembali dari DB
let lastMsg = null;         // object message dari model (untuk mendeteksi pesan baru)
let localMsg = null;        // pesan validasi di widget
let lastNotFound = null;    // R16: material terakhir yang diketik dan tidak ketemu -> isian awal "+ New material"
let nfFor = null;           // R16: { key, name, thick } input Material yang tidak ketemu -> tombol "+ New material" di sel itu
let awaitNew = null;        // R16: { key, thick } menunggu material baru dari modal, lalu aksi baris itu diulang otomatis
let lastMatAdded = null;    // R16: model.matAdded.key terakhir
let curAdd = null;          // input baris tambah yang sedang tampil
let curSub = null;          // { parent, f } form subkomponen yang sedang tampil
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

// = fn_clean_thickness (R16, gaya berspasi tim material): huruf besar, kutip pintar / dua apostrof -> ", koma desimal -> titik,
// ".5" -> "0.5", nol belakang dibuang ("2.0" = "2"), INCH / IN setelah angka -> ", angka + satuan satu spasi ("1.2MM" -> "1.2 MM"),
// "X" antar ukuran berspasi ("44X69CM" -> "44 X 69 CM"), tanpa spasi di sekitar "-", spasi sebelum "(", rentang
// "1.4 MM-1.6 MM" -> "1.4-1.6 MM". Kosong / "." / "-" = tanpa thickness. Salinan sama di cwVariantForm.
function canonThickness(s) {
  let t = String(s ?? '').replace(/\s+/g, ' ').trim().toUpperCase();
  if (t === '' || t === '.' || t === '-') return '';
  t = t.replace(/[“”„‟″〃＂]/g, '"')
    .replace(/['’‘′`´]{2}/g, '"')
    .replace(/(\d),(\d)/g, '$1.$2')
    .replace(/(^|[^0-9.])\.(\d)/g, (m, a, b) => `${a}0.${b}`)
    .replace(/(\d)\.(\d*[1-9])0+(?![0-9])/g, '$1.$2')
    .replace(/(\d)\.0+(?![0-9])/g, '$1')
    .replace(/(\d)\s*(INCHES|INCH|IN)(?=$|\s*X|\s*\(|\s*-|[^A-Z0-9\s])/g, '$1"')
    .replace(/(\d)\s*(MM|CM|UM|ME)(?=$|[^A-Z]|X\d)/g, '$1 $2')
    .replace(/(\d|MM|CM|UM|")\s*X\s*(?=\d)/g, '$1 X ')
    .replace(/\s*-\s*/g, '-')
    .replace(/\s*\(\s*/g, ' (')
    .replace(/\s+\)/g, ')')
    .replace(/(\d)\s+"/g, '$1"')
    .replace(/(\d) (MM|CM|UM)-(\d+(?:\.\d+)?) \2(?=$|[^A-Z])/g, '$1-$3 $2')
    .replace(/\s+/g, ' ')
    .trim();
  return t;
}

const thickKey = t => norm(canonThickness(t));

// Jarak ketik (Levenshtein) untuk saran typo
function editDistance(a, b) {
  const m = a.length;
  const n = b.length;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[n];
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
const matLabel = m => (m.thickness ? `${m.name}${SEP}${m.thickness}` : m.name);
const matKey = (materialId, thickness) => `${materialId}|${thickKey(thickness)}`;

// Varian ACTIVE per induk + thickness (warna terdaftar baris itu)
function variantsOf(materialId, thickness) {
  return (M.variants || []).filter(v => v.material_id === materialId && thickKey(v.thickness) === thickKey(thickness));
}

function variantByCode(text) {
  const key = norm(text);
  return key ? (M.variants || []).find(v => norm(v.code) === key) || null : null;
}

function resolveComponent(text) {
  const key = norm(text);
  if (!key) return { error: 'Component is required.' };
  const comps = M.components || [];
  let c = comps.find(x => norm(compLabel(x)) === key);
  if (c) return { comp: c };
  if (/^\d+$/.test(key)) {
    c = comps.find(x => Number(x.number) === Number(key));
    return c ? { comp: c } : { error: `Component number ${key} is not in the master. For a new component, type its name and fill in No.` };
  }
  const byName = comps.filter(x => norm(x.name) === key);
  return byName.length === 1 ? { comp: byName[0] } : { local: tidy(text) };
}

// Material yang tidak ditemukan: nama mirip (typo) dari master pabrik, paling dekat dulu
function didYouMean(raw) {
  const q = norm(String(raw).split(/\s*·\s*/)[0]);
  if (q.length < 3) return [];
  // typo di Material Code (tanpa spasi): kode terdekat
  if (!/\s/.test(q) && q.length >= 6) {
    const head = q.slice(0, 3);
    const tail = q.slice(-3);
    const codes = (M.variants || [])
      .filter(v => { const c = norm(v.code); return Math.abs(c.length - q.length) <= 2 && (c.startsWith(head) || c.endsWith(tail)); })
      .map(v => ({ v, d: editDistance(q, norm(v.code)) }))
      .filter(x => x.d <= 2)
      .sort((x, y) => x.d - y.d)
      .slice(0, 3)
      .map(x => `${x.v.code} (${x.v.material_name} · ${x.v.thickness || 'no dimension'} · ${x.v.color})`);
    if (codes.length) return codes;
  }
  const names = [...new Set((M.materials || []).map(x => x.name))];
  const limit = Math.max(1, Math.floor(q.length / 4));
  const qw = q.replace(/[^a-z0-9]+/g, ' ').trim().split(' ');
  return names
    .map(n => {
      const nn = norm(n);
      const nw = nn.replace(/[^a-z0-9]+/g, ' ').trim().split(' ');
      const near = (a, b) => Math.abs(a.length - b.length) <= Math.max(1, Math.floor(a.length / 4)) && editDistance(a, b) <= Math.max(1, Math.floor(a.length / 4));
      const wordsOk = qw.every(w => nw.some(v => v.includes(w) || near(w, v)));
      const whole = nn.includes(q) || q.includes(nn) || wordsOk ? 1
        : (Math.abs(nn.length - q.length) > limit ? limit + 1 : editDistance(q, nn));
      return { n, d: whole };
    })
    .filter(x => x.d <= limit)
    .sort((x, y) => x.d - y.d || x.n.localeCompare(y.n))
    .slice(0, 3)
    .map(x => x.n);
}

// R16 (21 Okt 2026, permintaan user): titik tengah sulit diketik. Tanpa "·", teks dibaca sebagai NAMA MASTER + THICKNESS bila
// bagian depannya persis nama material yang ada (terpanjang dulu) dan sisanya mirip thickness:
//   dengan pemisah ". - | / , ; :"  -> sisanya cukup berisi angka   ("honeylon mesh . 1,5 mm", "honeylon mesh - 44 inch")
//   tanpa pemisah                   -> sisanya angka + satuan      ("honeylon mesh 1,5mm"; "HONEYLON MESH 2" tetap nama)
// Nama yang cocok persis (mis. "SM-300 (COOL MELT)") selalu menang. Hasil -> "NAMA · THICKNESS" (isian ditulis ulang).
function looksThick(text, explicit) {
  const t = canonThickness(text);
  if (!/\d/.test(t) || /\d\.\d+\.\d/.test(t)) return false;         // "1.2.5" bukan angka
  return explicit || /\d\s*(MM|CM|UM)\b|\d"/.test(t);
}

function altSplit(raw) {
  if (raw.includes('·')) return null;
  const nr = norm(raw);
  const names = [...new Set((M.materials || []).map(x => x.name))].sort((a, b) => norm(b).length - norm(a).length);
  if (names.some(n => norm(n) === nr)) return null;                   // nama persis
  for (const n of names) {
    const nn = norm(n);
    if (!nn || !nr.startsWith(nn)) continue;
    const rest = nr.slice(nn.length);
    if (!/^[\s.\-|\/,;:]/.test(rest)) continue;                         // nama lain yang lebih panjang ("honeylon meshx ...")
    const sep = /^\s*[.\-|\/,;:]+\s*/.exec(rest);
    const dotNumber = /^\.\d/.test(rest);                              // "NAMA.5mm" = 0.5, bukan pemisah
    const explicit = !!sep && !dotNumber;
    const body = (explicit ? rest.slice(sep[0].length) : rest).trim();
    if (body && looksThick(body, explicit)) return `${n}${SEP}${canonThickness(body)}`;
  }
  return null;
}

// Material baru (tidak ada di master) ditulis "NAMA . THICKNESS" / "NAMA - THICKNESS" (pemisah berspasi): pisahkan untuk modal
function splitNewName(raw) {
  const m = /^(.*\S)\s+[.\-|\/]\s+(\S.*)$/.exec(raw);
  return m && looksThick(m[2], true) ? { name: m[1], thickness: canonThickness(m[2]) } : null;
}

// -> { mat: { material_id, name, uom, thickness, isNew?, ... }, color }
//   (color terisi bila yang diketik Material Code; isNew = induk ada tapi thickness ini belum punya varian)
//   Tidak ketemu -> { error, notFound: { name, thickness } } (tombol "+ New material")
function resolveMaterial(text) {
  const raw = tidy(text);
  if (!raw) return { error: 'Material is required.' };
  const mats = M.materials || [];
  const parts = raw.split(/\s*·\s*/);
  const nameKey = norm(parts[0]);
  const thick = parts.length > 1 ? canonThickness(parts.slice(1).join(' ')) : '';
  const hasThick = thick !== '';      // "NAMA ·" tanpa thickness = masih mengetik: dianggap nama saja
  // 1. NAMA · THICKNESS (thickness dibakukan dulu: "1.2mm" = "1.2 MM")
  if (hasThick) {
    const same = mats.filter(x => norm(x.name) === nameKey);
    if (same.length) {
      const hit = same.find(x => thickKey(x.thickness) === norm(thick));
      if (hit) return { mat: hit };
      if (new Set(same.map(x => x.material_id)).size > 1) {
        return { error: `Several materials are named "${parts[0]}" (different UoM). Pick one from the list.` };
      }
      const b = same[0];
      return { mat: { material_id: b.material_id, name: b.name, uom: b.uom, thickness: thick, variant_count: 0, isNew: !!thick } };
    }
  }
  // 2. Material Code
  const v = variantByCode(raw);
  if (v) {
    const combo = mats.find(x => x.material_id === v.material_id && thickKey(x.thickness) === thickKey(v.thickness));
    return combo ? { mat: combo, color: v.color }
      : { error: `Material Code ${v.code} belongs to an INACTIVE material.` };
  }
  // 3. nama saja
  if (!hasThick) {
    const byName = mats.filter(x => nameKey === norm(x.name));
    if (byName.length === 1) return { mat: byName[0] };
    if (byName.length > 1) return { error: `Material "${raw}" has several dimensions. Pick from the list (NAME · DIMENSION) or type the Material Code.` };
  }
  // 4. R16: tanpa titik tengah ("NAMA . 1,5 mm", "NAMA 1,5mm") -> dibaca ulang sebagai "NAMA · THICKNESS"
  const alt = altSplit(raw);
  if (alt) return Object.assign(resolveMaterial(alt), { reparsed: alt });
  const nw = parts.length > 1 ? null : splitNewName(raw);
  const nfName = nw ? nw.name : tidy(parts[0]);
  const nfThick = nw ? nw.thickness : thick;
  lastNotFound = { name: nfName, thickness: nfThick };
  // pesan (termasuk "Did you mean", pemindaian seluruh master) baru dihitung saat dibaca: sync isian tidak menampilkannya
  return {
    notFound: { name: nfName, thickness: nfThick },
    get error() {
      const guess = didYouMean(nw ? nw.name : raw);
      const how = M.canAddMaterial
        ? 'Check the spelling, or click "+ New material" to add it.'
        : 'Check the spelling, or ask Vendor Specsheet to add it to Master Material.';
      return `Material "${raw}" is not in this factory's Master Material (or INACTIVE).`
        + (guess.length ? ` Did you mean: ${guess.join(' / ')}?` : '') + ` ${how}`;
    },
  };
}

function resolveSupplier(text) {
  const raw = tidy(text);
  if (!raw) return { id: null };
  const s = (M.suppliers || []).find(x => norm(x.name) === norm(raw));
  return s ? { id: s.id } : { error: `Supplier "${raw}" is not in Master Supplier (or inactive).` };
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
    o.textContent = l ? (l.is_preferred ? 'main supplier of this material' : 'added to this material')
      : 'other supplier (will be linked)';
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
    [matLabel(m), [m.uom, m.variant_count ? `${m.variant_count} colors` : 'no variants yet'].join(' · ')]));
  fill($('dlColors'), (M.colors || []).map(c => [c]));
  $('dlSuppliers').innerHTML = '';
}

// ---------------------------------------------------------------- aksi
function send(type, data) {
  localMsg = null;
  showMessage();
  seq = Math.max(Date.now(), seq + 1);         // naik terus, juga setelah widget dimuat ulang
  queue.push(Object.assign({ type, seq }, data));
  if (queue.length === 1) setTimeout(flush, 0);  // setelah pemanggil mencatat nilai optimistic
}

function flush() {
  clearTimeout(retryTimer);
  if (!queue.length) return;
  appsmith.updateModel({ action: queue[0] });
  appsmith.triggerEvent('onAction');
  retryTimer = setTimeout(flush, 5000);        // event hilang (model di-reset) -> kirim ulang
}

// Balasan BomCtrl: model.doneSeq = seq aksi terakhir yang selesai (berhasil atau gagal) dan datanya sudah dimuat ulang
function onAck(m) {
  const done = Number((m || {}).doneSeq) || 0;
  const before = queue.length;
  while (queue.length && queue[0].seq <= done) queue.shift();
  if (queue.length === before) return;
  if (queue.length) {
    flush();
  } else {
    clearTimeout(retryTimer);
    optimistic = {};
  }
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
    // change + blur: nilai yang dipulihkan setelah render ulang tidak memicu change, jadi blur ikut menyimpan
    const commit = () => {
      if (!i.isConnected) return;              // elemen sudah diganti render ulang: jangan simpan ketikan setengah jadi
      if (clean(i.value) === clean(i.dataset.orig)) return;
      const before = seq;
      opts.onCommit(i);
      if (seq !== before) optimistic[key] = i.value;
    };
    i.addEventListener('change', commit);
    i.addEventListener('blur', commit);
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

// R16: material tidak ketemu -> pesan + tombol "+ New material" di sel input itu (hanya role yang boleh menambah material)
function materialMissing(key, input, r) {
  fail(input, r.error);
  if (!r.notFound || !M.canAddMaterial) return;
  nfFor = { key, name: r.notFound.name, thick: r.notFound.thickness };
  const cell = input.closest('td');
  if (!cell) return;
  const old = cell.querySelector('.newmat');
  if (old) old.remove();
  cell.appendChild(newMaterialBox(key));
}

function newMaterialBox(key) {
  const box = el('div', 'newmat');
  box.appendChild(el('span', 'hint', 'Not in Master Material.'));
  const b = el('button', 'link newmat-btn', '+ New material');
  b.type = 'button';
  b.disabled = !!M.busy;
  b.title = `Add "${nfFor ? nfFor.name : ''}" to Master Material. This line continues automatically after saving.`;
  b.addEventListener('mousedown', e => e.preventDefault());   // jangan blur input dulu (blur = simpan ulang)
  b.addEventListener('click', () => openNewFor(key));
  box.appendChild(b);
  return box;
}

function openNewFor(key) {
  if (!nfFor || nfFor.key !== key) return;
  awaitNew = { key, thick: nfFor.thick };
  lastNotFound = null;
  send('newMaterial', { name: nfFor.name });
}

// Isian Material diubah lagi -> tombol "+ New material" baris itu hilang
function clearMissing(key, input) {
  if (!nfFor || nfFor.key !== key) return;
  nfFor = null;
  const box = input.closest('td') && input.closest('td').querySelector('.newmat');
  if (box) box.remove();
}

// R16: material baru tersimpan di modal (BomCtrl.matAdded) -> ulangi aksi baris yang menunggu dengan nama yang disimpan
function resumeAfterNewMaterial() {
  const a = M.matAdded || {};
  if (a.key === lastMatAdded) return;
  lastMatAdded = a.key;
  const w = awaitNew;
  awaitNew = null;
  if (!w || !a.name) return;
  nfFor = null;
  const text = a.name + (w.thick ? SEP + w.thick : '');
  if (w.key === 'add:mat' && curAdd) {
    curAdd.mat.value = text;
    addState.mat = text;
    curAdd.mat.dispatchEvent(new Event('change'));   // UoM, thickness, supplier utama
    submitAdd(curAdd);
  } else if (w.key === 'sub:mat' && curSub) {
    curSub.f.mat.value = text;
    subState.mat = text;
    curSub.f.mat.dispatchEvent(new Event('change'));
    submitSub(curSub.parent, curSub.f);
  } else if (w.key.startsWith('mat:')) {
    const line = (M.lines || []).find(l => `mat:${l.id}` === w.key);
    const i = document.querySelector(`#tbody [data-key="${CSS.escape(w.key)}"]`);
    if (line && i) {
      i.value = text;
      const before = seq;
      commitMaterial(line, i);
      if (seq !== before) optimistic[w.key] = i.value;   // tampil sampai DB membalas (sama dengan cellInput)
    }
  }
}

function commitMaterial(line, input) {
  const r = resolveMaterial(input.value);
  if (r.error) return materialMissing(`mat:${line.id}`, input, r);
  if (matKey(r.mat.material_id, r.mat.thickness) === matKey(line.material_id, line.thickness)) {
    input.value = input.dataset.orig;
    return;
  }
  input.dataset.orig = input.value;
  send('replaceMaterial', { line_id: line.id, material_id: r.mat.material_id, thickness: r.mat.thickness || '' });
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

// Material Code diketik di sel -> warna varian itu (harus induk + thickness baris ini)
function commitCell(line, article, input) {
  let color = tidy(input.value);
  const v = variantByCode(color);
  if (v) {
    if (v.material_id !== line.material_id || thickKey(v.thickness) !== thickKey(line.thickness)) {
      return fail(input, `Code ${v.code} is ${v.material_name || 'another material'} · ${v.thickness || 'no dimension'} · ${v.color}. It does not match the material / dimension of this line.`);
    }
    color = v.color;
    input.value = color;
  }
  input.dataset.orig = input.value;
  send('setCell', { line_id: line.id, article_id: article.id, color });
}

// Warna terdaftar untuk baris ini dulu, lalu warna se-season
function colorSource(line) {
  return () => {
    const own = variantsOf(line.material_id, line.thickness).map(v => v.color);
    const seen = new Set(own.map(norm));
    return own.concat((M.colors || []).filter(c => !seen.has(norm(c))));
  };
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
  btn.textContent = line.undo_replace ? 'Sure?' : hasSubs ? 'Delete + sub?' : 'Sure?';
  clearTimeout(delTimer);
  delTimer = setTimeout(() => {
    delArmed = null;
    const b = document.querySelector(`#tbody .link.danger[data-line="${line.id}"]`);
    if (b) {
      b.classList.remove('confirm');
      b.textContent = line.undo_replace ? 'Undo replace' : 'Delete';
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
    mk('name', { placeholder: 'Subcomponent name', label: 'Subcomponent name' });
  } else {
    mk('comp', { list: 'dlComponents', placeholder: 'Type a component…', label: 'Component' });
    mk('no', { placeholder: 'No.', label: 'Local component no.', title: 'Only for a new component that is not in the master' });
  }
  mk('mat', { list: 'dlMaterials', placeholder: 'Name · dimension / Material Code…', label: 'Material' });
  f.mat.addEventListener('input', () => clearMissing(`${prefix}:mat`, f.mat));
  mk('sup', { list: supplierListId(null), placeholder: 'Supplier…', label: 'Supplier' });
  mk('rem', { placeholder: 'Remarks', label: 'Remarks', keepLines: true, title: 'Shift+Enter / Alt+Enter = new line' });
  f.uom = el('span', 'ro none', '-');
  f.thk = el('span', 'ro none', '-');
  if (!isSub) {
    // Material Code diketik -> tawarkan isi warnanya ke semua article
    f.fill = el('label', 'fill');
    f.fillCheck = el('input');
    f.fillCheck.type = 'checkbox';
    f.fillCheck.checked = state.fill !== false;
    f.fillCheck.addEventListener('change', () => { state.fill = f.fillCheck.checked; });
    f.fillText = el('span');
    f.fill.append(f.fillCheck, f.fillText);
    f.fill.hidden = true;
  }

  const syncMaterial = () => {
    const r = resolveMaterial(f.mat.value);
    const mat = r.mat || null;
    f.uom.textContent = mat ? mat.uom : '-';
    f.thk.textContent = mat && mat.thickness ? mat.thickness + (mat.isNew ? ' (new)' : '') : '-';
    f.thk.title = mat && mat.isNew
      ? 'New dimension for this material: no variants yet. Color cells stay yellow until their Material Codes are registered.' : '';
    if (mat && (r.color || r.reparsed)) {     // kode / "NAMA . THICKNESS" diketik -> tampilkan sebagai NAMA · THICKNESS
      f.mat.value = matLabel(mat);
      state.mat = f.mat.value;
    }
    if (f.fill) {
      // warna dari kode tetap ditawarkan selama material + thickness-nya tidak diganti
      const key = mat ? matKey(mat.material_id, mat.thickness) : '';
      if (r.color) state.fillKey = key;
      state.fillColor = r.color || (key && key === state.fillKey ? state.fillColor || '' : '');
      f.fill.hidden = !state.fillColor;
      f.fillText.textContent = ` Fill color ${state.fillColor} into all articles`;
    }
    f.sup.setAttribute('list', supplierListId(mat ? mat.material_id : null));
    if (mat && !tidy(f.sup.value)) {
      f.sup.value = defaultSupplier(mat.material_id);
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
    if (!/^\d+$/.test(no)) return fail(f.no, `"${c.local}" is not in the component master. Fill in No. (a number) for this local component.`);
    if (Number(no) % 10 === 0) return fail(f.no, 'A local component no. cannot be a multiple of 10.');
    data.local_no = no;
    data.local_name = c.local;
  }
  const m = resolveMaterial(f.mat.value);
  if (m.error) return materialMissing('add:mat', f.mat, m);
  const s = resolveSupplier(f.sup.value);
  if (s.error) return fail(f.sup, s.error);
  const fill = addState.fillColor && addState.fill !== false ? addState.fillColor : '';
  send('addLine', Object.assign(data, {
    material_id: m.mat.material_id, thickness: m.mat.thickness || '', supplier_id: s.id || '',
    process: tidyLines(f.rem.value), fill_color: fill,
  }));
}

function submitSub(parent, f) {
  Object.values(f).forEach(i => i.classList && i.classList.remove('invalid'));
  if (!tidy(f.name.value)) return fail(f.name, 'Subcomponent name is required.');
  const m = resolveMaterial(f.mat.value);
  if (m.error) return materialMissing('sub:mat', f.mat, m);
  const s = resolveSupplier(f.sup.value);
  if (s.error) return fail(f.sup, s.error);
  send('addSub', {
    parent_id: parent.id, sub_name: tidy(f.name.value), material_id: m.mat.material_id,
    thickness: m.mat.thickness || '', supplier_id: s.id || '', process: tidyLines(f.rem.value),
  });
}

// ---------------------------------------------------------------- render
function parseObj(v) {
  if (typeof v !== 'string') return v || {};
  try { return JSON.parse(v || '{}'); } catch (e) { return {}; }
}

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
  if (line.supplier_id && (line.link_status === 'INACTIVE' || line.supplier_status === 'INACTIVE')) {
    const b = el('span', 'badge inactive', '⚠ inactive');
    b.title = line.supplier_status === 'INACTIVE'
      ? 'This supplier is inactive in Master Supplier. Choose another supplier before publishing.'
      : 'This supplier is inactive for this material. Choose another supplier before publishing.';
    c.appendChild(b);
  }
  return c;
}

function materialCell(line, editable) {
  const c = el('td', 'c-mat');
  const label = matLabel({ name: line.material_name, thickness: line.thickness });
  const title = [line.uom, line.material_code].filter(x => x).join(' · ');
  if (editable) {
    const mi = cellInput(`mat:${line.id}`, label, {
      col: 'mat', list: 'dlMaterials', label: 'Material',
      title: `${title}. Type another material / dimension (or Material Code) to Replace Material.`,
      onCommit: i => commitMaterial(line, i),
    });
    mi.addEventListener('input', () => clearMissing(`mat:${line.id}`, mi));
    c.appendChild(mi);
  } else {
    const s = el('span', 'ro', label);
    s.title = title;
    c.appendChild(s);
  }
  if (line.material_status === 'INACTIVE') c.appendChild(el('span', 'badge inactive', '⚠ material INACTIVE'));
  if (editable && M.canAddMaterial && nfFor && nfFor.key === `mat:${line.id}`) c.appendChild(newMaterialBox(nfFor.key));
  return c;
}

function lineRow(line, arts, editable, hasSubs) {
  const tr = el('tr', line.is_sub ? 'sub' : '');
  tr.appendChild(td('c-no', String(line.display_no ?? '')));
  const comp = el('td', 'c-comp');
  const name = el('span', 'ro name', line.display_name || '');
  if (line.is_local) name.appendChild(el('span', 'local', 'local'));
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
      title: 'Shift+Enter / Alt+Enter = new line · Enter = save', onCommit: i => commitProcess(line, i),
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
      b.title = 'Add a subcomponent below this line';
      b.addEventListener('click', () => {
        subParent = subParent === line.id ? null : line.id;
        subState = {};
        render(M, true);
        const first = document.querySelector('tr.subform input');
        if (first) first.focus();
      });
      act.appendChild(b);
    }
    // R11 (T58): baris hasil Ganti material -> "Batal ganti" (baris ini dihapus, material sebelumnya aktif lagi)
    const undo = !!line.undo_replace;
    const del = el('button', 'link danger', delArmed === line.id ? (undo ? 'Sure?' : hasSubs ? 'Delete + sub?' : 'Sure?')
      : (undo ? 'Undo replace' : 'Delete'));
    if (delArmed === line.id) del.classList.add('confirm');
    del.type = 'button';
    del.dataset.line = line.id;
    del.title = undo ? `Undo material replace: back to ${line.undo_material || 'the previous material'}${hasSubs ? ' (subcomponents move too)' : ''} (click twice)`
      : hasSubs ? 'Delete this line and its subcomponents (click twice)' : 'Delete this line (click twice)';
    del.addEventListener('click', () => armDelete(del, line, hasSubs));
    act.appendChild(del);
    tr.appendChild(act);
  }
  const cells = parseObj(line.cells);
  const codes = parseObj(line.cell_codes);
  arts.forEach(a => {
    const v = cells[a.id] || '';
    const code = codes[a.id] || '';
    const yellow = !!v && !code;
    const c = el('td', 'c-art' + (yellow ? ' yellow' : ''));
    if (editable) {
      c.appendChild(cellInput(`cell:${line.id}:${a.id}`, v, {
        col: `art:${a.id}`, multiline: true, suggest: colorSource(line), label: `Warna ${a.code}`,
        title: 'Type a color or Material Code. Empty = not used in this article.',
        onCommit: i => commitCell(line, a, i),
      }));
    } else {
      c.appendChild(el('span', 'ro' + (v ? '' : ' none'), v || '-'));
    }
    if (code) {
      c.appendChild(el('span', 'vcode', code));
    } else if (yellow) {
      const note = el('span', 'vcode warn', 'no Material Code');
      note.title = 'This color is not registered as a variant of this material + dimension. The specsheet cannot be published.';
      c.appendChild(note);
      if (editable && M.canRegister) {
        const b = el('button', 'link reg', 'Register');
        b.type = 'button';
        b.title = `Register variant ${line.material_name} · ${line.thickness || 'no dimension'} · ${v}`;
        b.addEventListener('click', () => send('registerVariant', {
          line_id: line.id, material_id: line.material_id, material_name: line.material_name, uom: line.uom,
          thickness: line.thickness || '', color: v,
        }));
        c.appendChild(b);
      }
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
  if (f.fill) mat.appendChild(f.fill);
  if (M.canAddMaterial && nfFor && nfFor.key === f.mat.dataset.key) mat.appendChild(newMaterialBox(nfFor.key));
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
        if (nfFor && /^(add|sub):/.test(nfFor.key)) nfFor = null;
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
  [['c-no', 'No'], ['c-comp', 'Component'], ['c-mat', 'Material'], ['c-sup', 'Supplier'], ['c-uom', 'UoM'], ['c-thk', 'Dimension'], ['c-rem', 'Remarks']]
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
      b.title = `Drop article ${a.code} from this revision (click twice)`;
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
    const c = el('td', 'empty', M.emptyText || 'No BOM lines yet.');
    c.colSpan = cols;
    tr.appendChild(c);
    tbody.appendChild(tr);
  }
  curAdd = null;
  curSub = null;
  const parents = new Set(lines.filter(l => l.is_sub).map(l => l.parent_line_key));
  lines.forEach(line => {
    tbody.appendChild(lineRow(line, arts, editable, !line.is_sub && parents.has(line.line_key)));
    if (editable && subParent === line.id) {
      const f = formInputs('sub', subState, true);
      curSub = { parent: line, f };
      const ok = el('button', 'btn', 'Add');
      ok.type = 'button';
      ok.disabled = !!M.busy;
      ok.addEventListener('click', () => submitSub(line, f));
      const cancel = el('button', 'link muted', 'Cancel');
      cancel.type = 'button';
      cancel.addEventListener('click', () => { subParent = null; subState = {}; render(M, true); });
      tbody.appendChild(formRow('subform', f, { comp: f.name, input: f.name }, ok, cancel, arts));
    }
  });
  if (editable) {
    const f = formInputs('add', addState, false);
    curAdd = f;
    const ok = el('button', 'btn', '+ Add');
    ok.type = 'button';
    ok.disabled = !!M.busy;
    ok.addEventListener('click', () => submitAdd(f));
    tbody.appendChild(formRow('add', f, {
      no: f.no, comp: f.comp, input: f.comp,
      hint: 'Not in the master → local component, fill in No. (not a multiple of 10).',
    }, ok, null, arts));
  }

  // pulihkan ketikan, fokus, scroll
  document.querySelectorAll('#tbody .cell[data-key]').forEach(i => {
    const k = i.dataset.key;
    if (optimistic[k] !== undefined) {
      i.value = optimistic[k];
      i.dataset.orig = optimistic[k];
    }
    if (dirty[k] !== undefined) i.value = dirty[k];
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
  const yellow = lines.reduce((t, l) => t + (Number(l.yellow) || 0), 0);
  $('status').textContent = (M.busy || queue.length ? 'Saving… · ' : '')
    + `${n} lines · ${arts.length} article(s)` + (yellow ? ` · ${yellow} yellow cells` : '') + (editable ? '' : ' · read only');
  $('btnSupplier').hidden = !(editable && M.canAddSupplier);
  $('btnSupplier').disabled = !!M.busy;
  $('btnMaterial').hidden = !(editable && M.canAddMaterial);
  $('btnMaterial').disabled = !!M.busy;
  showMessage();
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  $('btnSupplier').addEventListener('click', () => send('newSupplier', {}));
  // "+ New material": nama dari ketikan terakhir yang tidak ketemu, atau isi kolom Material baris tambah
  $('btnMaterial').addEventListener('click', () => {
    const r = resolveMaterial(addState.mat || '');
    const nf = r.notFound || lastNotFound;
    lastNotFound = null;
    awaitNew = r.notFound ? { key: 'add:mat', thick: r.notFound.thickness } : null;   // baris tambah dilanjutkan setelah simpan
    send('newMaterial', { name: nf ? nf.name : tidy(String(addState.mat || '').split(/\s*·\s*/)[0]) });
  });
  $('scroll').addEventListener('scroll', hideSuggest);
  render(appsmith.model);
  lastMatAdded = (M.matAdded || {}).key;
  appsmith.onModelChange(m => {
    onAck(m);
    render(m);
    resumeAfterNewMaterial();
  });
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
