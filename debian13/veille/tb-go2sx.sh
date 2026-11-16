#!/bin/bash
# Thunderbolt (2 × Alpine Ridge JHL6540) du MacBookPro13,3 : la séquence de veille de macOS, reconstituée en
# désassemblant AppleThunderboltNHIType3 (macOS 13.7.8, MacBookPro14,3, même famille de contrôleurs).
#
# macOS, à l'endormissement (Type3::lateSleep) :
#   1. signalGo2Sx      : config PCI du NHI, VSEC (capacité étendue 0x0B, ici à 0x500) + 0x4c ← 5
#   2. super::lateSleep
#   3. ACPI NHI0.SXFP(0) : coupe les broches d'alimentation (PEG1 : 0x01070007 puis 0x01070004 ; PEG2 : …08 puis …05)
#   4. waitForOk2Go2Sx  : attend l'octet bas de VSEC + 0x48 == 5 (ou 0xffffffff = contrôleur déjà éteint), puis + 0x4c ← 0
#   5. ACPI NHI0.XRST(1) : pose seulement un drapeau (XRTE), lu nulle part → ignoré ici
# au réveil (Type3::prePCIWake), avant que le bus PCI ne soit réveillé :
#   ACPI NHI0.XRST(0), puis NHI0.TRPE(1, 0) : si la broche est réellement coupée (GGOV/GGDV = 0), la relâche,
#   attend l'entraînement du lien (10 s max, 4 essais) et le remet en Gen3.
# Linux ne fait rien de tout ça (seul l'Ice Lake a son équivalent, ICL_LC_GO2SX dans drivers/thunderbolt/nhi_ops.c).
#
#   sudo bash tb-go2sx.sh etat      lecture seule : registres VSEC des NHI + état réel des broches d'alimentation
#   sudo bash tb-go2sx.sh go2sx     échange Go2Sx complet à chaud (5, attente de l'écho, 0) : PAS de réponse le 16/11,
#                                   le firmware ne répond sans doute qu'une fois le NHI en D3 (macOS attend après)
#   sudo bash tb-go2sx.sh signal    écrit seulement 5 dans VSEC+0x4c, juste avant la veille (comme macOS)
#   sudo bash tb-go2sx.sh couper    avant la veille : go2sx, retrait PCI des contrôleurs, SXFP(0)
#   sudo bash tb-go2sx.sh allumer   après la veille (ou après couper) : TRPE(1,0), puis redétection PCI
#   sudo bash tb-go2sx.sh cycle     essai à chaud sans veille : couper, 3 s, allumer
#   sudo bash tb-go2sx.sh relancer  après une veille ratée : retrait PCI, TRPE(0) (broche forcée à 0), puis allumer
#                                   16/11 : broches OK (0 puis 1) mais lien des ports racine 00:01.1/.2 resté à x0
#   sudo bash tb-go2sx.sh lien      réentraîne le lien des ports racine : Retrain Link, puis Secondary Bus Reset,
#                                   puis Link Disable ; arrêt dès que le lien revient, puis redétection PCI
#   Ports racine sains : LnkSta=1043 (x4, 8 GT/s), 0x248=0 ; après S3 : LnkSta=1001 (x0)
#   LTSSM du port (0xC74, bits 0-3, champ LTSM d'Apple) : 3 = L0 ; après S3 : 0/1 = détection, l'Alpine Ridge ne
#   présente même plus sa terminaison → son firmware est figé, TRPE (broche « force power ») ne le relance pas.
#   sudo bash tb-go2sx.sh go2sx-d3  séquence macOS complète à chaud : pilote détaché, 5, NHI en D3hot, attente écho
#   sudo bash tb-go2sx.sh rattacher remet le NHI en D0 et rattache le pilote thunderbolt (après go2sx-d3 sans veille)
# Nécessite acpi_call. Journal : /var/log/t1-sleep/tb-go2sx-<mode>-<date>.txt
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
modprobe acpi_call || { echo "acpi_call indisponible"; exit 1; }
MODE=${1:-}
OUT=/var/log/t1-sleep/tb-go2sx-$MODE-$(date +%Y%m%d-%H%M%S).txt
mkdir -p /var/log/t1-sleep
start=$(date '+%F %T')
log() { echo "$*" | tee -a "$OUT"; }

NHI=(0000:06:00.0 0000:7c:00.0)      # NHI des deux contrôleurs
UPSB=(0000:04:00.0 0000:7a:00.0)     # ponts amont (retirés avant la veille)
ROOT=(0000:00:01.1 0000:00:01.2)     # ports racine du CPU
PEG=(PEG1 PEG2)
declare -A GPIO=([PEG1]="0x01070004 0x01070007" [PEG2]="0x01070005 0x01070008")
VSEC=0x500                           # lu le 16/11 : « Capabilities: [500 v1] Vendor Specific Information: ID=1234 »

acpi() {  # acpi <méthode> [args]
  echo "$*" > /proc/acpi/call
  local r; r=$(tr -d '\0' < /proc/acpi/call)
  printf '  %-44s -> %s\n' "$*" "$r" | tee -a "$OUT" >&2
  echo "$r"
}
present() { [ -e /sys/bus/pci/devices/$1/config ]; }
rd() { setpci -s "${1#0000:}" $(printf '0x%x' $(( VSEC + $2 ))).l; }
wr() { setpci -s "${1#0000:}" $(printf '0x%x' $(( VSEC + $2 ))).l=$3; }

etat() {
  for i in 0 1; do
    local n=${NHI[$i]} p=${PEG[$i]}
    if present "$n"; then
      log "${p} NHI $n : VSEC+48=$(rd $n 0x48) VSEC+4c=$(rd $n 0x4c) id=$(setpci -s ${n#0000:} $(printf '0x%x' $VSEC).l)"
    else
      log "${p} NHI $n : absent du bus PCI"
    fi
    for g in ${GPIO[$p]}; do
      log "${p} broche $g : GGOV=$(acpi '\_SB.GGOV' $g 2>/dev/null) GGDV=$(acpi '\_SB.GGDV' $g 2>/dev/null)"
    done
    log "${p} port racine ${ROOT[$i]} : $(lspci -vv -s ${ROOT[$i]#0000:} | grep -E 'LnkSta:' | xargs)"
  done
}

largeur() { echo $(( (0x$(setpci -s ${1#0000:} 0xb2.w) >> 4) & 0x3f )); }  # LnkSta : largeur négociée

lien() {  # réentraîne le lien des ports racine, du plus doux au plus fort, arrêt dès que le lien est revenu
  for r in "${ROOT[@]}"; do
    local s=${r#0000:}
    log "$s avant : LnkSta=$(setpci -s $s 0xb2.w) r248=$(setpci -s $s 0x248.l) largeur=x$(largeur $r)"
    [ "$(largeur $r)" -gt 0 ] && continue
    setpci -s $s 0xb0.w=0020:0020; sleep 1                                           # 1. Retrain Link
    log "$s après retrain : x$(largeur $r)"; [ "$(largeur $r)" -gt 0 ] && continue
    setpci -s $s 0x3e.w=0040:0040; sleep 0.1; setpci -s $s 0x3e.w=0000:0040; sleep 1   # 2. Secondary Bus Reset
    log "$s après reset secondaire : x$(largeur $r)"; [ "$(largeur $r)" -gt 0 ] && continue
    setpci -s $s 0xb0.w=0010:0010; sleep 0.5; setpci -s $s 0xb0.w=0000:0010; sleep 1   # 3. Link Disable puis réactivation
    log "$s après link disable : x$(largeur $r) LnkSta=$(setpci -s $s 0xb2.w)"
  done
  for b in "${UPSB[@]}"; do present "$b" && echo 1 > /sys/bus/pci/devices/$b/remove; done
  for r in "${ROOT[@]}"; do echo 1 > /sys/bus/pci/devices/$r/rescan; done
  sleep 5
  log "contrôleurs Thunderbolt vus : $(lspci | grep -c Thunderbolt) (14 attendus)"
}

relancer() {  # remise à zéro électrique : TRPE(0) force la broche à 0, puis allumer → TRPE(1,0) la relâche
  for b in "${UPSB[@]}"; do present "$b" && echo 1 > /sys/bus/pci/devices/$b/remove; done
  sleep 1
  for p in "${PEG[@]}"; do acpi "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.TRPE" 0 0 >/dev/null; done
  sleep 1
  etat
  allumer
}

go2sx() {
  for n in "${NHI[@]}"; do
    present "$n" || { log "$n absent : pas d'échange Go2Sx"; continue; }
    wr "$n" 0x4c 5
    local t=0 v
    while :; do
      v=$(rd "$n" 0x48)
      [ "$v" = ffffffff ] && break
      [ "$(( 0x$v & 0xff ))" = 5 ] && break
      t=$((t + 1)); [ $t -ge 300 ] && break      # 300 × 10 ms = 3 s
      sleep 0.01
    done
    wr "$n" 0x4c 0
    log "$n Go2Sx : VSEC+48=$v après $t × 10 ms $([ $t -ge 300 ] && echo '(PAS de réponse du firmware)')"
  done
}

signal() {  # comme macOS : 5 écrit avant l'endormissement, l'attente ne vient qu'après la mise en D3 du NHI
  for n in "${NHI[@]}"; do
    present "$n" || continue
    wr "$n" 0x4c 5
    log "$n signalGo2Sx : VSEC+4c relu=$(rd $n 0x4c) VSEC+48=$(rd $n 0x48)"
  done
}

go2sx_d3() {  # séquence macOS complète : pilote détaché, 5 → VSEC+4c, NHI en D3hot, attente de l'écho, puis 0
  for n in "${NHI[@]}"; do
    present "$n" || { log "$n absent"; continue; }
    local s=${n#0000:}
    [ -e /sys/bus/pci/devices/$n/driver ] && echo "$n" > /sys/bus/pci/devices/$n/driver/unbind
    wr "$n" 0x4c 5
    setpci -s $s CAP_PM+4.w=0003:0003
    log "$n NHI en D3hot : PMCSR=$(setpci -s $s CAP_PM+4.w) VSEC+48=$(rd $n 0x48)"
    local t=0 v
    while :; do
      v=$(rd "$n" 0x48)
      [ "$v" = ffffffff ] && break
      [ "$(( 0x$v & 0xff ))" = 5 ] && break
      t=$((t + 1)); [ $t -ge 500 ] && break      # 500 × 10 ms = 5 s
      sleep 0.01
    done
    wr "$n" 0x4c 0
    log "$n Go2Sx en D3 : VSEC+48=$v après $t × 10 ms $([ $t -ge 500 ] && echo '(PAS de réponse)' || echo '→ ACQUITTÉ')"
  done
}

rattacher() {  # après go2sx_d3 sans veille : NHI en D0 et pilote thunderbolt rattaché
  for n in "${NHI[@]}"; do
    present "$n" || continue
    setpci -s ${n#0000:} CAP_PM+4.w=0000:0003; sleep 0.1
    [ -e /sys/bus/pci/devices/$n/driver ] || echo "$n" > /sys/bus/pci/drivers/thunderbolt/bind
    log "$n : PMCSR=$(setpci -s ${n#0000:} CAP_PM+4.w) pilote=$(basename "$(readlink /sys/bus/pci/devices/$n/driver 2>/dev/null)")"
  done
}

couper() {
  go2sx
  for b in "${UPSB[@]}"; do present "$b" && echo 1 > /sys/bus/pci/devices/$b/remove; done
  sleep 1
  for p in "${PEG[@]}"; do acpi "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.SXFP" 0 >/dev/null; done
}

allumer() {
  for p in "${PEG[@]}"; do
    acpi "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.XRST" 0 >/dev/null
    acpi "\\_SB.PCI0.$p.UPSB.DSB0.NHI0.TRPE" 1 0 >/dev/null
  done
  sleep 1
  for b in "${UPSB[@]}"; do present "$b" && echo 1 > /sys/bus/pci/devices/$b/remove; done
  for r in "${ROOT[@]}"; do
    echo on > /sys/bus/pci/devices/$r/power/control
    echo 1 > /sys/bus/pci/devices/$r/rescan
  done
  sleep 5
  log "contrôleurs Thunderbolt vus : $(lspci | grep -c Thunderbolt) (14 attendus)"
}

case "$MODE" in
  etat) etat ;;
  go2sx) etat; go2sx; etat ;;
  signal) signal ;;
  relancer) etat; relancer; etat ;;
  lien) lien ;;
  go2sx-d3) go2sx_d3 ;;
  rattacher) rattacher ;;
  couper) etat; couper; etat ;;
  allumer) etat; allumer; etat ;;
  cycle) etat; couper; log "== coupé"; etat; sleep 3; allumer; etat ;;
  *) sed -n '2,24p' "$0"; exit 1 ;;
esac
journalctl -k --since "$start" -o short-precise --no-pager >> "$OUT"
echo "== Journal : $OUT"
