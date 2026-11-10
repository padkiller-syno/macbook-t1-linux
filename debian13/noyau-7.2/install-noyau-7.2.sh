#!/bin/bash
# Noyau 7.2 (trixie-backports) à côté du 6.12, sans le rendre par défaut.
#  1. GRUB_DEFAULT=saved, 6.12 reste le noyau par défaut (essai de la 7.2 par grub-reboot, retour auto si plantage)
#  2. DKMS : son (script ≥ 6.17), t1bridge-debian réservé aux 6.x, t1bridge d'origine pour les 7.x, v4l2loopback 0.15.4 (sid)
#  3. linux-image + linux-headers 7.2 depuis trixie-backports, modules compilés avant tout redémarrage
set -e
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ICI=$(dirname "$(readlink -f "$0")")
TS=$(date +%Y%m%d-%H%M%S); B=/root/backup-noyau-7.2-$TS; mkdir -p $B
OLD=$(uname -r)

echo "== 1. GRUB : choix enregistré"
cp -p /etc/default/grub $B/
sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
grep ^GRUB_DEFAULT /etc/default/grub

echo "== 2. DKMS"
cp -p /usr/src/snd_hda_macbookpro-0.1/dkms.conf $B/snd-dkms.conf
sed -i 's/install.cirrus.driver.pre617.sh -k/install.cirrus.driver.sh -k/' /usr/src/snd_hda_macbookpro-0.1/dkms.conf
cp -p /usr/src/t1bridge-debian-0.1.12/dkms.conf $B/t1bridge-debian-dkms.conf
grep -q '^BUILD_EXCLUSIVE_KERNEL' /usr/src/t1bridge-debian-0.1.12/dkms.conf || \
  echo 'BUILD_EXCLUSIVE_KERNEL="^6\."   # patchs 6.12 ; les 7.x utilisent t1bridge-upstream' >> /usr/src/t1bridge-debian-0.1.12/dkms.conf
U=/usr/src/t1bridge-upstream-0.1.12
if [ ! -d $U ]; then
  mkdir -p $U && cp -r /home/benoit/git/t1/t1bridge/kernel $U/
  find $U -name '*.ko' -o -name '*.o' -o -name '*.mod*' -o -name '.*.cmd' -o -name 'Module.symvers' -o -name 'modules.order' | xargs -r rm -f
  cat > $U/dkms.conf <<'EOC'
# t1bridge 0.1.12 (commit 81cbdf8) tel quel, écrit pour les noyaux 7.x ; les 6.x utilisent t1bridge-debian (patché)
PACKAGE_NAME="t1bridge-upstream"
PACKAGE_VERSION="0.1.12"
MAKE[0]="make -C kernel/dkms KDIR=/lib/modules/${kernelver}/build"
CLEAN="make -C kernel/dkms KDIR=/lib/modules/${kernelver}/build clean"
BUILT_MODULE_NAME[0]="t1_cfgsel"
BUILT_MODULE_LOCATION[0]="kernel/t1-cfgsel"
DEST_MODULE_LOCATION[0]="/updates/dkms"
BUILT_MODULE_NAME[1]="appletbdrm"
BUILT_MODULE_LOCATION[1]="kernel/appletbdrm-t1"
DEST_MODULE_LOCATION[1]="/updates/dkms"
BUILT_MODULE_NAME[2]="apple_t1_ncm"
BUILT_MODULE_LOCATION[2]="kernel/apple-t1-ncm"
DEST_MODULE_LOCATION[2]="/updates/dkms"
BUILT_MODULE_NAME[3]="uvcvideo"
BUILT_MODULE_LOCATION[3]="kernel/uvcvideo-t1"
DEST_MODULE_LOCATION[3]="/updates/dkms"
BUILD_EXCLUSIVE_KERNEL="^7\."
AUTOINSTALL="yes"
EOC
  dkms add -m t1bridge-upstream -v 0.1.12
fi
dpkg -i "$ICI/v4l2loopback-dkms_0.15.4-2_all.deb"

echo "== 3. Noyau 7.2 (backports)"
apt-get install -y -t trixie-backports linux-image-amd64 linux-headers-amd64
NEW=$(ls /lib/modules | grep '^7\.2' | sort -V | tail -1)
echo "== Modules pour $NEW :"
dkms status -k "$NEW"
for m in snd-hda-codec-cs8409 t1_cfgsel appletbdrm apple_t1_ncm uvcvideo v4l2loopback; do
  f=$(find /lib/modules/$NEW/updates /lib/modules/$NEW/kernel/extra -name "$m.ko*" 2>/dev/null | head -1)
  printf '  %-22s %s\n' "$m" "${f:-MANQUANT}"
done
lsinitramfs /boot/initrd.img-$NEW | grep -q t1_cfgsel && echo "  t1_cfgsel dans l'initramfs 7.2 : oui" || echo "  t1_cfgsel dans l'initramfs 7.2 : NON"

echo "== GRUB : $OLD par défaut"
UUID=$(grep -o "gnulinux-advanced-[0-9a-f-]*" /boot/grub/grub.cfg | head -1 | sed 's/gnulinux-advanced-//')
grub-set-default "gnulinux-advanced-$UUID>gnulinux-$OLD-advanced-$UUID"
grub-editenv list
echo "== Sauvegardes : $B"
echo "== Pour essayer la 7.2 une seule fois : sudo grub-reboot 'gnulinux-advanced-$UUID>gnulinux-$NEW-advanced-$UUID' && sudo reboot"
