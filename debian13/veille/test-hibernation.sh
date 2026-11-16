#!/bin/bash
# Essai d'hibernation (S4) sur le MacBookPro13,3. L'hibernation est interdite par install-veille.sh
# (AllowHibernation=no) car jamais testée. Prérequis vérifiés le 16/11 : swap 15,9 Go dans le LVM chiffré,
# RESUME configuré dans l'initramfs, lockdown none.
# Au retour d'hibernation l'EFI réinitialise tout (comme au démarrage) : bon pour le Wi-Fi (puce remise sous
# tension) et le codec ; inconnus : Radeon (amdgpu reprend son état sur un GPU réinitialisé par l'EFI), T1.
#   sudo bash test-hibernation.sh test   image écrite puis rechargée SANS éteindre (test_resume), sans risque
#   sudo bash test-hibernation.sh vrai   vraie hibernation, interdiction levée le temps d'un seul essai
#   sudo bash test-hibernation.sh bilan  état après le retour (journal du démarrage en cours)
# En cas d'écran noir au retour : redémarrer (la session sauvegardée est perdue, rien d'autre).
set -u
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ESSAI=/etc/systemd/sleep.conf.d/zz-essai-hibernation.conf
case "${1:-}" in
  test)
    # 16/11 21:16 : sans le hook (écriture directe dans /sys/power/state), gel dès « hibernation entry »
    # (Thunderbolt non retiré, comme le gel de S3 avant tb-go2sx) → le hook est appelé comme le ferait systemd.
    HOOK=/usr/lib/systemd/system-sleep/veille-macbook
    sync
    echo "== hook pre hibernate"; "$HOOK" pre hibernate
    echo "== test_resume : écriture de l'image puis rechargement immédiat (l'écran peut clignoter)"
    echo test_resume > /sys/power/disk
    echo disk > /sys/power/state; rc=$?
    echo platform > /sys/power/disk
    echo "== hook post hibernate"; "$HOOK" post hibernate
    echo "== retour (code $rc)"
    journalctl -k -b --no-pager --since -3min | grep -iE "PM: (hibernation|image|Basic memory|Restoring|Creating)|amdgpu.*(error|fail|resume)|error -" | tail -15 ;;
  vrai)
    printf '%s\n' "# essai d'hibernation (test-hibernation.sh), retiré au retour" "[Sleep]" "AllowHibernation=yes" > "$ESSAI"
    # retiré au prochain démarrage quoi qu'il arrive
    printf '%s\n' "r $ESSAI" > /etc/tmpfiles.d/zz-essai-hibernation.conf
    sync
    echo "== hibernation dans 3 s (au retour : phrase LUKS, puis session)"
    sleep 3
    systemctl hibernate ;;
  bilan)
    rm -f "$ESSAI" /etc/tmpfiles.d/zz-essai-hibernation.conf
    echo "== interdiction rétablie"
    journalctl -b --no-pager -o short-precise | grep -E "PM: (hibernation|Image|resume from hibernation|Restoring)|Restarting tasks|systemd-sleep|veille-son|amdgpu-t1|hibernat" | tail -20 | sed -E 's/^\S+ \S+ \S+ //' ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
