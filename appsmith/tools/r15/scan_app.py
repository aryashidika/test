# R15: daftar properti widget (selain Custom Widget) & query app yang masih berisi teks Indonesia / em dash.
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
path = sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/exports/build_r14.json'
d = json.load(open(path, encoding='utf-8'))
ID = re.compile(r'\b(yang|tidak|belum|sudah|dulu|harus|wajib|untuk|dengan|dari|atau|bisa|ada|dan|pilih|Pilih|isi|Isi|hanya|baris|Baris|harga|Harga|pabrik|Pabrik|terbit|Terbit|revisi|Revisi|Simpan|Batal|Tutup|Hapus|Ubah|Tambah|Cari|Semua|semua|Nama|nama|Kode|Aksi|Waktu|Entitas|Ubah|Lihat|Buat|Terbitkan|Riwayat|Kembali|Keterangan|Aktif|aktif|Nonaktif|nonaktif|Tanggal|Alasan|Kategori|Pemasok|Varian|varian|Warna|warna|Lampiran|Unggah|unggah|catatan|terbaru|hari|terakhir|maks|Tampilkan|Persetujuan|Pilihan|Komponen|Kelompok|Nomor|Musim|Usulan|Ajukan|Setujui|Tolak|Akhiri|Salin|Sumber|Status harga|Berlaku|Mulai|Ukuran|Jenis|Urutan|Nilai|Diubah|oleh|Pengguna|Masuk|Keluar|Dipakai|dipakai|Utama|utama|Unduh|unduh|mis|Muat|ulang|dihapus|disimpan|Beranda|Detail Material)\b')
def walk(w, p=''):
    yield w
    for c in w.get('children', []) or []:
        yield from walk(c)
out = []
for pg in d['pageList']:
    name = pg['unpublishedPage']['name']
    for w in walk(pg['unpublishedPage']['layouts'][0]['dsl']):
        if w.get('type') == 'CUSTOM_WIDGET':
            for k in ('defaultModel',):
                v = w.get(k)
                if isinstance(v, str) and (ID.search(v) or '—' in v):
                    out.append((name, w['widgetName'], k, v))
            continue
        def scan(obj, path):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    scan(v, f'{path}.{k}' if path else k)
            elif isinstance(obj, list):
                for i, v in enumerate(obj):
                    scan(v, f'{path}[{i}]')
            elif isinstance(obj, str) and (ID.search(obj) or '—' in obj):
                out.append((name, w.get('widgetName'), path, obj))
        scan({k: v for k, v in w.items() if k != 'children'}, '')
for a in d['actionList']:
    u = a['unpublishedAction']
    if u.get('collectionId'):
        continue
    b = (u.get('actionConfiguration') or {}).get('body') or ''
    b2 = re.sub(r'--[^\n]*', '', b)
    lits = [m for m in re.findall(r"'((?:[^']|'')*)'", b2) if ID.search(m) or '—' in m]
    if lits or '—' in b:
        out.append((u['pageId'], u['name'], 'QUERY', ' | '.join(lits) + (' [em dash di komentar]' if '—' in b else '')))
for r in out:
    print(' | '.join(str(x) for x in r[:3]), '=>', repr(r[3])[:300])
print(len(out), 'temuan', file=sys.stderr)
