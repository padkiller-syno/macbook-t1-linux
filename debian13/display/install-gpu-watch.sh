#!/bin/bash
# Installe gpu-watch (mesures Radeon/CPU chaque seconde + capture automatique d'un plantage amdgpu).
# Usage : sudo bash install-gpu-watch.sh            (installer)
#         sudo bash install-gpu-watch.sh annuler    (retirer ; garde /var/log/gpu-watch)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ICI=$(dirname "$(readlink -f "$0")")
if [ "${1:-}" = annuler ]; then
  systemctl disable --now gpu-watch.service 2>/dev/null || true
  rm -f /usr/local/sbin/gpu-watch /etc/systemd/system/gpu-watch.service
  systemctl daemon-reload; echo "== Retiré (journaux gardés dans /var/log/gpu-watch)"; exit 0
fi
install -m 755 "$ICI/gpu-watch" /usr/local/sbin/gpu-watch
cat > /etc/systemd/system/gpu-watch.service <<'EOF'
[Unit]
Description=Surveillance Radeon/CPU et capture des plantages amdgpu (/var/log/gpu-watch)
After=systemd-journald.service

[Service]
ExecStart=/usr/local/sbin/gpu-watch
Restart=always
RestartSec=5
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now gpu-watch.service
sleep 3
systemctl is-active gpu-watch.service
ls -l /var/log/gpu-watch/ | tail -3
tail -3 "$(ls -t /var/log/gpu-watch/*.csv | head -1)"
