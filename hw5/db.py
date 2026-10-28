import os
from functools import lru_cache
from google.cloud import secretmanager
from google.cloud.sql.connector import Connector, IPTypes
from sqlalchemy import create_engine

@lru_cache(maxsize=1)
def engine():
    project = os.environ['PROJECT_ID']
    secret_id = os.environ.get('DB_SECRET', 'hw5-db-password')
    resource = f'projects/{project}/secrets/{secret_id}/versions/latest'
    password = secretmanager.SecretManagerServiceClient().access_secret_version(name=resource).payload.data.decode()
    connector = Connector(refresh_strategy='LAZY')
    def connect():
        return connector.connect(os.environ['INSTANCE_CONNECTION_NAME'], 'pg8000', user='postgres', password=password, db='hw5db', ip_type=IPTypes.PUBLIC)
    # Hold connector alive via the creator closure.
    return create_engine('postgresql+pg8000://', creator=connect, pool_size=5,
                         max_overflow=10, pool_timeout=45, pool_pre_ping=True, pool_recycle=1500)
