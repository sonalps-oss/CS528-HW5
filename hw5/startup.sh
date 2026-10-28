#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/hw5-startup.log) 2>&1
METADATA=http://metadata.google.internal/computeMetadata/v1/instance/attributes
getmeta() { curl -fsS -H 'Metadata-Flavor: Google' "$METADATA/$1"; }
PROJECT=$(getmeta hw5-project)
BUCKET=$(getmeta hw5-bucket)
INSTANCE=$(getmeta hw5-instance)
SECRET=$(getmeta hw5-secret)

# Always ensure service starts on reboot; do not reinstall packages on reboot.
if [ -f /var/log/startup_already_done ]; then
  echo 'HW5 setup already ran; starting service if necessary'
  systemctl start hw5.service || true
  exit 0
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip curl ca-certificates
mkdir -p /opt/hw5 /var/log/hw5
id hw5app >/dev/null 2>&1 || useradd --system --home-dir /opt/hw5 --shell /usr/sbin/nologin hw5app
TOKEN=$(curl -fsS -H 'Metadata-Flavor: Google' \
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
for FILE in server.py db.py setup_schema.py report_stats.py show_rows.py requirements.txt; do
  curl -fSs --retry 4 -H "Authorization: Bearer $TOKEN" \
    "https://storage.googleapis.com/storage/v1/b/${BUCKET}/o/hw5-code%2F${FILE}?alt=media" \
    -o "/opt/hw5/$FILE"
done
python3 -m venv /opt/hw5/.venv
/opt/hw5/.venv/bin/pip install --disable-pip-version-check -r /opt/hw5/requirements.txt
cat >/etc/hw5.env <<EOF
PROJECT_ID=$PROJECT
BUCKET=$BUCKET
INSTANCE_CONNECTION_NAME=$PROJECT:us-central1:$INSTANCE
DB_SECRET=$SECRET
PORT=8080
EOF
chmod 644 /etc/hw5.env
chown -R hw5app:hw5app /opt/hw5 /var/log/hw5
cat >/etc/systemd/system/hw5.service <<'EOF'
[Unit]
Description=CS528 HW5 HTTP server
After=network-online.target
Wants=network-online.target
[Service]
User=hw5app
WorkingDirectory=/opt/hw5
EnvironmentFile=/etc/hw5.env
ExecStart=/opt/hw5/.venv/bin/python /opt/hw5/server.py
Restart=always
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
set -a
source /etc/hw5.env
set +a
/opt/hw5/.venv/bin/python /opt/hw5/setup_schema.py
systemctl daemon-reload
systemctl enable --now hw5.service
touch /var/log/startup_already_done
echo 'HW5 VM configured'
