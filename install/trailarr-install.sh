#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: cisox
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/nandyalu/trailarr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_hwaccel

PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1

msg_info "Installing Dependencies"
$STD apt install -y \
    git \
    ca-certificates \
    curl \
    wget \
    xz-utils \
    unzip \
    tar \
    pciutils \
    udev \
    usbutils \
    ca-certificates \
    build-essential \
    libffi-dev \
    libssl-dev \
    systemd \
    sudo \
    ffmpeg
msg_ok "Installed Dependencies"

msg_info "Installing Trailarr"
fetch_and_deploy_gh_release "trailarr" "nandyalu/trailarr"

mkdir /var/lib/trailarr
mkdir /var/log/trailarr
mkdir /opt/trailarr/tmp
mkdir /opt/trailarr/scripts
mkdir /opt/trailarr/bin
msg_ok "Installed Trailarr"

mkdir /opt/trailarr/.local/bin
cp /usr/bin/ffmpeg /opt/trailarr/.local/bin
cp /usr/bin/ffprobe /opt/trailarr/.local/bin

cd /opt/trailarr/backend || exit
PYTHON_VERSION="3.13" setup_uv

$STD adduser --system --group trailarr
chown -R trailarr:trailarr /opt/trailarr
chown -R trailarr:trailarr /var/lib/trailarr
chown -R trailarr:trailarr /var/log/trailarr

msg_info "Configuring Trailarr"
TZ=$(timedatectl | grep "Time zone" | awk '{print $3}' 2>/dev/null || echo "UTC")
YTDLP_VERSION=$(/opt/trailarr/backend/.venv/bin/yt-dlp --version)

cat <<EOF >/var/lib/trailarr/.env
PYTHON_EXECUTABLE=/opt/trailarr/backend/.venv/bin/python
PYTHON_VENV=/opt/trailarr/backend/.venv
PYTHONPATH=/opt/trailarr/backend
APP_VERSION=$APP_VERSION
APP_DATA_DIR=/var/lib/trailarr
APP_MODE="Direct Linux"
APP_PORT=7889
INSTALLATION_MODE=baremetal
MONITOR_INTERVAL=60
PYTHONPATH=/opt/trailarr/backend
WAIT_FOR_MEDIA=true
TZ=$TZ
FFMPEG_PATH=/opt/trailarr/.local/bin/ffmpeg
FFPROBE_PATH=/opt/trailarr/.local/bin/ffprobe
YTDLP_PATH=/opt/trailarr/backend/.venv/bin/yt-dlp
YTDLP_VERSION=$YTDLP_VERSION
EOF

chown trailarr:trailarr /var/lib/trailarr/.env
msg_ok "Configured Trailarr"

cat <<'EOF' >/opt/trailarr/scripts/update_ytdlp_local.sh
#!/bin/bash

# Update yt-dlp in Trailarr virtual environment using pip
set -e

INSTALL_DIR="/opt/trailarr"
VENV_DIR="$INSTALL_DIR/backend/.venv"

echo "Updating yt-dlp via uv sync..."

if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR"
    exit 1
fi

# Check current version
if [ -f "$VENV_DIR/bin/yt-dlp" ]; then
    CURRENT_VERSION=$("$VENV_DIR/bin/yt-dlp" --version 2>/dev/null || echo "unknown")
    echo "Current yt-dlp version: $CURRENT_VERSION"
fi

# Update yt-dlp using pip
"$VENV_DIR/bin/pip" install --upgrade yt-dlp[default,curl-cffi]

if [ $? -eq 0 ]; then
    NEW_VERSION=$("$VENV_DIR/bin/yt-dlp" --version 2>/dev/null || echo "unknown")
    echo "✓ yt-dlp updated to version $NEW_VERSION"
else
    echo " Failed to update yt-dlp"
    exit 1
fi
EOF

chmod +x /opt/trailarr/scripts/update_ytdlp_local.sh

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/trailarr.service
Unit]
Description=Trailarr - Trailer downloader for Radarr and Sonarr
Documentation=https://github.com/nandyalu/trailarr
After=network.target

[Service]
Type=simple
User=trailarr
Group=trailarr
WorkingDirectory=/opt/trailarr
Environment=PYTHONPATH=/opt/trailarr/backend
Environment=PATH=/opt/trailarr/.local/bin:/opt/trailarr/backend/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=/var/lib/trailarr/.env
ExecStartPre=+/opt/trailarr/scripts/baremetal/baremetal_pre_start.sh
ExecStart=/opt/trailarr/scripts/baremetal/baremetal_start.sh
Restart=always
RestartSec=60
TimeoutStopSec=30

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=/var/lib/trailarr /var/log/trailarr /opt/trailarr
#ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now trailarr.service
msg_ok "Created Service"

cp /opt/trailarr/scripts/baremetal/trailarr_cli.sh /usr/local/bin/trailarr
chmod +x /usr/local/bin/trailarr

motd_ssh
customize
cleanup_lxc
