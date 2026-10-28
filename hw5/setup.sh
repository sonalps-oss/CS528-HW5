#!/usr/bin/env bash
set -euo pipefail
PROJECT_ID='directed-fabric-508221-d2'  # Required hardcoded project ID
REGION='us-central1'
ZONE='us-central1-a'
BUCKET='sonal-graph-2026-sps'
SQL_INSTANCE='hw5-postgres'
VM='hw5-server'
SECRET='hw5-db-password'
SA="hw4-server@${PROJECT_ID}.iam.gserviceaccount.com"
FUNCTION_SA="hw5-shutdown@${PROJECT_ID}.iam.gserviceaccount.com"
SCHEDULER_SA="hw5-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
gcloud config set project "$PROJECT_ID" >/dev/null

echo 'Enabling APIs ...'
gcloud services enable compute.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com \
  storage.googleapis.com cloudfunctions.googleapis.com cloudbuild.googleapis.com \
  run.googleapis.com cloudscheduler.googleapis.com artifactregistry.googleapis.com \
  iam.googleapis.com --project "$PROJECT_ID"

for ROLE in roles/cloudsql.client roles/secretmanager.secretAccessor roles/storage.objectViewer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$SA" \
    --role="$ROLE" --quiet >/dev/null
done

create_sql() {
  if gcloud sql instances describe "$SQL_INSTANCE" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo 'SQL instance exists: starting (not recreating)'
    gcloud sql instances patch "$SQL_INSTANCE" --activation-policy=ALWAYS --project="$PROJECT_ID" --quiet
  else
    echo 'Creating Cloud SQL PostgreSQL instance (billable) ...'
    gcloud sql instances create "$SQL_INSTANCE" --project="$PROJECT_ID" --region="$REGION" \
      --database-version=POSTGRES_15 --tier=db-g1-small --storage-size=10 \
      --availability-type=zonal --assign-ip --no-backup --no-deletion-protection --quiet
  fi
  gcloud sql databases describe hw5db --instance="$SQL_INSTANCE" --project="$PROJECT_ID" >/dev/null 2>&1 || \
    gcloud sql databases create hw5db --instance="$SQL_INSTANCE" --project="$PROJECT_ID"
  if ! gcloud secrets describe "$SECRET" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo 'Creating SQL credentials securely in Secret Manager ...'
    gcloud secrets create "$SECRET" --replication-policy=automatic --project="$PROJECT_ID" >/dev/null
    local password
    password=$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')
    printf %s "$password" | gcloud secrets versions add "$SECRET" --data-file=- --project="$PROJECT_ID" >/dev/null
    gcloud sql users set-password postgres --instance="$SQL_INSTANCE" --password="$password" --project="$PROJECT_ID"
    unset password
  elif ! gcloud sql users list --instance="$SQL_INSTANCE" --project="$PROJECT_ID" --format='value(name)' | grep -qx postgres; then
    echo 'ERROR: PostgreSQL admin user missing.' >&2
    exit 1
  fi
  # setup_schema.py is invoked on VM startup. Existing tables are preserved.
}
create_sql

for FILE in server.py db.py setup_schema.py report_stats.py show_rows.py requirements.txt; do
  gcloud storage cp "$FILE" "gs://$BUCKET/hw5-code/$FILE" --quiet
done

if ! gcloud compute firewall-rules describe hw5-http --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute firewall-rules create hw5-http --project="$PROJECT_ID" \
    --network=default --allow=tcp:8080 --target-tags=hw5-http --source-ranges=0.0.0.0/0
fi
if gcloud compute instances describe "$VM" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo 'HW5 VM exists: starting it'
  gcloud compute instances start "$VM" --zone="$ZONE" --project="$PROJECT_ID" || true
else
  gcloud compute instances create "$VM" --project="$PROJECT_ID" --zone="$ZONE" \
    --machine-type=e2-standard-2 --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=20GB --service-account="$SA" --scopes=cloud-platform \
    --tags=hw5-http \
    --metadata="hw5-project=$PROJECT_ID,hw5-bucket=$BUCKET,hw5-instance=$SQL_INSTANCE,hw5-secret=$SECRET" \
    --metadata-from-file=startup-script="$ROOT/startup.sh"
fi
IP=$(gcloud compute instances describe "$VM" --zone="$ZONE" --project="$PROJECT_ID" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
echo "Server endpoint: http://$IP:8080/"

# Schedule safety function provisioned separately with deploy_autostop.sh.
echo 'Run ./deploy_autostop.sh after setup succeeds to install hourly Cloud SQL auto-stop.'
