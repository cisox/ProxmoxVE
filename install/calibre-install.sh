#!/usr/bin/env bash

# Copyright (c) 2026 cisox
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://calibre-ebook.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y xdg-utils wget xz-utils python3 libegl1 libopengl0 libxcb-cursor0 libnss3 libxdamage1 x11-utils libxrandr2 libxtst6 libx11-6 libxext6 libxrender1 alsa-utils xdg-utils libgtk-3-0
msg_ok "Installed Dependencies"

msg_info "Installing Calibre"
mkdir -p /var/lib/calibre/
chmod 775 /var/lib/calibre/
cd /var/lib/calibre/
$STD curl -fsSL 'https://download.calibre-ebook.com/linux-installer.sh' -o linux-installer.sh
chmod +x linux-installer.sh
$STD ./linux-installer.sh install_dir=/opt
rm -rf linux-installer.sh
mkdir -p /opt/calibre/library
$STD curl -fsSL 'https://github.com/thansen0/sample-epub-minimal/raw/refs/heads/master/minimal.epub' -o minimal.epub
$STD /opt/calibre/calibredb add minimal.epub --library-path /opt/calibre/library
msg_ok "Installed Calibre"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/calibre.service
[Unit]
Description=Calibre
After=syslog.target network.target
[Service]
UMask=0002
Type=simple
ExecStart=/opt/calibre/calibre-server --port=8080 --enable-local-write /opt/calibre/library
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl -q daemon-reload
systemctl enable --now -q calibre
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
