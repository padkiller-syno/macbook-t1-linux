#!/bin/bash
# Essai Touch Bar après veille : imiter macOS, qui renvoie l'état d'affichage 2 (page HID 0xFF12, usage 0x31,
# rapport 3) dans la seconde qui suit le réveil ; la T1 se déconnecte alors d'elle-même ~300 ms plus tard et se
# réénumère (« connect change interrupt »), puis TouchBarServer redessine. appletbdrm gare la T1 (état 1) à la
# veille mais ne renvoie jamais l'état 2 au réveil.
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
# ESSAI temporaire (test-t1-reveil.sh) : état d'affichage 2 envoyé à la T1 dès le réveil, comme macOS
[ "\$1" = post ] || exit 0
L=/var/log/t1-sleep/t1-reveil-test-\$(date +%Y%m%d-%H%M%S).txt
{
  echo "== réveil \$(date '+%T.%N')  T1 : \$(cat /sys/bus/usb/devices/1-3/devnum 2>/dev/null)"
  python3 -I $OUTIL 2>&1
  python3 -I $OUTIL 3 02 f4 01 2>&1
  echo "== 02 envoyé \$(date '+%T.%N')"
  for t in 0.3 0.5 1 2 3; do sleep \$t; echo "+\$t s : T1 devnum=\$(cat /sys/bus/usb/devices/1-3/devnum 2>/dev/null)"; done
  python3 -I $OUTIL 2>&1
  journalctl -k --since "-20s" -o short-precise --no-pager | grep -iE 'usb 1-3|appletb|t1bridge|05ac' | tail -20
} > "\$L" 2>&1 &
EOF
  chmod 755 "$HOOK"; echo "Hook d'essai installé : $HOOK" ;;
retirer) rm -f "$HOOK"; echo "Hook d'essai retiré" ;;
*) sed -n '2,8p' "$0"; exit 1 ;;
esac
