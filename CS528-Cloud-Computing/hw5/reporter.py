#!/usr/bin/env python3
"""CS528 HW4 - Pub/Sub forbidden-country event reporter."""
import json
import os
from google.cloud import pubsub_v1

project = os.environ['PROJECT_ID']
subscription = os.environ.get('SUBSCRIPTION', 'hw4-forbidden-sub')
client = pubsub_v1.SubscriberClient()
path = client.subscription_path(project, subscription)

def callback(message):
    try:
        payload = json.loads(message.data.decode('utf-8'))
        print(f"FORBIDDEN COUNTRY: {payload['country']} | "
              f"IP: {payload['ip']} | REQUEST: {payload['method']} {payload['path']}", flush=True)
        message.ack()
    except Exception as exc:
        print(f'Malformed event: {exc}', flush=True)
        message.nack()

print(f'Subscribed to {path}', flush=True)
stream = client.subscribe(path, callback=callback)
try:
    stream.result()
finally:
    stream.cancel()
    client.close()
