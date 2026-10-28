import os
from google.auth import default
from google.auth.transport.requests import AuthorizedSession
import functions_framework

@functions_framework.http
def stop_sql(request):
    project = os.environ['PROJECT_ID']
    instance = os.environ['SQL_INSTANCE']
    credentials, _ = default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
    session = AuthorizedSession(credentials)
    base = f'https://sqladmin.googleapis.com/sql/v1beta4/projects/{project}/instances/{instance}'
    instance_response = session.get(base, timeout=30)
    instance_response.raise_for_status()
    info = instance_response.json()
    policy = info.get('settings', {}).get('activationPolicy')
    if policy == 'NEVER':
        return ('SQL already stopped', 200)
    response = session.patch(base, json={'settings': {'activationPolicy': 'NEVER'}}, timeout=30)
    response.raise_for_status()
    return ('Cloud SQL stop operation submitted', 200)
