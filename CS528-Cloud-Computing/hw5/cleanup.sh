#!/usr/bin/env bash
set -euo pipefail
PROJECT_ID='directed-fabric-508221-d2'
ZONE='us-central1-a'
REGION='us-central1'
gcloud config set project "$PROJECT_ID" >/dev/null
# Remove hourly scheduler before function; SQL remains stopped (not deleted).
gcloud scheduler jobs delete hw5-sql-autostop --location="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || true
gcloud functions delete hw5-sql-autostop --gen2 --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || true
gcloud compute instances delete hw5-server --zone="$ZONE" --project="$PROJECT_ID" --quiet 2>/dev/null || true
gcloud compute firewall-rules delete hw5-http --project="$PROJECT_ID" --quiet 2>/dev/null || true
# This project setup uses ephemeral IPs. If adding a reserved IP later, release it here.
gcloud sql instances patch hw5-postgres --activation-policy=NEVER --project="$PROJECT_ID" --quiet
# No ADC login used; therefore there is no ADC session to revoke.
echo 'Cleanup complete: Cloud SQL stopped, never deleted.'
