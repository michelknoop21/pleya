#!/usr/bin/env python3
"""Meet onbekende bibliotheeksoorten zonder de server of het protocol te wijzigen."""
import argparse
import gzip
import http.client
import io
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from urllib.parse import urlsplit

LIBRARY_ID = '019a0000-0014-7000-8000-000000000014'
LIBRARY = {'id': LIBRARY_ID, 'title': 'PS-14 meetbibliotheek', 'kind': 'books', 'item_count': 0, 'permission': 'view'}
HOP_HEADERS = {'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade'}
MAX_BODY = 1 << 20


def handler_for(upstream):
    target = urlsplit(upstream)
    if target.scheme not in {'http', 'https'} or not target.hostname or target.username or target.password or target.query or target.fragment:
        raise ValueError('upstream moet een vaste http(s)-basis zonder credentials, query of fragment zijn')

    class Proxy(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Aanvragen kunnen credentials dragen; de meetproxy bewaart geen verkeerslog.

        def send_response(self, code, message=None):
            self._reply_started = True
            super().send_response(code, message)

        def forward(self):
            request = urlsplit(self.path)
            if request.scheme or request.netloc or not request.path.startswith('/'):
                self.send_error(400)
                return
            if self.command == 'GET' and request.path == f'/pleya/v1/libraries/{LIBRARY_ID}/items':
                self.json_response({'items': [], 'next_cursor': None})
                return
            try:
                size = int(self.headers.get('Content-Length', '0'))
            except ValueError:
                self.send_error(400)
                return
            if size < 0 or size > MAX_BODY or self.headers.get('Transfer-Encoding'):
                self.send_error(413)
                return
            body = self.rfile.read(size) if size else None
            connection_headers = {x.strip().lower() for x in self.headers.get('Connection', '').split(',')}
            headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS | connection_headers | {'host', 'accept-encoding'}}
            headers['Accept-Encoding'] = 'identity'
            if self.command == 'GET' and request.path == '/pleya/v1/libraries':
                headers = {k: v for k, v in headers.items() if k.lower() not in {'if-none-match', 'if-modified-since'}}
            cls = http.client.HTTPSConnection if target.scheme == 'https' else http.client.HTTPConnection
            connection = cls(target.hostname, target.port, timeout=30)
            try:
                connection.request(self.command, target.path.rstrip('/') + self.path, body, headers)
                response = connection.getresponse()
                transform = self.command == 'GET' and request.path == '/pleya/v1/libraries' and response.status == 200
                response_headers = response.getheaders()
                if transform:
                    data = response.read(MAX_BODY + 1)
                    if len(data) > MAX_BODY:
                        raise ValueError('bibliothekenantwoord te groot')
                    encoding = response.getheader('Content-Encoding', 'identity')
                    if encoding == 'gzip':
                        # Ook de uitgepakte representatie blijft begrensd.
                        with gzip.GzipFile(fileobj=io.BytesIO(data)) as decoded:
                            data = decoded.read(MAX_BODY + 1)
                    elif encoding != 'identity':
                        raise ValueError('niet ondersteunde encoding voor bibliothekenantwoord')
                    if len(data) > MAX_BODY:
                        raise ValueError('bibliothekenantwoord te groot')
                    document = json.loads(data)
                    if not isinstance(document, dict) or not isinstance(document.get('items'), list):
                        raise ValueError('onjuist bibliothekenantwoord')
                    if any(row.get('id') == LIBRARY_ID for row in document['items'] if isinstance(row, dict)):
                        raise ValueError('meet-ID bestaat al')
                    document['items'].append(LIBRARY)
                    self.json_response(document)
                    return
                self.send_response(response.status)
                removed = HOP_HEADERS | {x.strip().lower() for x in response.getheader('Connection', '').split(',')}
                for key, value in response_headers:
                    if key.lower() not in removed:
                        self.send_header(key, value)
                self.end_headers()
                if self.command != 'HEAD':
                    while data := response.read(64 << 10):
                        self.wfile.write(data)
            except (OSError, ValueError, http.client.HTTPException):
                # Geen upstream-URL, headers of body in het foutantwoord.
                if getattr(self, '_reply_started', False):
                    self.close_connection = True
                else:
                    self.send_error(502, 'meetproxy kon het antwoord niet doorgeven')
            finally:
                connection.close()

        def json_response(self, document):
            data = json.dumps(document, separators=(',', ':')).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = forward

    return Proxy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', required=True)
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=18865)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.bind, args.port), handler_for(args.upstream))
    print(f'PS-14 meetproxy luistert op {args.bind}:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
