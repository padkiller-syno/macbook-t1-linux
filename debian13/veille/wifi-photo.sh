#!/bin/bash
# Photographie de l'état de la carte Wi-Fi BCM43602 (03:00.0) et de son port PCIe (00:1c.0), pour comparer
# l'état « bon » (juste après démarrage, 5 GHz OK) et l'état « cassé » (après une déconnexion : 5 GHz refusé).
#   sudo bash wifi-photo.sh <etiquette>     → ~/git/t1/wifi/<etiquette>-<heure>/
#   comparer : diff -r ~/git/t1/wifi/bon-* ~/git/t1/wifi/casse-*
set -u
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
U=${SUDO_USER:-benoit}
O=/home/$U/git/t1/wifi/${1:-photo}-$(date +%H%M%S)
mkdir -p "$O"
for d in 03:00.0 00:1c.0; do
  lspci -vvv -s $d > "$O/lspci-$d.txt" 2>&1
  lspci -xxxx -s $d > "$O/config-$d.hex" 2>&1
done
P=/sys/bus/pci/devices/0000:03:00.0
for f in power_state power/runtime_status power/control d3cold_allowed link/l1_aspm link/l1_1_aspm \
         link/l1_2_aspm link/l0s_aspm link/clkpm current_link_speed current_link_width; do
  [ -r "$P/$f" ] && echo "$f=$(cat $P/$f)"
done > "$O/sysfs.txt" 2>&1
cat /sys/module/pcie_aspm/parameters/policy > "$O/aspm-policy.txt" 2>&1
IW=/usr/sbin/iw; PHY=$(ls /sys/class/ieee80211/ | head -1)
$IW reg get > "$O/reg.txt" 2>&1
$IW phy "$PHY" channels > "$O/channels.txt" 2>&1
$IW dev wlp3s0 link > "$O/link.txt" 2>&1
$IW dev wlp3s0 station dump > "$O/station.txt" 2>&1
D=/sys/kernel/debug/ieee80211/$PHY/brcmfmac
if [ -d "$D" ]; then for f in "$D"/*; do cat "$f" > "$O/debug-$(basename "$f").txt" 2>&1; done; fi
journalctl -k -b --no-pager | grep -iE "brcmf|03:00.0|00:1c.0" > "$O/noyau.txt"
chown -R "$U": "$(dirname "$O")"
echo "== $O : $(ls "$O" | wc -l) fichiers"; cat "$O/link.txt" | head -3
