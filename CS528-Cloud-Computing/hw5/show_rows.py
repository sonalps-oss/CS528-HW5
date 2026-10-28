#!/usr/bin/env python3
from sqlalchemy import text
from db import engine
with engine().connect() as c:
    for tbl in ('requests','request_errors'):
        print('\n==',tbl,'count ==', c.execute(text('SELECT COUNT(*) FROM '+tbl)).scalar(),'==')
        for row in c.execute(text('SELECT * FROM '+tbl+' ORDER BY id DESC LIMIT 5')):
            print(tuple(row))
