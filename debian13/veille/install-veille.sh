#!/bin/bash
# Active la veille S3 au quotidien sur le MacBookPro13,3 (nécessite le module amdgpu patché, voir README).
#   sudo bash install-veille.sh            installer
#   sudo bash install-veille.sh annuler    tout remettre comme avant (veille interdite, capot = verrouillage)
#
# - veille S3 (« deep ») autorisée, hibernation toujours interdite (jamais testée) ;
# - aucun périphérique PCI en D3cold (règle udev) : sans ça la machine gèle en s'endormant ;
# - Wi-Fi (brcmfmac) rechargé au réveil : sinon il ne s'associe plus ;
# - garde-fou : si le module amdgpu patché n'est pas chargé (autre noyau…), la veille est bloquée ;
# - capot fermé : veille sur batterie, verrouillage sur secteur, rien avec un écran externe.
# Connu : après une veille, Touch Bar noire (tactile OK) et Thunderbolt/dock perdus jusqu'au redémarrage.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
SAVE=/root/backup-veille/installation
SLEEP_BAN=/etc/systemd/sleep.conf.d/pas-de-veille.conf
SLEEP_OK=/etc/systemd/sleep.conf.d/veille-s3.conf
LID=/etc/systemd/logind.conf.d/10-capot-verrouille.conf
RULE=/etc/udev/rules.d/90-macbook-pas-de-d3cold.rules
HOOK=/usr/lib/systemd/system-sleep/veille-macbook
GARDE=/etc/systemd/system/veille-garde.service

if [ "${1:-}" = annuler ]; then
  systemctl disable --now veille-garde.service 2>/dev/null || true
  rm -f "$SLEEP_OK" "$RULE" "$HOOK" "$GARDE"
  cp -p "$SAVE/pas-de-veille.conf" "$SLEEP_BAN"
  cp -p "$SAVE/10-capot-verrouille.conf" "$LID"
  systemctl daemon-reload; udevadm control --reload
  systemctl reload systemd-logind
  echo "== Annulé : veille interdite, capot = verrouillage. D3cold revient au prochain démarrage."
  exit 0
fi

[ -e /sys/module/amdgpu/parameters/t1_smc_restart ] || {
  echo "Le module amdgpu patché n'est pas chargé : la Radeon ne survivrait pas à la veille. Abandon."; exit 1; }

mkdir -p "$SAVE"
[ -f "$SAVE/pas-de-veille.conf" ] || cp -p "$SLEEP_BAN" "$SAVE/"
[ -f "$SAVE/10-capot-verrouille.conf" ] || cp -p "$LID" "$SAVE/"

rm -f "$SLEEP_BAN"
cat > "$SLEEP_OK" <<'EOF'
# MacBookPro13,3 : veille S3 seulement (amdgpu patché, voir ~/git/macbook-t1-linux/debian13/veille/)
[Sleep]
AllowSuspend=yes
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
MemorySleepMode=deep
EOF

cat > "$RULE" <<'EOF'
# MacBookPro13,3 : un périphérique PCI en D3cold fait geler la mise en veille S3 (essais du 16/11/2026)
ACTION=="add", SUBSYSTEM=="pci", ATTR{d3cold_allowed}="0"
EOF
udevadm control --reload
for f in /sys/bus/pci/devices/*/d3cold_allowed; do echo 0 > "$f" 2>/dev/null || true; done

cat > "$HOOK" <<'EOF'
#!/bin/sh
# MacBookPro13,3 : le Wi-Fi BCM43602 ne s'associe plus après une veille S3 → rechargement de brcmfmac.
case "$1" in
  post) modprobe -r brcmfmac_wcc 2>/dev/null; modprobe -r brcmfmac && sleep 1 && modprobe brcmfmac ;;
esac
EOF
chmod 755 "$HOOK"

cat > "$GARDE" <<'EOF'
[Unit]
Description=Bloque la veille si le module amdgpu patché (MacBookPro13,3) n'est pas chargé
ConditionPathExists=!/sys/module/amdgpu/parameters/t1_smc_restart

[Service]
ExecStart=/usr/bin/systemd-inhibit --what=sleep --who=veille-garde --mode=block --why="amdgpu non patché : la Radeon ne survivrait pas à la veille" /bin/sleep infinity

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable veille-garde.service

cat > "$LID" <<'EOF'
# MacBookPro13,3 : capot fermé = veille sur batterie, verrouillage sur secteur, rien avec un écran externe
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=ignore
EOF
systemctl reload systemd-logind

echo "== Veille installée. Sauvegardes : $SAVE"
echo "   CanSuspend : $(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspend 2>/dev/null)"
echo "   D3cold encore permis : $(grep -l 1 /sys/bus/pci/devices/*/d3cold_allowed 2>/dev/null | wc -l) périphérique(s)"
