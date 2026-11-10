#!/bin/bash
# Suite de install-noyau-7.2.sh après l'échec DKMS du son : correctif, fin de configuration du noyau, 6.12 par défaut.
set -e
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ICI=$(dirname "$(readlink -f "$0")")
OLD=$(uname -r)
bash "$ICI/fix-son-dkms.sh"
echo "== Fin de configuration du noyau 7.2"
dpkg --configure -a
NEW=$(ls /lib/modules | grep '^7\.2' | sort -V | tail -1)
echo "== Modules pour $NEW :"
for m in snd-hda-codec-cs8409 t1_cfgsel appletbdrm apple_t1_ncm uvcvideo v4l2loopback; do
  f=$(find /lib/modules/$NEW/updates /lib/modules/$NEW/kernel/extra -name "$m.ko*" 2>/dev/null | head -1)
  printf '  %-22s %s\n' "$m" "${f:-MANQUANT}"
done
lsinitramfs /boot/initrd.img-$NEW | grep -q t1_cfgsel && echo "  t1_cfgsel dans l'initramfs 7.2 : oui" || echo "  t1_cfgsel dans l'initramfs 7.2 : NON"
lsinitramfs /boot/initrd.img-$NEW | grep -q "themes/pomme/pomme.script" && echo "  thème pomme dans l'initramfs 7.2 : oui" || echo "  thème pomme : NON"
echo "== GRUB : $OLD par défaut"
UUID=$(grep -o "gnulinux-advanced-[0-9a-f-]*" /boot/grub/grub.cfg | head -1 | sed 's/gnulinux-advanced-//')
grep -q "gnulinux-$NEW-advanced-$UUID" /boot/grub/grub.cfg && echo "  entrée 7.2 présente dans grub.cfg"
grub-set-default "gnulinux-advanced-$UUID>gnulinux-$OLD-advanced-$UUID"
grub-editenv list
echo "ESSAI=gnulinux-advanced-$UUID>gnulinux-$NEW-advanced-$UUID" > "$ICI/essai.env"
echo "== Pour essayer la 7.2 une seule fois : sudo grub-reboot 'gnulinux-advanced-$UUID>gnulinux-$NEW-advanced-$UUID' && sudo reboot"
