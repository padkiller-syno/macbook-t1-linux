#!/bin/bash
# Essai de veille (S3 « deep ») sur le MacBookPro13,3, interdiction de veille levée le temps de l'essai.
#   sudo bash test-veille.sh 1   noyau actuel, rien de changé
#   sudo bash test-veille.sh 2   + Radeon et son pont PCIe maintenus alimentés (d3cold_allowed=0)
#   sudo bash test-veille.sh 3   + SSD NVMe et son port PCIe maintenus alimentés (d3cold_allowed=0)
#   sudo bash test-veille.sh 4   + aucun périphérique PCI coupé (d3cold_allowed=0 partout)
#   sudo MEMSLEEP=s2idle bash test-veille.sh 1   veille « s2idle » (veille logicielle, sans S3 ni
#        _PTS du firmware) au lieu de « deep » ; consomme plus que S3 mais bien moins qu'allumé
#   T1UNBIND=1 : appletbdrm détaché pendant la veille (test : le « garage » de la Touch Bar est-il en cause ?)
#   WAKE=<s> : réveil automatique par la RTC au bout de <s> secondes (30 par défaut)
#   (modes 2-4 : réglage perdu au redémarrage suivant, rien de permanent)
#   sudo PMTEST=devices bash test-veille.sh 1   veille simulée (/sys/power/pm_test) : tout le chemin
#        jusqu'au niveau donné (freezer, devices, platform, processors, core), 5 s, puis réveil, sans
#        couper l'alimentation. Le niveau qui gèle indique le coupable (pilote, ACPI ou firmware).
# Au réveil : interdiction remise, messages noyau de l'essai dans /var/log/t1-sleep/test-<mode>-<date>.txt.
# Si la machine gèle : le service veille-test-restore remet l'interdiction au démarrage suivant ;
# lire alors journalctl -k -b -1 et /var/lib/systemd/pstore/.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
MODE=${1:-1}
CONF=/etc/systemd/sleep.conf.d/pas-de-veille.conf
SAVE=/root/backup-veille/pas-de-veille.conf
GPU=/sys/bus/pci/devices/0000:01:00.0
BRIDGE=$(readlink -f $GPU/..)
PMTEST=${PMTEST:-none}
MEMSLEEP=${MEMSLEEP:-deep}
OUT=/var/log/t1-sleep/test-$MODE-$MEMSLEEP-pm$PMTEST-$(date +%Y%m%d-%H%M%S).txt
mkdir -p /root/backup-veille /var/log/t1-sleep

# Un blocage au réveil ne laisse aucune trace (journal non écrit, pas d'Oops) : on le transforme en
# panique, que efi_pstore enregistre dans /var/lib/systemd/pstore/ au démarrage suivant (redémarrage auto 30 s).
PANIC_KEYS="kernel.panic_on_oops kernel.softlockup_panic kernel.hung_task_panic kernel.hardlockup_panic kernel.panic"
PANIC_SAVED=$(for k in $PANIC_KEYS; do echo "$k=$(sysctl -n $k 2>/dev/null)"; done)
restore() {
  echo none > /sys/power/pm_test 2>/dev/null || true
  echo deep > /sys/power/mem_sleep 2>/dev/null || true
  for kv in $PANIC_SAVED; do sysctl -q -w "$kv" 2>/dev/null || true; done
  [ -f "$CONF" ] || cp -p "$SAVE" "$CONF"
  systemctl disable --quiet veille-test-restore.service 2>/dev/null || true
  rm -f /etc/systemd/system/veille-test-restore.service; systemctl daemon-reload
}

# filet de sécurité en cas de gel : remet l'interdiction au prochain démarrage
cp -p "$CONF" "$SAVE"
cat > /etc/systemd/system/veille-test-restore.service <<EOF
[Unit]
Description=Remet l'interdiction de veille après un essai qui a gelé
ConditionPathExists=!$CONF
[Service]
Type=oneshot
ExecStart=/bin/cp -p $SAVE $CONF
ExecStart=/bin/systemctl disable veille-test-restore.service
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable --quiet veille-test-restore.service

rm -f "$CONF"; systemctl daemon-reload
for kv in kernel.panic_on_oops=1 kernel.softlockup_panic=1 kernel.hung_task_panic=1 kernel.hardlockup_panic=1 kernel.panic=30; do
  sysctl -q -w "$kv" || true
done
if [ "$MODE" = 2 ]; then
  echo 0 > $GPU/d3cold_allowed; echo 0 > $BRIDGE/d3cold_allowed
fi
# mode 3 : le SSD NVMe (Samsung SM961, 02:00.0) et son port 00:1b.0 restent alimentés
NVME=/sys/bus/pci/devices/0000:02:00.0
if [ "$MODE" = 3 ]; then
  echo 0 > $NVME/d3cold_allowed; echo 0 > "$(readlink -f $NVME/..)/d3cold_allowed"
fi
# mode 4 : plus aucun périphérique PCI coupé (D3cold) : distingue une coupure d'alimentation d'un
# blocage dans les méthodes ACPI d'Apple
if [ "$MODE" = 4 ]; then
  for f in /sys/bus/pci/devices/*/d3cold_allowed; do echo 0 > "$f" 2>/dev/null || true; done
fi
echo "$PMTEST" > /sys/power/pm_test
echo "$MEMSLEEP" > /sys/power/mem_sleep
{
  echo "# essai $MODE, pm_test=$PMTEST — $(date '+%F %T') — $(uname -r)"
  echo "# mem_sleep: $(cat /sys/power/mem_sleep)  radeon d3cold_allowed=$(cat $GPU/d3cold_allowed)  pont $(basename $BRIDGE) d3cold_allowed=$(cat $BRIDGE/d3cold_allowed)"
  echo "# nvme d3cold_allowed=$(cat $NVME/d3cold_allowed)  port $(basename "$(readlink -f $NVME/..)") d3cold_allowed=$(cat "$(readlink -f $NVME/..)/d3cold_allowed")"
  echo "# radeon power_state avant: $(cat $GPU/power_state)  DPM: $(cat $GPU/power_dpm_force_performance_level)"
} > "$OUT"
start=$(date '+%F %T')
sync
echo "== Mise en veille dans 3 s (réveil : touche ou bouton). Mode $MODE."
# T1UNBIND=1 : détacher appletbdrm avant la veille (pas de « garage » de la Touch Bar), le rattacher au réveil
if [ "${T1UNBIND:-0}" = 1 ]; then
  echo 1-3:2.3 > /sys/bus/usb/drivers/appletbdrm/unbind || true
  echo "# appletbdrm détaché avant la veille" >> "$OUT"
fi
sleep 3
# réveil automatique par l'horloge RTC : distingue « endormie mais réveil clavier/capot inopérant »
# de « gelée » (si le journal montre « PM: suspend exit », le noyau a bien repris)
echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +${WAKE:-30} > /sys/class/rtc/rtc0/wakealarm
systemctl suspend -i
# attendre la sortie de veille (ou 3 min)
for _ in $(seq 1 180); do
  journalctl -k --since "$start" -o cat | grep -q "PM: suspend exit" && break
  sleep 1
done
if [ "${T1UNBIND:-0}" = 1 ]; then
  echo 1-3:2.3 > /sys/bus/usb/drivers/appletbdrm/bind || true
  sleep 1; systemctl restart t1-touchbar-hw.service || true
fi
sleep 10   # laisser amdgpu et gnome-shell reprendre
{
  echo "# radeon power_state après: $(cat $GPU/power_state 2>/dev/null)"
  journalctl -k --since "$start" -o short-precise --no-pager
} >> "$OUT"
restore
sync
echo "== Réveil OK, interdiction remise. Journal : $OUT"
grep -i -E "amdgpu.*(fail|error|timeout)|SMU|resume failed|BUG|Oops" "$OUT" | head -15 || echo "(aucune erreur amdgpu visible)"
