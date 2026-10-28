#!/usr/bin/env bash
set -euo pipefail
PROJECT_ID='directed-fabric-508221-d2'
REGION='us-central1'
FUNCTION_SA="hw5-shutdown@${PROJECT_ID}.iam.gserviceaccount.com"
SCHEDULER_SA="hw5-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud config set project "$PROJECT_ID" >/dev/null
for ACC in hw5-shutdown hw5-scheduler; do
  gcloud iam service-accounts describe "$ACC@$PROJECT_ID.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$ACC" --project="$PROJECT_ID"
done
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$FUNCTION_SA" \
  --role=roles/cloudsql.admin --quiet >/dev/null
gcloud functions deploy hw5-sql-autostop --gen2 --runtime=python312 \
  --region="$REGION" --source=cloud_function --entry-point=stop_sql \
  --trigger-http --no-allow-unauthenticated --service-account="$FUNCTION_SA" \
  --set-env-vars="PROJECT_ID=$PROJECT_ID,SQL_INSTANCE=hw5-postgres" --project="$PROJECT_ID"
URL=$(gcloud functions describe hw5-sql-autostop --gen2 --region="$REGION" \
  --project="$PROJECT_ID" --format='value(serviceConfig.uri)')
gcloud run services add-iam-policy-binding hw5-sql-autostop --region="$REGION" \
  --member="serviceAccount:$SCHEDULER_SA" --role=roles/run.invoker --project="$PROJECT_ID" >/dev/null
if gcloud scheduler jobs describe hw5-sql-autostop --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud scheduler jobs update http hw5-sql-autostop --location="$REGION" --schedule='0 * * * *' \
    --uri="$URL" --http-method=POST --oidc-service-account-email="$SCHEDULER_SA" \
    --oidc-token-audience="$URL" --project="$PROJECT_ID"
else
  gcloud scheduler jobs create http hw5-sql-autostop --location="$REGION" --schedule='0 * * * *' \
    --uri="$URL" --http-method=POST --oidc-service-account-email="$SCHEDULER_SA" \
    --oidc-token-audience="$URL" --project="$PROJECT_ID"
fi
# Pause during initial development/load test; RESUME when finished to protect credits.
gcloud scheduler jobs pause hw5-sql-autostop --location="$REGION" --project="$PROJECT_ID"
echo 'Autostop installed but PAUSED. Resume after work: gcloud scheduler jobs resume hw5-sql-autostop --location=us-central1'
