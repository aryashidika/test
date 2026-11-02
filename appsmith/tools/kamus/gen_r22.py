"""R22: tulis sql/R22_kamus.sql (dijalankan sesudah R21_kamus.sql + isi kamus R21).

Fungsi R21 yang diubah disalin dari sql/R21_kamus.sql lalu ditambal (assert bila bagian yang ditambal tidak ketemu), supaya
tidak ada salinan manual 100+ baris. Yang berubah (PLAN R22):
  - kamus: satu teks = satu kode (material / Dimension terisi / warna). Kode pertama yang menang: yang dipakai varian app terbanyak,
    lalu (material) yang tersambung ke material app, lalu kode terkecil (= baris pertama Excel ERP, Excel urut kode). Dimension
    kosong (None) tetap boleh beberapa kode (kode kosong per material, R20 bagian 3).
  - fn_variant_code_problems: arah teks -> kode juga dari kamus
  - fn_variant_compose: kode dari kamus dipakai tanpa syarat "tepat satu kode" (sekarang selalu satu); (None) tanpa kode kosong
    material = kode kosong pertama di kamus
  - fn_code_dict_learn: bagian baru yang teksnya sudah ada di kamus dengan kode lain tidak ditulis (tidak error)
  - fn_material_add: nama sama dengan kamus -> awalan kamus tersambung ke material baru
Pakai: python -X utf8 -I gen_r22.py   (dari folder tools/kamus)
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
SQL = os.path.join(HERE, '..', '..', 'sql')


def block(src, name):
    m = re.search(r'CREATE OR REPLACE FUNCTION ' + name + r'\(.*?\n\$function\$;\n', src, re.S)
    assert m, name
    return m.group(0)


def patch(text, old, new):
    assert text.count(old) == 1, old[:60]
    return text.replace(old, new)


r21 = open(os.path.join(SQL, 'R21_kamus.sql'), encoding='utf-8').read()
r19 = open(os.path.join(SQL, 'R19_catatan_uji.sql'), encoding='utf-8').read()

# ---------------------------------------------------------------- fn_variant_code_problems
prob = block(r21, 'fn_variant_code_problems')
prob = patch(prob, "  RETURN v_out;\nEND;", """  -- R22 arti -> kode dari kamus: satu teks = satu kode (Dimension kosong dikecualikan: kode kosong per material, di atas)
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
END;""")

# ---------------------------------------------------------------- fn_variant_compose
comp = block(r21, 'fn_variant_compose')
comp = patch(comp, """  IF v_mid IS NULL AND v_tkey <> '' THEN    -- dimension belum dipakai varian app: kode kamus bila hanya SATU
    SELECT min(d.code) INTO v_mid FROM code_dict_dimension d
     WHERE d.factory_id = v_factory AND d.thickness_key = v_tkey HAVING count(*) = 1;
  END IF;""", """  IF v_mid IS NULL THEN    -- R22: kode kamus (satu teks = satu kode; (None) tanpa kode kosong material ini = kode kosong pertama)
    SELECT min(d.code) INTO v_mid FROM code_dict_dimension d
     WHERE d.factory_id = v_factory AND d.thickness_key = v_tkey;
  END IF;""")
comp = patch(comp, """  IF v_last IS NULL AND NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = v_factory AND length(v.code) = 10
                                       AND v.color_key = v_ckey) THEN
    SELECT min(d.code) INTO v_last FROM code_dict_color d    -- warna belum dipakai varian app: kode kamus bila hanya SATU
     WHERE d.factory_id = v_factory AND d.color_key = v_ckey HAVING count(*) = 1;
  END IF;""", """  IF v_last IS NULL THEN                   -- R22: kode kamus (satu warna = satu kode)
    SELECT min(d.code) INTO v_last FROM code_dict_color d
     WHERE d.factory_id = v_factory AND d.color_key = v_ckey;
  END IF;""")

# ---------------------------------------------------------------- fn_material_add (R19 + sambungan awalan kamus)
add = re.search(r'CREATE OR REPLACE FUNCTION fn_material_add\(p_token text, p_name text, p_category text, p_uom text, '
                r'p_is_process boolean DEFAULT false\).*?\n\$function\$;\n', r19, re.S).group(0)
add = patch(add, "  RETURNING id INTO v_id;\n  RETURN v_id;", """  RETURNING id INTO v_id;
  -- R22: nama sama dengan nama kamus -> awalan kamus tersambung ke material baru (tidak ada material kembar)
  IF NOT v_proc THEN
    UPDATE code_dict_material d SET material_id = v_id
     WHERE d.factory_id = v_factory AND d.name_key = fn_tight_key(p_name) AND d.material_id IS NULL;
  END IF;
  RETURN v_id;""")

head = """-- ============================================================================
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
"""
out = head + prob + "\n-- ---------------------------------------------------------------- 4. susun kode otomatis dari kamus\n" + comp
out += "\n-- ---------------------------------------------------------------- 5. Master Material: nama = nama kamus -> awalan tersambung\n" + add
out += """
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
"""
assert out.isascii(), [c for c in out if ord(c) > 127][:5]
with open(os.path.join(SQL, 'R22_kamus.sql'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('R22_kamus.sql', len(out.encode()), 'byte')
