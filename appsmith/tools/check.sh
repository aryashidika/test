B="D:/OJT_PM/Mock Up/appsmith/exports/export_v11.json"; N="$1"
PY=../venv/Scripts/python.exe
PYTHONIOENCODING=utf-8 $PY validate.py "$B" "$B" | grep '^ERROR' | sort > base_err.txt
PYTHONIOENCODING=utf-8 $PY validate.py "$B" "$N" > build_out.txt
grep -v '^ERROR' build_out.txt | grep -v '^HASIL'
grep '^ERROR' build_out.txt | sort > build_err.txt
echo "error yang sudah ada di base (tidak disentuh): $(comm -12 base_err.txt build_err.txt | wc -l)"
echo "== ERROR BARU =="; comm -13 base_err.txt build_err.txt
echo "== error base yang hilang (diperbaiki) =="; comm -23 base_err.txt build_err.txt
