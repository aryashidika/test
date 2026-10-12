-- ============================================================================
-- R8 — catatan hasil uji E2E-R (12 Okt 2026, PLAN.md §6 R8). Jalankan SETELAH R_revisi_semua.sql, lewat z_run_sql
-- di app "DB Tools" (Use prepared statements = OFF). Aman diulang. Satu transaksi: kalau error, tidak ada yang tersimpan.
--
-- 1. Manager Costing boleh mengajukan / menyalin harga (izin manage_price) dan harganya LANGSUNG disetujui
--    (trg_price_self_approve: pengaju yang punya approve_price -> fn_price_activate). Usulan Vendor CBD tetap PROPOSED.
-- 3. Batas 5 article per season dihapus (fn_article_check).
-- 4. Awalan Material Code (4 karakter depan, kode 10 karakter) wajib sama dengan varian lain di material yang sama
--    (trg_material_variant_prefix; hanya dicek saat varian baru / kode diubah).
-- 5. Ajukan harga master dari baris CBD: fn_cbd_price_propose(token, cbd_line_id, harga, currency, berlaku mulai,
--    referensi) -> fn_price_propose untuk varian × supplier baris itu (alur approval sama; bukan override).
-- (Catatan 2 — riwayat harga — hanya di JSObject MaterialDetailCtrl.)
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.stage_setting') IS NULL OR to_regprocedure('fn_price_propose(text,uuid,jsonb,numeric,text,date,text)') IS NULL THEN
    RAISE EXCEPTION 'R3–R7 belum terpasang. Jalankan sql/R_revisi_semua.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- 1. Manager Costing: ajukan = langsung berlaku
INSERT INTO role_permission (role, permission)
SELECT 'MANAGER_COSTING', 'manage_price'
 WHERE NOT EXISTS (SELECT 1 FROM role_permission WHERE role = 'MANAGER_COSTING' AND permission = 'manage_price');

-- Usulan baru dari user yang juga berhak menyetujui -> langsung APPROVED (dia tercatat sebagai penyetuju).
-- Semua pemeriksaan sudah dilakukan fn_price_propose / fn_price_copy / fn_cbd_price_propose sebelum INSERT.
CREATE OR REPLACE FUNCTION fn_price_self_approve() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'PROPOSED' AND NEW.updated_by IS NOT NULL AND fn_has_perm(NEW.updated_by, 'approve_price') THEN
    PERFORM fn_price_activate(NEW.id, NEW.updated_by);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_price_self_approve ON material_price;
CREATE TRIGGER trg_price_self_approve AFTER INSERT ON material_price
  FOR EACH ROW EXECUTE FUNCTION fn_price_self_approve();

-- ---------------------------------------------------------------- 3. Article per season tanpa batas
-- Rapikan isian, kode unik per season (tidak peka huruf besar/kecil), kode article yang sudah dipakai tidak bisa diubah.
CREATE OR REPLACE FUNCTION fn_article_check() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.code     := btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g'));
  NEW.colorway := btrim(regexp_replace(coalesce(NEW.colorway, ''), '\s+', ' ', 'g'));
  IF NEW.code = ''     THEN RAISE EXCEPTION 'Kode article wajib diisi.'; END IF;
  IF NEW.colorway = '' THEN RAISE EXCEPTION 'Colorway wajib diisi.'; END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.specsheet_id IS DISTINCT FROM OLD.specsheet_id THEN
      RAISE EXCEPTION 'Article tidak bisa dipindah ke season lain.';
    END IF;
    IF NEW.code IS DISTINCT FROM OLD.code AND fn_article_is_used(OLD.id) THEN
      RAISE EXCEPTION 'Kode article % tidak bisa diubah karena sudah dipakai di specsheet/CBD.', OLD.code;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM 1 FROM specsheet WHERE id = NEW.specsheet_id FOR UPDATE;   -- antre per season (cek kode unik)
  END IF;
  IF EXISTS (SELECT 1 FROM article WHERE specsheet_id = NEW.specsheet_id AND upper(code) = upper(NEW.code)
                                     AND id <> NEW.id) THEN
    RAISE EXCEPTION 'Kode article % sudah ada di season ini.', NEW.code;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------- 4. Awalan Material Code sama per material
-- Berjalan SETELAH trg_material_variant_check (urutan nama), jadi kode sudah dirapikan (huruf besar).
CREATE OR REPLACE FUNCTION fn_material_variant_prefix() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other text;
BEGIN
  IF length(NEW.code) <> 10 OR (TG_OP = 'UPDATE' AND NEW.code IS NOT DISTINCT FROM OLD.code) THEN
    RETURN NEW;
  END IF;
  SELECT string_agg(DISTINCT left(v.code, 4), ', ') INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.id <> NEW.id AND length(v.code) = 10 AND left(v.code, 4) <> left(NEW.code, 4);
  IF v_other IS NOT NULL THEN
    RAISE EXCEPTION 'Awalan Material Code % berbeda dari varian lain di material ini (%). Semua varian satu material harus berawalan sama — periksa kodenya.',
      left(NEW.code, 4), v_other;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_material_variant_prefix ON material_variant;
CREATE TRIGGER trg_material_variant_prefix BEFORE INSERT OR UPDATE ON material_variant
  FOR EACH ROW EXECUTE FUNCTION fn_material_variant_prefix();

-- ---------------------------------------------------------------- 5. Ajukan harga master dari baris CBD
-- Untuk varian × supplier baris CBD (material CATALOG, baris ACTIVE). Izin & pabrik dicek fn_price_propose
-- (manage_price); Manager Costing -> langsung berlaku (trg_price_self_approve). Mengembalikan batch_id.
CREATE OR REPLACE FUNCTION fn_cbd_price_propose(p_token text, p_line_id uuid, p_price numeric, p_currency text,
                                                p_valid_from date, p_reference text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'manage_price', fn_cbd_line_factory(p_line_id));
  v_line  record;
  v_link  uuid;
BEGIN
  SELECT cl.status, cl.variant_id, cl.supplier_id, cl.material_id, m.price_method, m.name AS material_name
    INTO v_line
    FROM cbd_line cl JOIN material m ON m.id = cl.material_id
   WHERE cl.id = p_line_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Baris CBD tidak ditemukan. Muat ulang halaman.';
  END IF;
  IF v_line.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Baris ini sudah tidak ada di specsheet (MISSING_IN_SPEC).';
  END IF;
  IF v_line.price_method <> 'CATALOG' THEN
    RAISE EXCEPTION 'Material % memakai metode Quotation — isi harganya lewat Isi harga, bukan harga master.', v_line.material_name;
  END IF;
  IF v_line.variant_id IS NULL THEN
    RAISE EXCEPTION 'Baris ini belum punya Material Code (varian) — daftarkan dulu di specsheet.';
  END IF;
  IF v_line.supplier_id IS NULL THEN
    RAISE EXCEPTION 'Baris ini belum punya supplier di specsheet.';
  END IF;
  SELECT id INTO v_link FROM material_supplier WHERE material_id = v_line.material_id AND supplier_id = v_line.supplier_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier baris ini belum terhubung ke material. Hubungkan di Material Detail.';
  END IF;
  RETURN fn_price_propose(p_token, v_link, jsonb_build_array(v_line.variant_id), p_price, p_currency, p_valid_from, p_reference);
END;
$$;

COMMIT;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'R8 terpasang' AS cek,
       'MC manage_price: ' || EXISTS (SELECT 1 FROM role_permission WHERE role = 'MANAGER_COSTING' AND permission = 'manage_price')::text
       || ' · auto-approve: ' || EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_price_self_approve')::text
       || ' · batas 5 article masih ada: ' || (position('>= 5' IN pg_get_functiondef('fn_article_check()'::regprocedure)) > 0)::text
       || ' · awalan kode: ' || EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_material_variant_prefix')::text
       || ' · ajukan dari CBD: ' || (to_regprocedure('fn_cbd_price_propose(text,uuid,numeric,text,date,text)') IS NOT NULL)::text
       AS hasil;
