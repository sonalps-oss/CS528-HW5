# CS528 Homework 5 — Cloud SQL Request Analytics

**Course:** CS528 — Cloud Computing  
**Repository:** [sonalps-oss/CS528-HW5](https://github.com/sonalps-oss/CS528-HW5)  
**Google Cloud project:** `directed-fabric-508221-d2`  
**Region / zone:** `us-central1` / `us-central1-a`

## Overview

This homework builds on Homework 4 by adding **Google Cloud SQL (PostgreSQL)** logging to a Python HTTP server that serves HTML objects from **Google Cloud Storage**. The server reads client-supplied demographic and country headers, records every request and its HTTP status, and separately records unsuccessful requests. It also measures processing stages with Python's high-resolution timer. Two concurrent copies of the updated instructor-provided Linux client generate 50,000 requests each with the same random seed.

## Architecture

```text
Updated Linux http-client (2 concurrent processes, 50,000 each)
                         |
                         v
              Python HTTP server :8080
                |             |
                v             v
         GCS object read   Cloud SQL PostgreSQL
         graph_data/*.html  |             |
                         requests    request_errors
                              |
                       report_stats.py

Cloud Scheduler (hourly) -> Cloud Function -> Stop running Cloud SQL
```

## Infrastructure

| Resource | Value |
|---|---|
| Cloud Storage bucket | `sonal-graph-2026-sps` |
| Serving prefix | `graph_data/` |
| HW5 server VM | `hw5-server` (`e2-standard-2`) |
| VM zone | `us-central1-a` |
| HTTP port | `8080` |
| Cloud SQL instance | `hw5-postgres` |
| PostgreSQL database | `hw5db` |
| Database version | PostgreSQL 15 |

The HW5 server is separate from the existing HW4 VMs. Cloud SQL was **stopped, not deleted**, during cleanup.

## Repository layout

```text
CS528-HW5/
├── README.md
└── hw5/
    ├── setup.sh
    ├── cleanup.sh
    ├── startup.sh
    ├── setup_schema.py
    ├── server.py
    ├── reporter.py
    ├── db.py
    ├── show_rows.py
    ├── report_stats.py
    ├── run_clients.sh
    ├── deploy_autostop.sh
    ├── requirements.txt
    ├── README.md
    └── cloud_function/
        ├── main.py
        └── requirements.txt
```

The updated instructor-provided `http-client` executable and final PDF report can also be kept under `hw5/` if distribution is permitted. **The required grading path is `hw5/setup.sh` and `hw5/cleanup.sh`, directly under the repository root.**

## Database schema

The PostgreSQL schema has two tables, each with a primary key:

- **`requests`**: `id`, `request_time`, `observed_at`, `country`, `client_ip`, `gender`, `age_group`, `income_group`, `is_banned`, `requested_file`, `http_status`, together with instrumented processing durations.
- **`request_errors`**: `id`, `request_time`, `requested_file`, `error_code`. Only non-200 responses are written to this separate table.

The updated client sends `X-country`, `X-client-IP`, `X-gender`, `X-age`, `X-income`, and `X-time`. The server derives `is_banned` from the country and normalizes paths such as `sonal-graph-2026-sps/graph_data/1880.html` to the GCS object path `graph_data/1880.html`. The header values are **simulated assignment data**, not verified real-world client identities or geolocation.

## Deploy

Run the following from Google Cloud Shell in the `hw5/` directory:

```bash
cd hw5
chmod +x setup.sh cleanup.sh startup.sh deploy_autostop.sh run_clients.sh
./setup.sh
```

`setup.sh` creates or reuses the HW5 Cloud SQL instance, configures required resources, and creates the server VM using the metadata-based `startup.sh`. Do not use interactive SSH commands to provision the VM internally; the assignment requires startup-script provisioning.

Confirm the server service:

```bash
gcloud compute ssh hw5-server --zone=us-central1-a \
  --command='sudo systemctl status hw5.service --no-pager'
```

View logged rows in both tables:

```bash
gcloud compute ssh hw5-server --zone=us-central1-a \
  --command='sudo bash -c "set -a; source /etc/hw5.env; set +a; cd /opt/hw5; /opt/hw5/.venv/bin/python show_rows.py"'
```

## Curl demonstration

Get the current VM address (do **not** hardcode a transient external IP):

```bash
HW5_IP=$(gcloud compute instances describe hw5-server --zone=us-central1-a \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
```

Take snapshots of **both SQL tables before and after every request** using the `show_rows.py` command above. Save the resulting screenshots for the PDF report.

**Success (expected HTTP 200, if the object exists):**

```bash
curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' \
  "http://$HW5_IP:8080/graph_data/1880.html" \
  -H 'X-country: Benin' -H 'X-client-IP: 192.0.2.10' \
  -H 'X-gender: Male' -H 'X-age: 26-35' \
  -H 'X-income: 20k-40k' -H 'X-time: 2026-10-27 04:00:00'
```

**Missing object (expected HTTP 404):**

```bash
curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' \
  "http://$HW5_IP:8080/graph_data/99999999.html" -H 'X-country: Benin'
```

**Blocked country (expected HTTP 400):**

```bash
curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' \
  "http://$HW5_IP:8080/graph_data/1880.html" -H 'X-country: Iran'
```

## Concurrent load test

The updated Linux `http-client` supports `-n` (number of requests), `-r` (random seed), `-i` (maximum numbered file index), `-p` (port), and additional options. The load-test script launches **two concurrent processes**, each with `-n 50000` and `-r 42`.

From the Linux client VM, with `http-client` and `run_clients.sh` present:

```bash
chmod +x http-client run_clients.sh
./run_clients.sh 12000 42 SERVER_IP
```

`12000` was used for the recorded test; verify it against the actual numbered file range before reproducing. `SERVER_IP` is the current HW5 server IP. Both processes reported exit status `0` in the recorded execution. This confirms process completion; database counts were checked separately.

## Observed results

Statistics reported by Cloud SQL after the demonstration and load testing:

| Metric | Value |
|---|---:|
| Total recorded requests | 100,008 |
| HTTP 200 successes | 95,318 |
| Unsuccessful requests | 4,690 |
| Requests from banned countries | 4,685 |
| HTTP 400 responses | 4,685 |
| HTTP 404 responses | 5 |

The 100,008 recorded requests include **eight additional demonstration/test requests**, not only the nominal 100,000-request client workload.

### Request demographics

- **Gender:** Female 50,135; Male 49,867; unspecified 6.
- **Top five countries:** Cambodia (594), Burkina Faso (578), Timor-Leste (576), Myanmar (576), Nepal (574).
- **Most active age group:** 26–35 (12,723 requests).
- **Most active income group:** 40k–60k (12,727 requests).

### Timing measurements

Measured with `time.perf_counter_ns()` and reported in milliseconds:

| Operation | Mean (ms) | P95 (ms) | Max (ms) |
|---|---:|---:|---:|
| Header processing | 0.070 | 0.116 | 2.669 |
| Cloud Storage read | 52.687 | 108.602 | 4,712.579 |
| HTTP response sending | 1.123 | 2.253 | 69.389 |
| Database insertion | 12.302 | 15.888 | 337.261 |

Cloud Storage retrieval had the highest average stage latency. These stage timings are **not** a direct measurement of complete end-to-end request latency.

To recompute analytics while the database and server VM are running:

```bash
gcloud compute ssh hw5-server --zone=us-central1-a \
  --command='sudo bash -c "set -a; source /etc/hw5.env; set +a; cd /opt/hw5; /opt/hw5/.venv/bin/python report_stats.py"'
```

## Hourly Cloud SQL shutdown

```bash
./deploy_autostop.sh
```

The deployment creates a second-generation Cloud Function and an hourly Cloud Scheduler job. Pause the scheduler while actively using the database:

```bash
gcloud scheduler jobs pause hw5-sql-autostop --location=us-central1
```

Resume it when appropriate:

```bash
gcloud scheduler jobs resume hw5-sql-autostop --location=us-central1
```

For an immediate stop without deleting stored data:

```bash
gcloud sql instances patch hw5-postgres --activation-policy=NEVER
```

## Cleanup

```bash
./cleanup.sh
```

The HW5 cleanup removes the HW5 VM and associated HW5 infrastructure and **stops, rather than deletes, Cloud SQL**. It does not remove the existing HW4 VMs or the GCS dataset. The recorded cleanup finished with:

```text
Cleanup complete: Cloud SQL stopped, never deleted.
```

## Billing and report

The captured seven-day project-wide billing view showed **$5.08 gross costs, $5.08 in savings/credits, and $0.00 net displayed cost**. This figure is not an isolated HW5-only cost. The assignment permits a separately submitted billing PDF after delayed costs post.

The detailed report contains deployment instructions, schema details, screenshots of SQL tables before and after the three curl requests, six analytics outcomes, four measured stage timings, and cleanup evidence.

**Final report:** `hw5/CS528_HW5_Final_Report.pdf` (include the file at this path if linking it from GitHub).

## Submission notes

- Keep the `hw5/` folder at the repository root.
- Preserve `reporter.py` as the unmodified second HW4 application.
- The accompanying HTTP server used for HW5 may not retain the HW4 Pub/Sub publication path; confirm the grader's expectations about running the reporter, not just submitting its code.
- Make sure `setup.sh`, `cleanup.sh`, and `startup.sh` are executable in Git, particularly if files were uploaded through GitHub's web interface.
- Avoid committing service-account credentials, database passwords, and other secrets.
- Test `setup.sh` and `cleanup.sh` from a fresh deployment environment before final submission.
