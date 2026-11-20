#!/bin/sh
# MacBook Pro T2 : correctifs du 20/11 (soir), à lancer en root (sudo sh kubuntu-t2/systeme/correctifs-20261120.sh).
#   1. profil-energie-sync : plus d'After=power-profiles-daemon (cycle avec multi-user.target → job supprimé au boot)
#   2. t2-ncm-reveil : rend la porteuse à t2_ncm au démarrage (Touch ID)
#   3. nettoyages : /swapfile retiré (zram suffit), règle 30-amdgpu-pm limitée aux cartes qui ont l'attribut,
#      accès i2c des cartes graphiques à la session (luminosité DDC des écrans externes dans KDE)
set -eu
cd "$(dirname "$0")/.."
B=/root/backup_systemd/$(date +%Y%m%d%H%M%S)-ameliorations-t2
mkdir -p "$B"
cp -a /etc/systemd/system/profil-energie-sync.service /etc/fstab /etc/udev/rules.d/30-amdgpu-pm.rules "$B"/
echo "sauvegardes : $B"

# 1
install -m 0644 energie/profil-energie-sync.service /etc/systemd/system/profil-energie-sync.service

# 2
install -m 0755 touchid/t2-ncm-reveil /usr/local/sbin/t2-ncm-reveil
install -m 0644 touchid/t2-ncm-reveil.service /etc/systemd/system/t2-ncm-reveil.service

# 3a swapfile
if grep -q '^/swapfile' /etc/fstab; then
  swapoff /swapfile 2>/dev/null || true
  sed -i 's|^/swapfile|# retiré le 20/11 (zram) : /swapfile|' /etc/fstab
  rm -f /swapfile
fi
# 3b règle amdgpu : card0 = simple-framebuffer (parent amdgpu, sans l'attribut) → erreur au boot
cat > /etc/udev/rules.d/30-amdgpu-pm.rules <<'EOF'
KERNEL=="card[012]", SUBSYSTEM=="drm", DRIVERS=="amdgpu", TEST=="device/power_dpm_force_performance_level", ATTR{device/power_dpm_force_performance_level}="low"
EOF
# 3c i2c des cartes graphiques (classe PCI 0x030000) pour l'utilisateur de la session, pas le SMBus
cat > /etc/udev/rules.d/60-i2c-ecrans.rules <<'EOF'
SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", ATTRS{class}=="0x030000", TAG+="uaccess"
EOF

systemctl daemon-reload
systemctl enable t2-ncm-reveil.service
udevadm control --reload
udevadm trigger --subsystem-match=i2c-dev
systemctl start profil-energie-sync.service
systemctl start t2-ncm-reveil.service || true

echo "--- état"
systemctl is-active profil-energie-sync t2-ncm-reveil kait2en-t2-touchid || true
ip -br link show t2_ncm; ip -6 -br addr show t2_ncm
swapon --show
ls -l /dev/i2c-9
