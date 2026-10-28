#!/usr/bin/env python3
import json
import statistics
from pathlib import Path
from sqlalchemy import text
from db import engine
queries = {
 'Total successful vs unsuccessful': 'SELECT http_status = 200 AS success, COUNT(*) FROM requests GROUP BY success ORDER BY success DESC',
 'Requests from banned countries': 'SELECT COUNT(*) FROM requests WHERE is_banned = TRUE',
 'Male vs Female': 'SELECT gender,COUNT(*) FROM requests GROUP BY gender ORDER BY COUNT(*) DESC',
 'Top five countries': 'SELECT country,COUNT(*) FROM requests GROUP BY country ORDER BY COUNT(*) DESC LIMIT 5',
 'Age group with most requests': 'SELECT age_group,COUNT(*) FROM requests GROUP BY age_group ORDER BY COUNT(*) DESC LIMIT 1',
 'Income group with most requests': 'SELECT income_group,COUNT(*) FROM requests GROUP BY income_group ORDER BY COUNT(*) DESC LIMIT 1',
 'Error count table': 'SELECT error_code,COUNT(*) FROM request_errors GROUP BY error_code ORDER BY error_code'
}
with engine().connect() as conn:
    for label,query in queries.items():
        print('\n== '+label+' ==')
        for row in conn.execute(text(query)): print(tuple(row))

rows=[]
f=Path('/var/log/hw5/timings.jsonl')
if f.exists():
    for line in f.open():
        try: rows.append(json.loads(line))
        except ValueError: pass
if rows:
    print('\n== Timings in milliseconds: avg / p95 / max ==')
    for k in ['header_ms','storage_ms','response_ms','database_ms']:
        vals=sorted(float(r[k]) for r in rows if k in r)
        if vals:
            print(f'{k}: {statistics.mean(vals):.3f} / {vals[int(0.95*(len(vals)-1))]:.3f} / {max(vals):.3f} (n={len(vals)})')
