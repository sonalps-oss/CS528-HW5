#!/usr/bin/env bash
set -euo pipefail
# Run on Cloud Shell / any Linux machine with the instructor's updated http-client in the same folder.
PROJECT_ID='directed-fabric-508221-d2'
ZONE='us-central1-a'
BUCKET='sonal-graph-2026-sps'
INDEX="${1:?Usage: ./run_clients.sh MAX_INDEX [RANDOM_SEED] [SERVER_IP]}"
SEED="${2:-42}"
IP="${3:-$(gcloud compute instances describe hw5-server --zone="$ZONE" --project="$PROJECT_ID" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')}"
CLIENT="${CLIENT:-./http-client}"
test -x "$CLIENT" || { echo "Missing executable updated Linux client: $CLIENT" >&2; exit 1; }
mkdir -p client_logs
"$CLIENT" -d "$IP" -b "$BUCKET" -w graph_data -n 50000 -i "$INDEX" -p 8080 -r "$SEED" -t 30 >client_logs/client1.log 2>&1 &
A=$!
"$CLIENT" -d "$IP" -b "$BUCKET" -w graph_data -n 50000 -i "$INDEX" -p 8080 -r "$SEED" -t 30 >client_logs/client2.log 2>&1 &
B=$!
set +e
wait "$A"; A_STATUS=$?
wait "$B"; B_STATUS=$?
set -e
echo "Client 1 exit=$A_STATUS, Client 2 exit=$B_STATUS. Check client_logs/"
test "$A_STATUS" -eq 0 && test "$B_STATUS" -eq 0
