#!/bin/bash
# Thunderbolt (2 × Alpine Ridge) du MacBookPro13,3 : appelle les méthodes ACPI d'Apple que macOS utilise.
# Lu dans la SSDT « TbtPEG12 » (~/git/t1/acpi/ssdt7.dsl) : avec _OSI("Darwin") (réponse par défaut de Linux sur
# Mac), _PS3 des ponts DSB0/DSB2 coupe l'alimentation (PCDA → GNHI/GXCI = 0 → UGIO, GPIO 0x01070004/7) dès que
# RTBT/RUSB valent 0, et _PS0 (PCEU) ne la remet PAS. C'est PCED (« power on ») qui rallume : GPCI/GNHI/GXCI = 1,
# UGIO, puis réentraînement du lien PCIe. macOS appelle PCED ; Linux jamais → contrôleurs « inaccessibles ».
#
#   sudo bash tb-acpi.sh rallumer   PCED sur UPSB, NHI0 et le xHCI des deux contrôleurs, puis remove/rescan PCI
#   sudo bash tb-acpi.sh reveil     après une veille S3 : remet l'état ACPI à « éteint » (_PS3) puis enchaîne rallumer
#   sudo bash tb-acpi.sh retirer    avant la veille : retire les 2 contrôleurs du bus PCI (rallumer les ramène)
#   sudo bash tb-acpi.sh garder     RTPC(1) sur NHI0 et xHCI : RTBT/RUSB = 1, _PS3 ne coupe plus (avant la veille)
#   sudo bash tb-acpi.sh etat       lit les variables ACPI utiles (via les méthodes POFF)
# Nécessite le module acpi_call (DKMS acpi-call, déjà installé).
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
modprobe acpi_call || { echo "acpi_call indisponible"; exit 1; }
OUT=/var/log/t1-sleep/tb-acpi-${1:-}-$(date +%Y%m%d-%H%M%S).txt
start=$(date '+%F %T')

call() {  # call <méthode ACPI> [arguments]
  echo "$*" > /proc/acpi/call
  printf '%-48s -> %s\n' "$*" "$(tr -d '\0' < /proc/acpi/call)" | tee -a "$OUT"
}

declare -A XHC=([PEG1]=XHC2 [PEG2]=XHC3)
case "${1:-}" in
rallumer)
  for p in PEG1 PEG2; do
    call "\\_SB.PCI0.$p.UPSB.PCED"
    call "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.PCED"
    call "\\_SB.PCI0.$p.UPSB.DSB2.${XHC[$p]}.PCED"
  done
  sleep 2
  # si les contrôleurs sont encore listés (réveil sans « retirer »), les retirer pour repartir à neuf
  for b in 0000:04:00.0 0000:7a:00.0; do
    [ -e /sys/bus/pci/devices/$b ] && echo 1 > /sys/bus/pci/devices/$b/remove
  done
  sleep 1
  # redétection limitée aux deux ports racine Thunderbolt (comme un branchement à chaud)
  for r in 0000:00:01.1 0000:00:01.2; do
    echo on > /sys/bus/pci/devices/$r/power/control   # port racine réveillé, sinon le lien reste coupé
    echo 1 > /sys/bus/pci/devices/$r/rescan
  done
  sleep 5
  echo "contrôleurs Thunderbolt vus : $(lspci | grep -c Thunderbolt) (14 attendus)" | tee -a "$OUT" ;;
reveil)
  # après une veille S3 : le matériel a perdu le courant mais les variables ACPI (GPCI/GNHI/GXCI, en RAM) disent
  # « allumé », donc PCED → UGIO ne fait rien. On remet d'abord l'état firmware à « éteint » par ses propres
  # méthodes (RTPC 0 puis _PS3 des ponts), puis RTPC 1 et PCED → UGIO voit éteint → allumé et réentraîne le lien.
  for p in PEG1 PEG2; do
    call "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.RTPC 0"
    call "\\_SB.PCI0.$p.UPSB.DSB2.${XHC[$p]}.RTPC 0"
    call "\\_SB.PCI0.$p.UPSB.DSB0._PS3"
    call "\\_SB.PCI0.$p.UPSB.DSB2._PS3"
    call "\\_SB.PCI0.$p._PS3"
    call "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.RTPC 1"
    call "\\_SB.PCI0.$p.UPSB.DSB2.${XHC[$p]}.RTPC 1"
    call "\\_SB.PCI0.$p._PS0"
  done
  exec bash "$0" rallumer ;;
retirer)
  # avant la veille : sortir les deux contrôleurs du bus PCI, le noyau n'y touchera plus pendant la veille
  for b in 0000:04:00.0 0000:7a:00.0; do
    [ -e /sys/bus/pci/devices/$b ] && echo 1 > /sys/bus/pci/devices/$b/remove
  done
  sleep 1
  echo "contrôleurs Thunderbolt vus : $(lspci | grep -c Thunderbolt)" | tee -a "$OUT" ;;
garder)
  for p in PEG1 PEG2; do
    call "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.RTPC 1"
    call "\\_SB.PCI0.$p.UPSB.DSB2.${XHC[$p]}.RTPC 1"
  done ;;
etat)
  for p in PEG1 PEG2; do
    call "\\_SB.PCI0.$p.POFF"
    call "\\_SB.PCI0.$p.UPSB.DSB0.POFF"
  done ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
journalctl -k --since "$start" -o short-precise --no-pager >> "$OUT"
echo "== Journal : $OUT"
