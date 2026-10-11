# Gabungkan sql/R3..R7 menjadi sql/R_revisi_semua.sql (satu file, satu transaksi saat dijalankan di DB Tools).
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = ['R3_harga', 'R4_model_specsheet', 'R5_cbd', 'R6_tugas_pabrik', 'R7_copy_model']
out = ["""-- ============================================================================
-- R_revisi_semua — gabungan revisi R3 + R4 + R5 + R6 + R7 (dibuat otomatis oleh tools/make_revisi_sql.py;
-- JANGAN diedit langsung — ubah file sql/R3_…–R7_… lalu jalankan ulang skripnya).
--
-- Urutan menjalankan (DB Tools, z_run_sql, Use prepared statements = OFF):
--   1. sql/RESET_data_bisnis.sql   (hapus data uji; user & pabrik tetap)
--   2. file ini                    (satu transaksi: kalau ada error, TIDAK ADA yang tersimpan; aman diulang)
--   3. sql/R_selftest.sql          (uji alur inti lalu dibatalkan; hasil harus "SELFTEST LOLOS")
-- Baris terakhir hasil query ini = ringkasan cek. Kalau error, pesan menyebut bagian (R3…R7) yang gagal.
-- ============================================================================
"""]
for p in PARTS:
    src = open(os.path.join(ROOT, 'sql', p + '.sql'), encoding='utf-8').read().strip()
    out.append(f"\n\n-- #################################################################### {p}\nDO $$ BEGIN RAISE NOTICE 'mulai {p}'; END $$;\n\n{src}\n")
out.append("""
-- #################################################################### ringkasan
SELECT 'R3–R7 terpasang' AS cek,
       concat_ws(' · ',
         'variant_id harga: ' || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'material_price' AND column_name = 'variant_id'),
         'model tanpa kode: ' || (SELECT (count(*) = 0)::text FROM information_schema.columns WHERE table_name = 'product_model' AND column_name = 'code'),
         'sel varian: ' || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'bom_cell' AND column_name = 'variant_id'),
         'PO SMS: ' || coalesce((SELECT po_factor::text FROM stage_setting WHERE stage = 'SMS'), '-'),
         'model induk: ' || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'product_model' AND column_name = 'parent_model_id')) AS hasil;
""")
open(os.path.join(ROOT, 'sql', 'R_revisi_semua.sql'), 'w', encoding='utf-8', newline='\n').write(''.join(out))
print('OK sql/R_revisi_semua.sql')
