#!/usr/bin/env python3
from sqlalchemy import text
from db import engine

SCHEMA = """
CREATE TABLE IF NOT EXISTS requests (
 id BIGSERIAL PRIMARY KEY,
 request_time TIMESTAMP NOT NULL,
 observed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 country TEXT,
 client_ip TEXT,
 gender TEXT,
 age_group TEXT,
 income_group TEXT,
 is_banned BOOLEAN NOT NULL DEFAULT FALSE,
 requested_file TEXT NOT NULL,
 http_status INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS request_errors (
 id BIGSERIAL PRIMARY KEY,
 request_time TIMESTAMP NOT NULL,
 requested_file TEXT NOT NULL,
 error_code INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS requests_country_idx ON requests(country);
CREATE INDEX IF NOT EXISTS requests_status_idx ON requests(http_status);
"""

def main():
    with engine().begin() as conn:
        for statement in SCHEMA.split(';'):
            if statement.strip():
                conn.execute(text(statement))
    print('HW5 schema ready')
if __name__ == '__main__': main()
