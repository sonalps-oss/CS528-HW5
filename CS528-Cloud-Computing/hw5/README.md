# CS528 HW5 — Google Cloud SQL request analytics

Project: `directed-fabric-508221-d2`. Zone: `us-central1-a`. Bucket: `sonal-graph-2026-sps`.

## Deployment

From Cloud Shell, in this `hw5/` directory:

```bash
chmod +x setup.sh cleanup.sh startup.sh deploy_autostop.sh run_clients.sh
./setup.sh
./deploy_autostop.sh
```

**Pause the Scheduler job during all active DB usage.** It is initially paused by `deploy_autostop.sh`. Resume it after development/tests, or explicitly stop SQL when finished.

New VM: `hw5-server` (existing HW4 machines untouched). Startup metadata installs the application, fetches code from `gs://sonal-graph-2026-sps/hw5-code/`, creates the schema, and starts the systemd service. The bootstrap log is `/var/log/hw5-startup.log`. Verify by `gcloud compute instances get-serial-port-output hw5-server --zone=us-central1-a | tail` and read logs over SSH.

## Verify startup

```bash
IP=$(gcloud compute instances describe hw5-server --zone=us-central1-a --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
# Valid files must be in graph_data and use their real numeric names.
curl -i "http://$IP:8080/graph_data/1.html"
```

## Schema

`requests(id PK, request_time, observed_at, country, client_ip, gender, age_group, income_group, is_banned, requested_file, http_status)` for all requests.

`request_errors(id PK, request_time, requested_file, error_code)` for non-200 requests only.

The added primary key in the errors table is required by the assignment. PostgreSQL admin account credentials are stored in Secret Manager for reliable PostgreSQL 15 schema creation; restrict access to the VM service account and project admins. `is_banned` is derived from the original HW4 forbidden-country code set translated to country names. `X-time` is used as request_time; missing or malformed values fall back to server UTC. Client-supplied `X-client-IP` is trusted only for this homework simulation.

## Curl screenshots (three cases)

Use `gcloud compute ssh hw5-server --zone=us-central1-a` and inside VM:

```bash
cd /opt/hw5
sudo -u hw5app env $(cat /etc/hw5.env | xargs) /opt/hw5/.venv/bin/python report_stats.py
```

More useful before/after snapshots are provided by `show_rows.py` (below), showing last five rows of each table. Take one screenshot BEFORE and AFTER each request.

```bash
# Example 200 (assuming graph_data/1.html exists):
curl -i "http://$IP:8080/sonal-graph-2026-sps/graph_data/1.html" \
  -H 'X-country: Benin' -H 'X-client-IP: 1.2.3.4' -H 'X-gender: Male' \
  -H 'X-age: 26-35' -H 'X-income: 20k-40k' -H 'X-time: 2026-10-27 04:00:00'
# Example 404:
curl -i "http://$IP:8080/graph_data/99999999.html" -H 'X-country: Benin'
# Example 400:
curl -i "http://$IP:8080/graph_data/1.html" -H 'X-country: Iran'
```

## Load test

Place the instructor's **updated Linux `http-client`** next to `run_clients.sh`; don't commit a binary without your instructor's permission. Pass the verified MAXIMUM file index, not the number of files.

```bash
./run_clients.sh MAX_FILE_INDEX 42
```

Two identical-seed 50K clients run concurrently. When complete, run `report_stats.py` inside the server VM for six statistics and four performance measures. The sum of successful and failed logged requests should equal the expected 100,000; check console for any database logging failures and rerun if needed.

## Hourly auto-stop

Function `cloud_function/main.py` is deployed as a second-generation authenticated HTTP function, invoked hourly by a Cloud Scheduler job. During active development, pause the job:

```bash
gcloud scheduler jobs pause hw5-sql-autostop --location=us-central1
```

When finished, resume it:

```bash
gcloud scheduler jobs resume hw5-sql-autostop --location=us-central1
```

To stop immediately, without waiting for hourly trigger:

```bash
gcloud sql instances patch hw5-postgres --activation-policy=NEVER
```

To resume working:

```bash
gcloud scheduler jobs pause hw5-sql-autostop --location=us-central1
gcloud sql instances patch hw5-postgres --activation-policy=ALWAYS
```

## Cleanup

```bash
./cleanup.sh
```

Deletes HW5 compute VM and firewall, scheduler and cloud function, but **preserves Cloud SQL instance/tables and stops Cloud SQL**, as required. Does not delete existing HW4 VMs or the bucket. No reserved static IP used. No `gcloud auth application-default login` used.

## Deliverables

Submit the `hw5/` folder, **modified server.py**, **unmodified updated instructor client (where permitted)**, Cloud Function, scripts, `setup_schema.py`, a PDF with configuration/schema, screenshots (before/after curl for 1 success + 2 errors), 4 timings, 6 statistics, and resource costs. Add `billing_report.pdf` after billing posts if needed.

**Limitations:** This has been authored for your current environment, but has not been deployed to your account from this chat. Validate quota, Cloud SQL tier availability, enabled APIs, and exact client parameters in Cloud Shell; do not claim it worked until you observe it. The original HW4 Pub/Sub forbidden-country alert path is not carried into this HW5 implementation; if your grader tests preservation of HW4 reporter behavior, restore that optional event publisher in `server.py`.
