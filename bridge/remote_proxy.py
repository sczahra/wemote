from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
TOKEN_FILE = ROOT / 'data' / 'remote_token.txt'
UPSTREAM = 'http://127.0.0.1:8765'
ALLOWED_ORIGIN = re.compile(r'^https://([a-zA-Z0-9-]+\.)?(wemotecontwol|wemote)\.pages\.dev$')


def read_token():
    try:
        return TOKEN_FILE.read_text(encoding='utf-8').strip()
    except Exception:
        return ''


class Handler(BaseHTTPRequestHandler):
    server_version = 'WEMOTE-Remote/0.5.2'

    def _cors(self):
        origin = self.headers.get('Origin', '')
        if ALLOWED_ORIGIN.match(origin):
            self.send_header('Access-Control-Allow-Origin', origin)
            self.send_header('Vary', 'Origin')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Wemote-Token')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Cache-Control', 'no-store')

    def do_OPTIONS(self):
        origin = self.headers.get('Origin', '')
        if origin and not ALLOWED_ORIGIN.match(origin):
            self.send_response(403)
            self.end_headers()
            return
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        self._proxy('GET')

    def do_POST(self):
        self._proxy('POST')

    def _proxy(self, method):
        if not self.path.startswith('/api/'):
            self.send_response(404)
            self.end_headers()
            return

        origin = self.headers.get('Origin', '')
        if origin and not ALLOWED_ORIGIN.match(origin):
            self.send_response(403)
            self.end_headers()
            return

        expected = read_token()
        supplied = self.headers.get('X-Wemote-Token', '')
        if not expected or supplied != expected:
            self.send_response(401)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"detail":"Remote bridge authentication required."}')
            return

        length = int(self.headers.get('Content-Length', '0') or '0')
        body = self.rfile.read(length) if length else None
        headers = {}
        ctype = self.headers.get('Content-Type')
        if ctype:
            headers['Content-Type'] = ctype
        req = Request(UPSTREAM + self.path, data=body, headers=headers, method=method)

        try:
            with urlopen(req, timeout=15) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self._cors()
                if resp.headers.get('Content-Type'):
                    self.send_header('Content-Type', resp.headers.get('Content-Type'))
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        except HTTPError as exc:
            data = exc.read()
            self.send_response(exc.code)
            self._cors()
            if exc.headers.get('Content-Type'):
                self.send_header('Content-Type', exc.headers.get('Content-Type'))
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:
            data = ('{"detail":"Remote proxy error: %s"}' % str(exc).replace('"', "'")).encode('utf-8')
            self.send_response(502)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    def log_message(self, fmt, *args):
        return


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8766), Handler).serve_forever()
