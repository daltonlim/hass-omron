#!/usr/bin/env python3
"""Serve the Omron BLE reader on localhost so Chrome allows Web Bluetooth."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os

os.chdir(os.path.dirname(os.path.abspath(__file__)))
HOST = "127.0.0.1"
PORT = 8765
print(f"Open Chrome at http://{HOST}:{PORT}/")
ThreadingHTTPServer((HOST, PORT), SimpleHTTPRequestHandler).serve_forever()
