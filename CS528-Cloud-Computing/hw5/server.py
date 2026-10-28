#!/usr/bin/env python3
"""CS528 HW5: threaded GCS server + PostgreSQL request/error logging."""
import json
import os
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, unquote, parse_qs
import pycountry
from google.cloud import storage
from google.api_core.exceptions import NotFound, Forbidden
from sqlalchemy import text
from db import engine

PROJECT = os.environ['PROJECT_ID']
BUCKET = os.environ['BUCKET']
PORT = int(os.environ.get('PORT', '8080'))
GCS = storage.Client(project=PROJECT)
SQL = engine()
TIMINGS_FILE = '/var/log/hw5/timings.jsonl'
TIMINGS_LOCK = threading.Lock()
BANNED_CODES = {'KP','IR','CU','MM','IQ','LY','SD','ZW','SY'}  # Preserved from HW4
BANNED_ALIASES = {
    'north korea':'KP','democratic people\'s republic of korea':'KP',
    'iran':'IR','iran, islamic republic of':'IR','cuba':'CU',
    'myanmar':'MM','burma':'MM','iraq':'IQ',
    'libya':'LY','sudan':'SD','zimbabwe':'ZW','syria':'SY','syrian arab republic':'SY'
}

def banned(country):
    normalized = (country or '').strip()
    if normalized.upper() in BANNED_CODES: return True
    if BANNED_ALIASES.get(normalized.lower()) in BANNED_CODES: return True
    try:
        item = pycountry.countries.lookup(normalized)
        return item.alpha_2 in BANNED_CODES
    except LookupError:
        return False

def parse_time(value):
    if value:
        try: return datetime.fromisoformat(value.strip().replace('Z', '+00:00')).replace(tzinfo=None)
        except ValueError: pass
    return datetime.now(timezone.utc).replace(tzinfo=None)

def normalize_file(raw):
    path = unquote(urlsplit(raw).path).strip().lstrip('/')
    prefix = BUCKET + '/'
    if path.startswith(prefix): path = path[len(prefix):]
    # Restrict access to serving files. Avoid traversal and internal code objects.
    if not path.startswith('graph_data/') or '..' in path.split('/') or not path.endswith('.html'):
        raise ValueError('Invalid file path')
    return path

def record(row, timings):
    start = time.perf_counter_ns()
    with SQL.begin() as conn:
        conn.execute(text("""INSERT INTO requests
            (request_time,country,client_ip,gender,age_group,income_group,is_banned,requested_file,http_status)
            VALUES (:request_time,:country,:client_ip,:gender,:age_group,:income_group,:is_banned,:requested_file,:http_status)"""), row)
        if row['http_status'] != 200:
            conn.execute(text("""INSERT INTO request_errors (request_time,requested_file,error_code)
                         VALUES (:request_time,:requested_file,:http_status)"""),row)
    timings['database_ms'] = round((time.perf_counter_ns()-start)/1e6, 4)
    with TIMINGS_LOCK:
        with open(TIMINGS_FILE,'a',encoding='utf-8') as f:
            f.write(json.dumps(timings, separators=(',', ':'))+'\n')

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, fmt, *args):
        pass  # Avoid 100K stdout writes; request rows reside in Cloud SQL
    def response(self, status, payload, content_type='text/plain; charset=utf-8'):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        if payload: self.wfile.write(payload)
        self.wfile.flush()
    def filename(self):
        if self.command == 'GET': return normalize_file(self.path)
        length = int(self.headers.get('Content-Length','0'))
        if length < 0 or length > 8192: raise ValueError('Bad payload length')
        payload = self.rfile.read(length).decode('utf-8')
        ctype = self.headers.get('Content-Type','').split(';')[0]
        if ctype == 'application/json':
            v = json.loads(payload)
            raw = str(v.get('file') or v.get('filename') or v.get('path') or '')
        elif ctype == 'application/x-www-form-urlencoded':
            raw = parse_qs(payload).get('file',[''])[0]
        else: raw = payload.strip()
        return normalize_file(raw)
    def serve(self):
        stage = time.perf_counter_ns()
        country = self.headers.get('X-country', self.headers.get('X-Country-Code',''))
        blocked = banned(country)
        row = dict(request_time=parse_time(self.headers.get('X-time')),
            country=country, client_ip=self.headers.get('X-client-IP',self.client_address[0]),
            gender=self.headers.get('X-gender'), age_group=self.headers.get('X-age'),
            income_group=self.headers.get('X-income'), is_banned=blocked,
            requested_file=unquote(urlsplit(self.path).path), http_status=500)
        timings = {'header_ms':0.0,'storage_ms':0.0,'response_ms':0.0,'database_ms':0.0}
        try:
            filename = self.filename()
            row['requested_file'] = filename
            timings['header_ms'] = round((time.perf_counter_ns()-stage)/1e6,4)
            if blocked:
                code, body, ctype = 400, b'Permission denied: forbidden country\n', 'text/plain; charset=utf-8'
            else:
                stage = time.perf_counter_ns()
                try:
                    body = GCS.bucket(BUCKET).blob(filename).download_as_bytes()
                    code, ctype = 200, 'application/octet-stream'
                except (NotFound, Forbidden):
                    code, body, ctype = 404, b'File not found\n', 'text/plain; charset=utf-8'
                finally:
                    timings['storage_ms'] = round((time.perf_counter_ns()-stage)/1e6,4)
        except (ValueError, UnicodeError, json.JSONDecodeError):
            code, body, ctype = 404, b'File not found\n', 'text/plain; charset=utf-8'
            timings['header_ms'] = round((time.perf_counter_ns()-stage)/1e6,4)
        except Exception as exc:
            print('Request processing error:', repr(exc), flush=True)
            code, body, ctype = 500, b'Internal server error\n', 'text/plain; charset=utf-8'
        row['http_status'] = code
        stage = time.perf_counter_ns()
        try:
            self.response(code, body, ctype)
        except (BrokenPipeError,ConnectionResetError) as exc:
            print('Client disconnected:', repr(exc), flush=True)
        finally:
            timings['response_ms'] = round((time.perf_counter_ns()-stage)/1e6,4)
        try:
            record(row, timings)
        except Exception as exc:
            print('DATABASE LOG FAILURE:', repr(exc), flush=True)
    do_GET = serve
    do_POST = serve
    def unsupported(self):
        # No body consumption for unsupported methods.
        self.close_connection = True
        self.serve()
    do_PUT = unsupported
    do_DELETE = unsupported
    do_HEAD = unsupported
    do_OPTIONS = unsupported
    do_PATCH = unsupported

if __name__ == '__main__':
    print(f'HW5 server on 0.0.0.0:{PORT} bucket={BUCKET}',flush=True)
    ThreadingHTTPServer(('0.0.0.0',PORT),Handler).serve_forever()
