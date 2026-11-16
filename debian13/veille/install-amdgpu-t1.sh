#!/bin/bash
# amdgpu patché pour le MacBookPro13,3 (Radeon Pro 450/455/460, Polaris 11) : traces de l'état de
# la carte au réveil + redémarrage forcé du SMC quand le chargement des microcodes échoue
# (« SMU load firmware failed » après une veille S3 ou un reset GPU). Patch : patches/amdgpu-t1-smc-restart.patch
#
#   bash install-amdgpu-t1.sh compiler          (utilisateur) sources Debian du noyau en cours → ~/git/t1/amdgpu-smu
#   sudo bash install-amdgpu-t1.sh installer    module dans /lib/modules/<noyau>/updates/amdgpu-t1/ + initramfs
#   sudo bash install-amdgpu-t1.sh annuler      retour au module d'origine (+ initramfs)
# Seul le noyau en cours est touché : en cas de souci, démarrer l'autre noyau dans GRUB (options avancées).
# Réglage à chaud : /sys/module/amdgpu/parameters/t1_smc_restart (1 = actif, 0 = comportement d'origine).
set -euo pipefail
ICI=$(dirname "$(readlink -f "$0")")
K=${KVER:-$(uname -r)}
W=${WORK:-/home/benoit/git/t1/amdgpu-smu}
DEST=/lib/modules/$K/updates/amdgpu-t1

case "${1:-}" in
compiler)
  [ "$(id -u)" != 0 ] || { echo "À lancer sans sudo"; exit 1; }
  mkdir -p "$W" && cd "$W"
  ls linux-source-*.deb >/dev/null 2>&1 || apt-get download "linux-source-${K%.*}"
  [ -d linux-source ] || { dpkg-deb -x linux-source-*.deb pkg; mkdir linux-source;
    tar -xf pkg/usr/src/linux-source-*.tar.xz -C linux-source --strip-components=1 \
      --wildcards '*/drivers/gpu/drm/amd'; }
  rm -rf build && mkdir build && cp -a linux-source/drivers/gpu/drm/amd build/
  cd build/amd
  # construction hors arbre : chemin des traces relatif au dossier du module
  sed -i 's|^#define TRACE_INCLUDE_PATH ../../drivers/gpu/drm/amd/amdgpu|#define TRACE_INCLUDE_PATH .|' amdgpu/amdgpu_trace.h
  echo 'CFLAGS_amdgpu_trace_points.o := -I$(src)' >> amdgpu/Makefile
  patch -p1 < "$ICI/patches/amdgpu-t1-smc-restart.patch"
  make -C "/lib/modules/$K/build" M="$PWD/amdgpu" -j"$(nproc)" modules
  strip --strip-debug -o "$W/amdgpu-t1.ko" amdgpu/amdgpu.ko
  /sbin/modinfo "$W/amdgpu-t1.ko" | grep -E "vermagic|t1_smc"
  ;;
installer)
  [ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
  [ -f "$W/amdgpu-t1.ko" ] || { echo "Compiler d'abord ($W/amdgpu-t1.ko absent)"; exit 1; }
  /sbin/modinfo -F vermagic "$W/amdgpu-t1.ko" | grep -q "^$K " || { echo "Module compilé pour un autre noyau"; exit 1; }
  install -D -m 644 "$W/amdgpu-t1.ko" "$DEST/amdgpu.ko"
  depmod -a "$K"
  echo "== module retenu : $(/sbin/modinfo -n -k "$K" amdgpu)"
  update-initramfs -u -k "$K"
  echo "== Installé. Redémarrer, puis : journalctl -k -b | grep amdgpu-t1"
  ;;
annuler)
  [ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
  rm -rf "$DEST"
  depmod -a "$K"
  echo "== module retenu : $(/sbin/modinfo -n -k "$K" amdgpu)"
  update-initramfs -u -k "$K"
  echo "== Module d'origine remis. Redémarrer."
  ;;
*) sed -n '2,10p' "$0"; exit 1 ;;
esac
