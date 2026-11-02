-- ============================================================================
-- R22 Appsmith: kamus ERP = sumber pilihan + pembentuk kode (31 Okt 2026). Dibuat oleh tools/kamus/gen_r22.py (jangan diedit tangan).
-- Jalankan SESUDAH R21_kamus.sql + R21_kamus_isi_1..6.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Satu transaksi. Aman diulang. Varian, harga, dan dokumen tidak diubah. Hasil: pesan NOTICE jumlah baris kamus yang dibuang.
-- ============================================================================

-- ---------------------------------------------------------------- 1. satu teks = satu kode
-- Pemenang: kode yang dipakai varian app terbanyak, material: yang tersambung ke material app, lalu kode terkecil.
-- Dimension kosong (None) tidak dikurangi: kode kosong per material (R20 bagian 3).
DO $r22$
DECLARE
  v_m int; v_d int; v_c int; v_mu int; v_du int; v_cu int;
BEGIN
  WITH g AS (SELECT factory_id, name_key FROM code_dict_material GROUP BY 1, 2 HAVING count(*) > 1),
       r AS (SELECT d.factory_id, d.code,
                    row_number() OVER (PARTITION BY d.factory_id, d.name_key ORDER BY
                      (SELECT count(*) FROM material_variant v WHERE v.factory_id = d.factory_id AND length(v.code) = 10
                          AND left(v.code, 4) = d.code) DESC, (d.material_id IS NOT NULL) DESC, d.code) AS rn
               FROM code_dict_material d JOIN g USING (factory_id, name_key)),
       del AS (DELETE FROM code_dict_material d USING r WHERE r.factory_id = d.factory_id AND r.code = d.code AND r.rn > 1
               RETURNING d.factory_id, d.code)
  SELECT count(*), count(*) FILTER (WHERE EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = del.factory_id
                                                   AND length(v.code) = 10 AND left(v.code, 4) = del.code))
    INTO v_m, v_mu FROM del;
  WITH g AS (SELECT factory_id, thickness_key FROM code_dict_dimension WHERE thickness_key <> '' GROUP BY 1, 2 HAVING count(*) > 1),
       r AS (SELECT d.factory_id, d.code,
                    row_number() OVER (PARTITION BY d.factory_id, d.thickness_key ORDER BY
                      (SELECT count(*) FROM material_variant v WHERE v.factory_id = d.factory_id AND length(v.code) = 10
                          AND substr(v.code, 5, 3) = d.code) DESC, d.code) AS rn
               FROM code_dict_dimension d JOIN g USING (factory_id, thickness_key)),
       del AS (DELETE FROM code_dict_dimension d USING r WHERE r.factory_id = d.factory_id AND r.code = d.code AND r.rn > 1
               RETURNING d.factory_id, d.code)
  SELECT count(*), count(*) FILTER (WHERE EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = del.factory_id
                                                   AND length(v.code) = 10 AND substr(v.code, 5, 3) = del.code))
    INTO v_d, v_du FROM del;
  WITH g AS (SELECT factory_id, color_key FROM code_dict_color GROUP BY 1, 2 HAVING count(*) > 1),
       r AS (SELECT d.factory_id, d.code,
                    row_number() OVER (PARTITION BY d.factory_id, d.color_key ORDER BY
                      (SELECT count(*) FROM material_variant v WHERE v.factory_id = d.factory_id AND length(v.code) = 10
                          AND substr(v.code, 8, 3) = d.code) DESC, d.code) AS rn
               FROM code_dict_color d JOIN g USING (factory_id, color_key)),
       del AS (DELETE FROM code_dict_color d USING r WHERE r.factory_id = d.factory_id AND r.code = d.code AND r.rn > 1
               RETURNING d.factory_id, d.code)
  SELECT count(*), count(*) FILTER (WHERE EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = del.factory_id
                                                   AND length(v.code) = 10 AND substr(v.code, 8, 3) = del.code))
    INTO v_c, v_cu FROM del;
  RAISE NOTICE 'R22: kode kembar dibuang dari kamus: material %, Dimension %, warna % (masih dipakai varian app: %, %, %)',
    v_m, v_d, v_c, v_mu, v_du, v_cu;
END
$r22$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_code_dict_material_name ON code_dict_material (factory_id, name_key);
CREATE UNIQUE INDEX IF NOT EXISTS uq_code_dict_dimension_text ON code_dict_dimension (factory_id, thickness_key) WHERE thickness_key <> '';
CREATE UNIQUE INDEX IF NOT EXISTS uq_code_dict_color_text ON code_dict_color (factory_id, color_key);

-- ---------------------------------------------------------------- 2. varian baru -> bagian baru masuk kamus (tanpa error bila teks sudah punya kode lain)
CREATE OR REPLACE FUNCTION fn_code_dict_learn() RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_by text := coalesce(NEW.updated_by, current_setting('app.user', true));
BEGIN
  IF length(NEW.code) <> 10 THEN
    RETURN NULL;
  END IF;
  INSERT INTO code_dict_material (factory_id, code, name, material_id, source, created_by)
  SELECT NEW.factory_id, left(NEW.code, 4), m.name, m.id, 'REGISTER', v_by FROM material m
   WHERE m.id = NEW.material_id
     AND NOT EXISTS (SELECT 1 FROM code_dict_material x WHERE x.factory_id = NEW.factory_id
                        AND x.name_key = fn_tight_key(m.name) AND x.code <> left(NEW.code, 4))
  ON CONFLICT (factory_id, code) DO UPDATE SET material_id = EXCLUDED.material_id
   WHERE code_dict_material.material_id IS NULL
      OR (TG_OP = 'UPDATE' AND code_dict_material.material_id = OLD.material_id AND OLD.material_id <> NEW.material_id);
  INSERT INTO code_dict_dimension (factory_id, code, thickness, source, created_by)
  VALUES (NEW.factory_id, substr(NEW.code, 5, 3), coalesce(NEW.thickness, ''), 'REGISTER', v_by)
  ON CONFLICT DO NOTHING;
  INSERT INTO code_dict_color (factory_id, code, color, source, created_by)
  VALUES (NEW.factory_id, substr(NEW.code, 8, 3), NEW.color, 'REGISTER', v_by)
  ON CONFLICT DO NOTHING;
  RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------- 3. aturan kode (teks -> kode dari kamus)
CREATE OR REPLACE FUNCTION fn_variant_code_problems(p_factory uuid, p_material_id uuid, p_code text, p_color text,
                                                    p_thickness text, p_exclude uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_code  text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')));
  v_color text := fn_clean_color(p_color);
  v_thick text := fn_clean_thickness(p_thickness);
  v_tkey  text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey  text := fn_color_key(p_color);
  v_mat   material%ROWTYPE;
  v_out   text[] := '{}';
  r       record;
BEGIN
  IF length(v_code) <> 10 THEN
    RETURN v_out;
  END IF;
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  -- kode -> arti: 4 awal = satu material (kamus: awalan yang sudah tersambung ke material app)
  SELECT d.material_id, m.name INTO r
    FROM code_dict_material d JOIN material m ON m.id = d.material_id
   WHERE d.factory_id = p_factory AND d.code = left(v_code, 4);
  IF FOUND THEN
    IF r.material_id <> p_material_id THEN
      v_out := v_out || format('Prefix %s belongs to material %s (ERP dictionary). Register this variant in that material.',
                               left(v_code, 4), r.name);
    END IF;
  ELSE
    SELECT x.material_id, x.code INTO r
      FROM (SELECT v.material_id, count(*) AS n, min(v.created_at) AS first_at,
                   (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
              FROM material_variant v
             WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
               AND left(v.code, 4) = left(v_code, 4)
             GROUP BY v.material_id) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
    IF FOUND AND r.material_id <> p_material_id THEN
      v_out := v_out || format('Prefix %s belongs to material %s (code %s). Register this variant in that material.',
                               left(v_code, 4), (SELECT name FROM material WHERE id = r.material_id), r.code);
    END IF;
  END IF;
  -- kode -> arti: 3 tengah = satu dimension
  SELECT d.thickness_key AS tkey, d.thickness INTO r
    FROM code_dict_dimension d WHERE d.factory_id = p_factory AND d.code = substr(v_code, 5, 3);
  IF FOUND THEN
    IF r.tkey <> v_tkey THEN
      v_out := v_out || format('Dimension code %s means %s (ERP dictionary), not %s.',
                               substr(v_code, 5, 3), fn_thickness_label(r.thickness), fn_thickness_label(v_thick));
    END IF;
  ELSE
    SELECT x.tkey, x.thickness, x.code INTO r
      FROM (SELECT v.thickness_key AS tkey, count(*) AS n, min(v.created_at) AS first_at,
                   (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                   (array_agg(v.thickness ORDER BY v.created_at, v.code))[1] AS thickness
              FROM material_variant v
             WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
               AND substr(v.code, 5, 3) = substr(v_code, 5, 3)
             GROUP BY v.thickness_key) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
    IF FOUND AND r.tkey <> v_tkey THEN
      v_out := v_out || format('Dimension code %s means %s (code %s), not %s.',
                               substr(v_code, 5, 3), fn_thickness_label(r.thickness), r.code, fn_thickness_label(v_thick));
    END IF;
  END IF;
  -- kode -> arti: 3 akhir = satu warna
  SELECT d.color_key AS ckey, d.color INTO r
    FROM code_dict_color d WHERE d.factory_id = p_factory AND d.code = substr(v_code, 8, 3);
  IF FOUND THEN
    IF v_ckey <> '' AND r.ckey <> v_ckey THEN
      v_out := v_out || format('Color code %s means %s (ERP dictionary), not %s.', substr(v_code, 8, 3), r.color, v_color);
    END IF;
  ELSE
    SELECT x.ckey, x.color, x.code INTO r
      FROM (SELECT v.color_key AS ckey, count(*) AS n, min(v.created_at) AS first_at,
                   (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                   (array_agg(v.color ORDER BY v.created_at, v.code))[1] AS color
              FROM material_variant v
             WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
               AND substr(v.code, 8, 3) = substr(v_code, 8, 3)
             GROUP BY v.color_key) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
    IF FOUND AND v_ckey <> '' AND r.ckey <> v_ckey THEN
      v_out := v_out || format('Color code %s means %s (code %s), not %s.', substr(v_code, 8, 3), r.color, r.code, v_color);
    END IF;
  END IF;
  -- arti -> kode: satu material = satu awalan
  SELECT x.part, x.code INTO r
    FROM (SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> left(v_code, 4) THEN
    v_out := v_out || format('Material %s uses prefix %s (code %s), not %s.', v_mat.name, r.part, r.code, left(v_code, 4));
  END IF;
  -- arti -> kode: satu dimension = satu kode tengah. R20 bagian 3: dimension kosong = satu kode tengah PER MATERIAL
  -- (UoM tidak dipakai lagi: UoM bisa salah isi). Material lain boleh memakai kode kosong lain (800 / K00 / C00 ...).
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v JOIN material m ON m.id = v.material_id
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.thickness_key = v_tkey AND (v_tkey <> '' OR v.material_id = p_material_id)
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> substr(v_code, 5, 3) THEN
    v_out := v_out || CASE WHEN v_tkey = ''
      THEN format('Material %s without dimension uses dimension code %s (code %s), not %s.', v_mat.name, r.part, r.code,
                  substr(v_code, 5, 3))
      ELSE format('Dimension %s uses dimension code %s (code %s), not %s.', v_thick, r.part, r.code, substr(v_code, 5, 3)) END;
  END IF;
  -- arti -> kode: satu warna di material ini = satu kode akhir
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.color_key = v_ckey
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND v_ckey <> '' AND r.part <> substr(v_code, 8, 3) THEN
    v_out := v_out || format('Color %s in material %s uses color code %s (code %s), not %s.',
                             v_color, v_mat.name, r.part, r.code, substr(v_code, 8, 3));
  END IF;
  -- R22 arti -> kode dari kamus: satu teks = satu kode (Dimension kosong dikecualikan: kode kosong per material, di atas)
  -- hanya untuk material yang belum punya varian berkode: awalannya = awalan kamus yang tersambung ke material ini, atau
  -- (belum tersambung) awalan kamus bernama sama. Material app yang menggabung beberapa material ERP (CARTON BOX SPECS =
  -- 6715 + 6717) memakai awalan variannya (aturan "satu material = satu awalan" di atas)
  IF v_mat.name IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM material_variant w WHERE w.material_id = p_material_id AND length(w.code) = 10
                        AND w.id IS DISTINCT FROM p_exclude) THEN
    SELECT d.code INTO r FROM code_dict_material d
     WHERE d.factory_id = p_factory
       AND (d.material_id = p_material_id OR (d.material_id IS NULL AND d.name_key = fn_tight_key(v_mat.name)))
     ORDER BY (d.material_id IS NOT NULL) DESC, d.code LIMIT 1;
    IF FOUND AND r.code <> left(v_code, 4) THEN
      v_out := v_out || format('Material %s has prefix %s in the ERP dictionary, not %s.', v_mat.name, r.code, left(v_code, 4));
    END IF;
  END IF;
  IF v_tkey <> '' THEN
    SELECT d.code INTO r FROM code_dict_dimension d WHERE d.factory_id = p_factory AND d.thickness_key = v_tkey;
    IF FOUND AND r.code <> substr(v_code, 5, 3) THEN
      v_out := v_out || format('Dimension %s has code %s in the ERP dictionary, not %s.', v_thick, r.code, substr(v_code, 5, 3));
    END IF;
  END IF;
  IF v_ckey <> '' THEN
    SELECT d.code INTO r FROM code_dict_color d WHERE d.factory_id = p_factory AND d.color_key = v_ckey;
    IF FOUND AND r.code <> substr(v_code, 8, 3) THEN
      v_out := v_out || format('Color %s has code %s in the ERP dictionary, not %s.', v_color, r.code, substr(v_code, 8, 3));
    END IF;
  END IF;
  RETURN v_out;
END;
$function$;

-- ---------------------------------------------------------------- 4. susun kode otomatis dari kamus
CREATE OR REPLACE FUNCTION fn_variant_compose(p_material_id uuid, p_thickness text, p_color text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_factory uuid;
  v_tkey    text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey    text := fn_color_key(p_color);
  v_pre     text;
  v_mid     text;
  v_last    text;
BEGIN
  SELECT factory_id INTO v_factory FROM material WHERE id = p_material_id AND NOT is_process;
  IF NOT FOUND OR v_ckey = '' THEN
    RETURN NULL;
  END IF;
  SELECT left(v.code, 4) INTO v_pre FROM material_variant v
   WHERE v.material_id = p_material_id AND length(v.code) = 10
   GROUP BY 1 ORDER BY count(*) DESC, min(v.created_at), 1 LIMIT 1;
  IF v_pre IS NULL THEN
    SELECT min(d.code) INTO v_pre FROM code_dict_material d
     WHERE d.factory_id = v_factory AND d.material_id = p_material_id HAVING count(*) = 1;
  END IF;
  SELECT substr(v.code, 5, 3) INTO v_mid FROM material_variant v
   WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.thickness_key = v_tkey
     AND (v_tkey <> '' OR v.material_id = p_material_id)
   GROUP BY 1 ORDER BY count(*) DESC, min(v.created_at), 1 LIMIT 1;
  IF v_mid IS NULL THEN    -- R22: kode kamus (satu teks = satu kode; (None) tanpa kode kosong material ini = kode kosong pertama)
    SELECT min(d.code) INTO v_mid FROM code_dict_dimension d
     WHERE d.factory_id = v_factory AND d.thickness_key = v_tkey;
  END IF;
  SELECT substr(v.code, 8, 3) INTO v_last FROM material_variant v
   WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.color_key = v_ckey
   GROUP BY 1 ORDER BY count(*) DESC, min(v.created_at), 1 LIMIT 1;
  IF v_last IS NULL THEN                   -- warna belum ada di material ini: kode warna material lain bila di pabrik hanya SATU
    SELECT CASE WHEN count(DISTINCT substr(v.code, 8, 3)) = 1 THEN min(substr(v.code, 8, 3)) END INTO v_last
      FROM material_variant v WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.color_key = v_ckey;
  END IF;
  IF v_last IS NULL THEN                   -- R22: kode kamus (satu warna = satu kode)
    SELECT min(d.code) INTO v_last FROM code_dict_color d
     WHERE d.factory_id = v_factory AND d.color_key = v_ckey;
  END IF;
  IF v_pre IS NULL OR v_mid IS NULL OR v_last IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN v_pre || v_mid || v_last;
END;
$function$;

-- ---------------------------------------------------------------- 5. Master Material: nama = nama kamus -> awalan tersambung
CREATE OR REPLACE FUNCTION fn_material_add(p_token text, p_name text, p_category text, p_uom text, p_is_process boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_proc    boolean := coalesce(p_is_process, false);
  v_id      uuid;
BEGIN
  IF v_factory IS NULL THEN
    RAISE EXCEPTION 'Your account has no factory yet. Ask the System Admin to set your factory.';
  END IF;
  INSERT INTO material (factory_id, name, category, uom, price_method, is_process, status, updated_by)
  VALUES (v_factory, p_name, p_category, p_uom, CASE WHEN v_proc THEN 'QUOTATION' ELSE 'CATALOG' END, v_proc, 'ACTIVE', v_email)
  RETURNING id INTO v_id;
  -- R22: nama sama dengan nama kamus -> awalan kamus tersambung ke material baru (tidak ada material kembar)
  IF NOT v_proc THEN
    UPDATE code_dict_material d SET material_id = v_id
     WHERE d.factory_id = v_factory AND d.name_key = fn_tight_key(p_name) AND d.material_id IS NULL;
  END IF;
  RETURN v_id;
END;
$function$;

-- ---------------------------------------------------------------- 6. saran dari kamus untuk dropdown (dicari ke server, maksimal 8 baris)
-- MATERIAL: hanya awalan yang belum tersambung ke material app (yang sudah ada tampil dari daftar material app).
-- DIMENSION / COLOR: teks kamus; yang kosong (None) tidak ikut.
CREATE OR REPLACE FUNCTION fn_dict_search(p_token text, p_kind text, p_q text)
 RETURNS TABLE(label text, code text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_email   text := fn_auth_any(p_token, ARRAY['edit_specsheet', 'view_drafts']);
  v_factory uuid := fn_user_factory(v_email);
  v_kind    text := upper(coalesce(p_kind, ''));
BEGIN
  IF v_factory IS NULL THEN
    RETURN;
  END IF;
  IF v_kind = 'MATERIAL' THEN
    IF length(fn_tight_key(p_q)) < 2 THEN
      RETURN;
    END IF;
    RETURN QUERY SELECT d.name, d.code FROM code_dict_material d
     WHERE d.factory_id = v_factory AND d.material_id IS NULL AND d.name_key LIKE '%' || fn_tight_key(p_q) || '%'
       AND NOT EXISTS (SELECT 1 FROM material m WHERE m.factory_id = v_factory AND fn_tight_key(m.name) = d.name_key)
     ORDER BY (d.name_key LIKE fn_tight_key(p_q) || '%') DESC, length(d.name), d.name LIMIT 8;
  ELSIF v_kind = 'DIMENSION' THEN
    IF fn_tight_key(p_q) = '' THEN
      RETURN;
    END IF;
    RETURN QUERY SELECT d.thickness, d.code FROM code_dict_dimension d
     WHERE d.factory_id = v_factory AND d.thickness_key <> '' AND d.search_key LIKE '%' || fn_tight_key(p_q) || '%'
     ORDER BY (d.search_key LIKE fn_tight_key(p_q) || '%') DESC, length(d.thickness), d.thickness LIMIT 8;
  ELSIF v_kind = 'COLOR' THEN
    IF fn_tight_key(p_q) = '' THEN
      RETURN;
    END IF;
    RETURN QUERY SELECT d.color, d.code FROM code_dict_color d
     WHERE d.factory_id = v_factory AND d.color_key LIKE '%' || fn_tight_key(p_q) || '%'
     ORDER BY (d.color_key LIKE fn_tight_key(p_q) || '%') DESC, length(d.color), d.color LIMIT 8;
  END IF;
END;
$function$;
