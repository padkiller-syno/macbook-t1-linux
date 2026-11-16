#!/bin/sh
# Son interne du MacBookPro13,3 après une veille S3.
# Le pilote snd_hda_macbookpro (module snd_hda_codec_cs8409) ne configure les puces voisines du CS8409
# (amplis MAX98706, CS42L83 du casque, micros) qu'au démarrage du codec ; son « resume » ne le refait pas.
# Après S3 : plus de son ni de micro. On redémarre donc le codec : contrôleur interne détaché, module cs8409
# rechargé, contrôleur rattaché. Le codec remis à zéro a perdu l'identifiant Apple et les broches écrits par
# l'EFI : hda-macbook13-3.patch (option patch= de snd-hda-intel) les rétablit à chaque détection.
# NE PAS toucher au contrôleur HDMI de la Radeon (0000:01:00.1) : le détacher juste après le réveil a figé la
# machine le 16/11 (écran noir). Limite : snd_hda_intel ne réutilise jamais un numéro de carte (32 au plus
# par chargement du module) → environ 30 veilles par démarrage, ensuite plus de son jusqu'au redémarrage.
# Lancé 3 s après le réveil par le hook veille-macbook (systemd-run), hors du hook lui-même.
#   sudo sh son-recharger.sh
D=/sys/bus/pci/drivers/snd_hda_intel
P=0000:00:1f.3
[ -e "$D/$P" ] && echo "$P" > "$D/unbind"
i=0
until modprobe -r snd_hda_codec_cs8409 2>/dev/null; do
  i=$((i + 1)); [ $i -ge 20 ] && { echo "son-recharger : cs8409 toujours utilisé" >&2; break; }
  sleep 0.5
done
modprobe snd_hda_codec_cs8409
echo "$P" > "$D/bind"
