#!/bin/bash
# Essai Touch Bar après veille : rejouer la séquence HID de macOS, relevée par capture USB (XHC20, SIP désactivé)
# sur un MacBookPro14,3 sous macOS 13.7.8 (16/11/2026), interface 6 de la T1 (SET_REPORT feature) :
#   endormissement : rapport 3 = 01 f4 01 (garage, déjà fait par appletbdrm) + CLRD ×2, puis rapport 2 = 01 02,
#                    puis SET_INTERFACE(5, 0) (données NCM coupées) et CLEAR_FEATURE(remote wakeup)
#   réveil         : la T1 se déconnecte d'elle-même, réénumération, REDY spontané de la T1 sur l'affichage,
#                    GINF/REDY/CLRD (= appletbdrm_t1_rearm), puis rapport 5 = 01 00…00 0b 00…, rapport 3 = 02 f4 01,
#                    rapport 2 = 01 01, puis les images.
# Linux n'envoie jamais le rapport 2 = 01 02 avant la veille, ni les rapports 5 et 2 au réveil.
#   sudo bash test-t1-reveil.sh installer   hook temporaire /usr/lib/systemd/system-sleep/zz-t1-reveil-test
#   sudo bash test-t1-reveil.sh retirer
# Journal : /var/log/t1-sleep/t1-reveil-test-<date>.txt
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
HOOK=/usr/lib/systemd/system-sleep/zz-t1-reveil-test
OUTIL=$(dirname "$(readlink -f "$0")")/t1-hid-feature.py
case "${1:-}" in
installer)
  cat > "$HOOK" <<EOF
#!/bin/sh
# ESSAI temporaire (test-t1-reveil.sh) : séquence HID de macOS autour de la veille pour la Touch Bar (T1)
T="python3 -I $OUTIL"
case "\$1" in
  pre)
    cat /sys/bus/usb/devices/1-3/devnum > /run/t1-devnum-avant 2>/dev/null
    # sans ça, Linux réinitialise la T1 au réveil en gardant l'ancien périphérique (reset-resume) au lieu de la
    # réénumérer comme macOS
    echo 0 > /sys/bus/usb/devices/1-3/power/persist
    \$T 2 01 02 > /run/t1-reveil-pre.txt 2>&1
    # macOS, juste avant la veille : SET_INTERFACE(5, 0) = interface de données NCM (réseau interne avec bridgeOS)
    # désactivée. Détacher apple_t1_ncm fait la même chose (usb_unbind_interface remet le réglage 0).
    echo 1-3:2.4 > /sys/bus/usb/drivers/apple_t1_ncm/unbind 2>>/run/t1-reveil-pre.txt
    echo "NCM détaché, interface 5 réglage=\$(cat /sys/bus/usb/devices/1-3:2.5/bAlternateSetting)" >> /run/t1-reveil-pre.txt ;;
  post)
    # capture USB du bus 1 dès le réveil (tshark ne reprend qu'après la réénumération de la T1) : texte usbmon,
    # 32 premiers octets de chaque transfert, 20 s
    modprobe usbmon && timeout 20 cat /sys/kernel/debug/usb/usbmon/1u > /var/log/t1-sleep/usbmon-reveil-\$(date +%Y%m%d-%H%M%S).txt 2>&1 &
    L=/var/log/t1-sleep/t1-reveil-test-\$(date +%Y%m%d-%H%M%S).txt
    {
      cat /run/t1-reveil-pre.txt
      AV=\$(cat /run/t1-devnum-avant 2>/dev/null)
      echo "== réveil \$(date '+%T.%N') devnum avant=\$AV"
      for n in \$(seq 1 30); do
        D=\$(cat /sys/bus/usb/devices/1-3/devnum 2>/dev/null)
        [ -n "\$D" ] && [ "\$D" != "\$AV" ] && break
        sleep 0.2
      done
      echo "== \$(date '+%T.%N') devnum=\$D (\$([ "\$D" != "\$AV" ] && echo 'T1 réénumérée' || echo 'pas de réénumération'))"
      sleep 1
      \$T 5 01 00 00 00 00 00 00 00 00 00 00 0b
      \$T 3 02 f4 01
      \$T 2 01 01
      [ -e /sys/bus/usb/devices/1-3:2.4/driver ] || echo 1-3:2.4 > /sys/bus/usb/drivers/apple_t1_ncm/bind
      echo "== séquence envoyée \$(date '+%T.%N') ; NCM : \$(basename \$(readlink /sys/bus/usb/devices/1-3:2.4/driver 2>/dev/null) 2>/dev/null)"
      systemctl restart t1-touchbar-hw.service
      journalctl -k --since "-30s" -o short-precise --no-pager | grep -iE 'usb 1-3|appletb|t1bridge|disconnect' | tail -15
    } > "\$L" 2>&1 ;;
esac
EOF
  chmod 755 "$HOOK"; echo "Hook d'essai installé : $HOOK" ;;
retirer) rm -f "$HOOK" /run/t1-devnum-avant /run/t1-reveil-pre.txt; echo "Hook d'essai retiré" ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
