#!/usr/bin/env python3
"""Serve the Omron BLE reader on localhost so Chrome allows Web Bluetooth."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os

os.chdir(os.path.dirname(os.path.abspath(__file__)))
HOST = "127.0.0.1"
PORT = 8765


class NoCacheHandler(SimpleHTTPRequestHandler):
    """Serve fresh files so an edited page never needs a manual hard reload."""

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()


print(f"Open Chrome at http://{HOST}:{PORT}/")
ThreadingHTTPServer((HOST, PORT), NoCacheHandler).serve_forever()
