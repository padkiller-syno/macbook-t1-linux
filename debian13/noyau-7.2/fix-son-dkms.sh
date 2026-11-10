#!/bin/bash
# Pilote son : le module compilé est dans build/hda (< 6.17) ou build/hda/codecs/cirrus (>= 6.17, nouvelle arborescence HDA).
# dkms.conf est lu comme un script shell avec $kernelver : on choisit l'emplacement selon la version.
set -e
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
C=/usr/src/snd_hda_macbookpro-0.1/dkms.conf
cat > $C <<'EOC'
PACKAGE_NAME="snd_hda_macbookpro"
PACKAGE_VERSION="0.1"
# install.cirrus.driver.sh délègue lui-même à install.cirrus.driver.pre617.sh pour les noyaux < 6.17
PRE_BUILD="install.cirrus.driver.sh -k $kernelver --dkms"
MAKE="make"
BUILT_MODULE_NAME[0]="snd-hda-codec-cs8409"
# Arborescence HDA réorganisée en 6.17 : sound/hda/codecs/cirrus/
case "$kernelver" in
  [0-5].*|6.[0-9].*|6.1[0-6].*) BUILT_MODULE_LOCATION[0]="build/hda" ;;
  *)                            BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus" ;;
esac
DEST_MODULE_LOCATION[0]="/kernel/extra"
AUTOINSTALL="yes"
EOC
NEW=$(ls /lib/modules | grep '^7\.2' | sort -V | tail -1)
dkms build -m snd_hda_macbookpro -v 0.1 -k "$NEW" --force
dkms install -m snd_hda_macbookpro -v 0.1 -k "$NEW" --force
dkms status -m snd_hda_macbookpro
