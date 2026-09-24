"""Entry point untuk versi web (lokal). Jalankan dengan: python run_web.py

Server Flask jalan di 127.0.0.1 (tidak diekspos ke jaringan), lalu otomatis
membuka browser default ke halaman aplikasi. Tetap 100% lokal: tidak ada
dependency internet (htmx dan CSS disajikan dari folder static sendiri).
"""
import threading
import webbrowser

from app.web import create_app

HOST = "127.0.0.1"
PORT = 5000


def main():
    app = create_app()
    url = f"http://{HOST}:{PORT}/"
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    app.run(host=HOST, port=PORT, debug=False, use_reloader=False, threaded=False)


if __name__ == "__main__":
    main()
