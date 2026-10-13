#!/usr/bin/env python3
"""Cihaz testi için gzip'li statik sunucu — build/web'i servis eder.

`python -m http.server` gzip yapmaz; release main.dart.js (~2.8MB) ham iner
ve telefonda yavaş açılır. Bu sunucu gzip + uzun cache ile teslim eder →
telefonda ilk yükleme çok daha hızlı (~2.8MB → ~0.8MB).

Kullanım:  python3 serve_web.py [port]   (kök: ./build/web, bind 0.0.0.0)
"""
import gzip
import io
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")
_COMPRESSIBLE = (
    ".js", ".json", ".html", ".css", ".wasm", ".svg", ".map", ".otf", ".ttf"
)
# Yalnız içerik-hash'li / versiyonlu dizinler uzun cache'lenir.
# main.dart.js, *.json, flutter_bootstrap.js vb. SABİT adlı ama her build'de
# içeriği değişir → cache'lenirse telefon eski sürümü görür. Bu yüzden
# uygulama kabuğu HİÇ cache'lenmez (no-store).
_LONG_CACHE_PREFIXES = ("/assets/", "/canvaskit/", "/icons/")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    # Base do_GET/do_HEAD send_head()'i çağırır, dönen stream'i yazar.
    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            path = os.path.join(path, "index.html")
        if not os.path.isfile(path):
            self.send_error(404, "File not found")
            return None
        try:
            with open(path, "rb") as fh:
                raw = fh.read()
        except OSError:
            self.send_error(404, "File not found")
            return None

        url_path = self.path.split("?")[0]
        ctype = self.guess_type(path)
        accepts_gzip = "gzip" in self.headers.get("Accept-Encoding", "")
        do_gzip = (
            accepts_gzip
            and path.endswith(_COMPRESSIBLE)
            and len(raw) > 1024
        )
        if do_gzip:
            buf = io.BytesIO()
            with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=6) as g:
                g.write(raw)
            payload = buf.getvalue()
        else:
            payload = raw

        self.send_response(200)
        self.send_header("Content-Type", ctype)
        if do_gzip:
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Vary", "Accept-Encoding")
        self.send_header("Content-Length", str(len(payload)))
        if url_path.startswith(_LONG_CACHE_PREFIXES):
            self.send_header("Cache-Control", "public, max-age=31536000")
        else:
            # Uygulama kabuğu — her zaman taze (telefon güncellemeyi görsün).
            self.send_header("Cache-Control", "no-store, must-revalidate")
        self.end_headers()
        return io.BytesIO(payload)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    os.chdir(ROOT)
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"gzip static server → http://0.0.0.0:{PORT}  (root={ROOT})")
    httpd.serve_forever()
