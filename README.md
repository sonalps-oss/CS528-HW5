# CS528 Cloud Computing — Homework 5

This repository contains the implementation and evidence report for CS528 Homework 5 (Google Cloud Storage HTTP service with Cloud SQL logging, two-client load testing, performance instrumentation, and scheduled Cloud SQL shutdown).

## Submission artifacts

- [`hw5/CS528_HW5_Final_Report.pdf`](hw5/CS528_HW5_Final_Report.pdf) — illustrated report with schema, curl evidence, performance measurements, six statistics, billing snapshot, and cleanup.
- [`hw5/README.md`](hw5/README.md) — deployment, verification, and cleanup instructions.
- [`hw5/setup.sh`](hw5/setup.sh), [`hw5/startup.sh`](hw5/startup.sh), [`hw5/cleanup.sh`](hw5/cleanup.sh) — infrastructure lifecycle scripts.
- [`hw5/server.py`](hw5/server.py) — modified first application; [`hw5/cloud_function/main.py`](hw5/cloud_function/main.py) — database shutdown function.

## Reproducing

Run from **Cloud Shell** in the lowercase `hw5/` directory:

```bash
cd hw5
./setup.sh
./deploy_autostop.sh
# Perform tests described in hw5/README.md
./cleanup.sh
```

The setup uses the fixed assignment GCP project `directed-fabric-508221-d2`, Cloud Storage bucket `sonal-graph-2026-sps`, region `us-central1` and zone `us-central1-a`. It creates **billable** cloud resources. The cleanup stops but retains Cloud SQL.

## Important source-file note

The instructor-provided updated Linux `http-client` binary and the original **unmodified second HW4 application** were not available in the material used to assemble this download, so neither has been fabricated or silently replaced. Before submitting, add the unmodified second application to `hw5/` and the instructor's updated client where course submission rules permit redistributing it. The submission requirements explicitly request the second application.

The PDF's repository URL placeholder must be updated with the actual link after uploading to GitHub. The billing image covers project-wide charges, not isolated HW5 costs.
