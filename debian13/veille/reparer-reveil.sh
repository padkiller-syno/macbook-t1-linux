#!/bin/bash
# Essais de remise en route après une veille S3 (MacBookPro13,3), une étape à la fois :
#   sudo bash reparer-reveil.sh wifi       recharge brcmfmac (BCM43602 : n'arrive plus à s'associer au réveil)
#   sudo bash reparer-reveil.sh tb         retire puis redécouvre les deux contrôleurs Thunderbolt (D3cold « inaccessibles »)
#   sudo bash reparer-reveil.sh touchbar   coupe puis rallume le port USB interne de la T1 (écran Touch Bar noir)
# Journal : /var/log/t1-sleep/reparer-<étape>-<date>.txt
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ETAPE=${1:-}
OUT=/var/log/t1-sleep/reparer-$ETAPE-$(date +%Y%m%d-%H%M%S).txt
start=$(date '+%F %T')
case "$ETAPE" in
wifi)
  modprobe -r brcmfmac_wcc 2>/dev/null; modprobe -r brcmfmac; sleep 1; modprobe brcmfmac
  sleep 10; nmcli -t -f DEVICE,STATE dev | grep wlp ;;
tb)
  # ponts amont des deux contrôleurs Alpine Ridge (sous les ports racine 00:01.1 et 00:01.2)
  for b in 0000:04:00.0 0000:7a:00.0; do
    [ -e /sys/bus/pci/devices/$b ] && echo 1 > /sys/bus/pci/devices/$b/remove
  done
  sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 5
  for d in 0000:06:00.0 0000:7c:00.0; do
    echo "$d : $(cat /sys/bus/pci/devices/$d/power_state 2>/dev/null || echo absent)"
  done ;;
touchbar)
  P=/sys/bus/usb/devices/usb1/1-0:1.0/usb1-port3
  echo 1 > $P/disable; sleep 3; echo 0 > $P/disable
  sleep 6; systemctl restart t1-touchbar-hw.service
  lsusb | grep -i ibridge ;;
*) sed -n '2,6p' "$0"; exit 1 ;;
esac
sleep 2
journalctl -k --since "$start" -o short-precise --no-pager > "$OUT"
echo "== Fini. Journal : $OUT"
