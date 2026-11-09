#!/usr/bin/env python3
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from threading import Thread
import unittest

from ps14_kind_proxy import handler_for, LIBRARY_ID


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        calls = self.calls

        class Upstream(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                calls.append((self.command, self.path, dict(self.headers)))
                if self.path.startswith('/pleya/v1/libraries'):
                    body = json.dumps({'items': [{'id': 'film', 'kind': 'movies', 'title': 'Film'}]}).encode()
                    kind = 'application/json'
                else:
                    body, kind = bytes(range(256)) * 5000, 'application/octet-stream'
                self.send_response(200)
                self.send_header('Content-Type', kind)
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Set-Cookie', 'first=1')
                self.send_header('Set-Cookie', 'second=2')
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                calls.append((self.command, self.path, dict(self.headers)))
                self.send_response(201)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.upstream = ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
        self.proxy = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(f'http://127.0.0.1:{self.upstream.server_port}'))
        self.threads = []
        for server in (self.upstream, self.proxy):
            thread = Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)

    def tearDown(self):
        for server in (self.proxy, self.upstream):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.proxy.server_port, timeout=5)
        self.addCleanup(connection.close)
        connection.request(method, path, body, headers or {})
        response = connection.getresponse()
        return response.status, response.getheaders(), response.read()

    def test_only_library_list_and_injected_items_are_rewritten(self):
        status, _, body = self.request('GET', '/pleya/v1/libraries?limit=10', headers={'Authorization': 'Bearer fixture', 'If-None-Match': 'old'})
        self.assertEqual(status, 200)
        rows = json.loads(body)['items']
        self.assertEqual(rows[0]['id'], 'film')
        self.assertEqual(rows[-1]['kind'], 'books')
        self.assertEqual(rows[-1]['id'], LIBRARY_ID)
        self.assertEqual(self.calls[0][2]['Authorization'], 'Bearer fixture')
        self.assertNotIn('If-None-Match', self.calls[0][2])
        count = len(self.calls)
        _, _, body = self.request('GET', f'/pleya/v1/libraries/{LIBRARY_ID}/items?limit=3')
        self.assertEqual(json.loads(body), {'items': [], 'next_cursor': None})
        self.assertEqual(len(self.calls), count)

    def test_other_methods_bytes_status_and_duplicate_headers_survive(self):
        status, _, body = self.request('POST', '/pleya/v1/example', b'unchanged body', {'Content-Type': 'text/plain'})
        self.assertEqual((status, body), (201, b'unchanged body'))
        status, headers, body = self.request('GET', '/stream')
        self.assertEqual(status, 200)
        self.assertEqual(body, bytes(range(256)) * 5000)
        self.assertEqual([v for k, v in headers if k.lower() == 'set-cookie'], ['first=1', 'second=2'])

    def test_credentials_and_absolute_request_targets_are_refused(self):
        with self.assertRaises(ValueError):
            handler_for('http://user:password@127.0.0.1')
        status, _, _ = self.request('GET', 'http://another.test/pleya/v1/libraries')
        self.assertEqual(status, 400)
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
