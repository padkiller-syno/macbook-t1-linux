#!/bin/bash
# À lancer juste après un réveil si la Freebox 5 GHz ne se connecte pas (clé USB débranchée, pour que SFR_EDA8 et
# son annonce GB ne faussent rien). Photographie l'état (wifi-photo.sh), résume le canal 116 et les événements
# réglementaires depuis le réveil, essaie le correctif « iw reg set 00 » puis « iw reg set FR », puis la connexion.
#   bash test-wifi-apres-veille.sh   (sudo demandé)
set -u
ICI=$(dirname "$(readlink -f "$0")")
CON=Freebox-A10C64; IF=wlp3s0; IW=/usr/sbin/iw
J=$HOME/git/t1/wifi/apres-veille-$(date +%H%M%S).txt
etat() { echo "   pays : $($IW reg get | grep -m1 country)"; $IW phy "$(basename "$(readlink -f /sys/class/net/$IF/phy80211)")" channels | grep -A3 "\[116\]" | sed 's/^/   /'; }
essai() { nmcli con up "$CON" ifname "$IF" > /dev/null 2>&1 && echo "   → Freebox : OK" || echo "   → Freebox : ÉCHEC"; }
sudo -v || exit 1
{
sudo bash "$ICI/wifi-photo.sh" apres-veille
R=$(journalctl -b --no-pager -o short-iso | grep "PM: suspend exit" | tail -1 | cut -d' ' -f1)
[ -n "$R" ] || { echo "== aucune veille depuis le démarrage : rien à analyser"; R=$(journalctl -b --no-pager -o short-iso | head -1 | cut -d' ' -f1); }
echo "== depuis le réveil ($R) :"
journalctl --since "$R" --no-pager -o short | grep -E "wpa_supplicant.*$IF.*(Trying|REJECT|CONNECTED|REGDOM|timed out)" | sed -E 's/^.*wpa_supplicant\[[0-9]+\]: /   /' | tail -15
echo "== état actuel"; etat
echo "== connexion sans rien faire"; S=$(essai); echo "$S"
if [[ $S == *ÉCHEC* ]]; then
  nmcli dev disconnect "$IF" > /dev/null 2>&1; sleep 2
  echo "== correctif : iw reg set 00 puis FR"; sudo $IW reg set 00; sleep 1; sudo $IW reg set FR; sleep 3; etat
  echo "== connexion après correctif"; essai
fi
} 2>&1 | tee "$J"
echo "== journal : $J"
