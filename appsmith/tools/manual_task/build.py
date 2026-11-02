# Membuat ulang semua manual task (Word) ke document/Manual Task/.
# Jalankan: python build.py
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import content_akun, content_master, content_model, content_spec  # noqa: E402

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'document', 'Manual Task'))


def main():
    n = 0
    for mod in (content_akun, content_master, content_model, content_spec):
        folder = os.path.join(OUT, mod.FOLDER)
        os.makedirs(folder, exist_ok=True)
        for fn in mod.TASKS:
            m = fn()
            path = os.path.join(folder, f'{m.number} {m.title}.docx')
            m.save(path)
            n += 1
            print(os.path.relpath(path, OUT))
    print(f'{n} manual dibuat di {OUT}')


if __name__ == '__main__':
    main()
