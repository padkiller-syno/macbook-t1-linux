#!/bin/bash
# Wi-Fi BCM43602, Freebox 5 GHz (canal 116, DFS) refusée : ASSOC-REJECT status 16, bssid 0.
# 16/11 : cause réglementaire (canal 116 en « No IR »). Une simple déconnexion ne casse rien (test 20:25) ;
# l'échec de 19:24 suivait une VEILLE, donc le rechargement de brcmfmac par le hook. Les tests de rechargement
# de 19:57-20:02 étaient faussés (clé USB sur SFR_EDA8, qui annonce GB).
# Ce test, sans SFR : rechargement de brcmfmac comme le hook, état du canal 116, connexion ; en cas d'échec,
# correctif « iw reg set 00 » puis « iw reg set FR » et nouvel essai. Clé USB reconnectée à SFR seulement à la fin
# en cas d'échec (session Claude coupée pendant le test).
#   bash test-wifi-reset.sh   (sudo demandé au début)
set -u
CON=Freebox-A10C64; IF=wlp3s0; USB=$(ls /sys/class/net | grep '^wlx' | head -1); SECOURS=SFR_EDA8
IW=/usr/sbin/iw
J=$HOME/git/t1/wifi/test-rechargement-$(date +%H%M%S).txt
etat() { echo "   pays : $($IW reg get | grep -m1 country)"; $IW phy "$(basename "$(readlink -f /sys/class/net/$IF/phy80211)")" channels | grep -A3 "\[116\]" | sed 's/^/   /'; }
essai() { nmcli con up "$CON" ifname "$IF" > /dev/null 2>&1 && echo "   → Freebox : OK" || echo "   → Freebox : ÉCHEC"
  journalctl --since -30s --no-pager -o short | grep -E "wpa_supplicant.*$IF.*(REJECT|CONNECTED)" | tail -2 | sed -E 's/^.*wpa_supplicant\[[0-9]+\]: /     /'; }
sudo -v || exit 1
{
[ -n "$USB" ] && nmcli dev disconnect "$USB" > /dev/null 2>&1 && echo "== clé USB déconnectée"
echo "== 1. rechargement de brcmfmac (comme le hook au réveil)"
sudo sh -c 'modprobe -r brcmfmac_wcc 2>/dev/null; modprobe -r brcmfmac && sleep 1 && modprobe brcmfmac'
sleep 6; etat
echo "== 2. connexion sans rien faire"; R=$(essai); echo "$R"
if [[ $R == *ÉCHEC* ]]; then
  nmcli dev disconnect "$IF" > /dev/null 2>&1; sleep 2
  echo "== 3. correctif : iw reg set 00 puis FR"; sudo $IW reg set 00; sleep 1; sudo $IW reg set FR; sleep 3; etat
  echo "== 4. connexion après correctif"; R=$(essai); echo "$R"
fi
if [[ $R == *ÉCHEC* ]] && [ -n "$USB" ]; then nmcli dev wifi connect "$SECOURS" ifname "$USB" > /dev/null && echo "== clé USB reconnectée à $SECOURS"; fi
echo "== fin"; etat
} 2>&1 | tee "$J"
echo "== journal : $J"
