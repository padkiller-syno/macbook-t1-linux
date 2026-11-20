#!/bin/sh
# MacBook Pro T2 (Kubuntu) : thème Plymouth « pomme » du 2016 à la place de kubuntu-logo (saisie LUKS + chargement).
# Fichiers du thème : ../../debian13/demarrage/ (partagés avec le 2016) (PNG produits par genere.py).
# Kubuntu choisit le thème par l'alternative default.plymouth (pas de plymouth-set-default-theme).
# GRUB a déjà « quiet splash » et un menu caché : rien à y changer.
# Annuler : sudo sh install-pomme-kubuntu.sh annuler
set -eu
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
SRC=$(cd "$(dirname "$0")/../../debian13/demarrage" && pwd)
DEST=/usr/share/plymouth/themes/pomme
ALT=/usr/share/plymouth/themes/default.plymouth

if [ "${1:-}" = annuler ]; then
  update-alternatives --set default.plymouth /usr/share/plymouth/themes/kubuntu-logo/kubuntu-logo.plymouth
  update-initramfs -u
  echo "== kubuntu-logo remis (le dossier $DEST est gardé)"
  exit 0
fi

ls "$SRC"/pomme.png >/dev/null || { echo "PNG absents : lancer d'abord python3 $SRC/genere.py"; exit 1; }
install -d "$DEST"
install -m 644 "$SRC"/pomme.plymouth "$SRC"/pomme.script "$SRC"/*.png "$DEST"/
update-alternatives --install "$ALT" default.plymouth "$DEST"/pomme.plymouth 200
update-alternatives --set default.plymouth "$DEST"/pomme.plymouth
update-initramfs -u
echo "== initramfs ($(uname -r)) :"
lsinitramfs /boot/initrd.img-"$(uname -r)" | grep -E "themes/pomme/|amdgpu.ko|renderers/drm|plymouth/script.so|t2bce" | sort
echo "== OK : redémarre pour voir la pomme."
