"""Browser UI for Underdog Woof. Run: python webui.py  then open http://127.0.0.1:8000"""
import io
import json
import os
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

from underdog_woof import SR, VOICES, Woof
from underdog_woof.runtime import write_wav

MAX_CHARS = 2000
HTML = os.path.join(os.path.dirname(os.path.abspath(__file__)), "webui.html")
_models, _lock = {}, threading.Lock()  # RNG is global and the model is not thread-safe: one synthesis at a time


def synth(text, voice, seed, temp):
    with _lock:
        if voice not in _models:
            _models[voice] = Woof(voice=voice)
        tts = _models[voice]
        tts.temp = temp
        t = time.perf_counter()
        wav = tts(text, seed=seed)
        el = time.perf_counter() - t
    buf = io.BytesIO()
    write_wav(buf, wav)
    return buf.getvalue(), len(wav) / SR, el


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype, headers=()):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _err(self, code, msg):
        self._send(code, json.dumps({"error": msg}).encode(), "application/json")

    def do_GET(self):
        if urlparse(self.path).path != "/":
            return self._err(404, "not found")
        with open(HTML, "rb") as f:
            self._send(200, f.read(), "text/html; charset=utf-8")

    def do_POST(self):
        if urlparse(self.path).path != "/tts":
            return self._err(404, "not found")
        try:
            n = int(self.headers.get("Content-Length", 0))
            if n > 64 * 1024:
                return self._err(413, "request too large")
            req = json.loads(self.rfile.read(n) or b"{}")
            text = str(req.get("text", "")).strip()
            voice = req.get("voice", "juno")
            seed = int(req.get("seed", 0))
            temp = float(req.get("temp", 0.5))
        except (ValueError, TypeError) as e:
            return self._err(400, f"bad request: {e}")
        if not text:
            return self._err(400, "text is empty")
        if len(text) > MAX_CHARS:
            return self._err(400, f"text over {MAX_CHARS} characters")
        if voice not in VOICES:
            return self._err(400, f"voice must be one of {VOICES}")
        if not 0.05 <= temp <= 1.5:
            return self._err(400, "temp must be between 0.05 and 1.5")
        try:
            wav, dur, el = synth(text, voice, seed, temp)
        except Exception as e:  # surface model errors to the UI instead of dropping the connection
            return self._err(500, f"synthesis failed: {e}")
        self._send(200, wav, "audio/wav", [("X-Audio-Seconds", f"{dur:.2f}"), ("X-Elapsed-Seconds", f"{el:.2f}")])


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8000)
    a = ap.parse_args()
    print(f"Underdog Woof UI on http://{a.host}:{a.port}")
    HTTPServer((a.host, a.port), Handler).serve_forever()
