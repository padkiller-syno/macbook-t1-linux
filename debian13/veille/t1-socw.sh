#!/bin/bash
# Prévenir la T1 (via le SMC) que l'hôte s'endort ou se réveille, comme le fait macOS.
# macOS 13.7.8 (MacBookPro14,3, pilote AppleEmbeddedOSSupportHost, rattaché à ACPI APP7777 = ASOC) appelle :
#   endormissement (kIOMessageSystemWillSleep 0xe0000280)  : ASOC.SOCW(0) → MBOX(1)
#   réveil         (kIOMessageSystemHasPoweredOn 0xe0000320) : ASOC.SOCW(1) → MBOX(6) puis MBOX(2)
# MBOX (DSDT) écrit la commande dans l'EC (INDX/DATA/CMDS) puis fait une poignée de main GPIO avec la T1 ;
# elle ne fait rien si MBXC = 0. Linux n'appelle jamais SOCW : aucun pilote ne se rattache à APP7777.
#   sudo bash t1-socw.sh etat     valeur de MBXC
#   sudo bash t1-socw.sh 1        réveil (SOCW 1)
#   sudo bash t1-socw.sh 0        endormissement (SOCW 0)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ASOC='\_SB.PCI0.XHC1.RHUB.ASOC'
modprobe acpi_call
acpi() { printf '%s\n' "$1" > /proc/acpi/call; tr -d '\0' < /proc/acpi/call; echo; }
echo "MBXC = $(acpi '\MBXC')"
case "${1:-etat}" in
  etat) ;;
  0|1)
    echo "$(date '+%T.%N') SOCW($1)…"
    echo "SOCW($1) = $(acpi "$ASOC.SOCW $1")   (0 = OK, 1/2 = délai dépassé, 3 = échec MBOX(6))"
    echo "$(date '+%T.%N') fin" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
