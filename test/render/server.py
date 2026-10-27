import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        sys.stdout.write("REQUEST " + self.path + "\n"); sys.stdout.flush()
        self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 8765), H).serve_forever()
