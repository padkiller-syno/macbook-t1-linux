#!/bin/bash
# Installe le contexte Touch ID pour la Touch Bar (ce qu'on autorise, essais, délai) :
# script touchid-context + une ligne pam_exec avant pam_fprintd dans common-auth et gdm-fingerprint.
# Usage : sudo bash install-touchid-context.sh            (installer)
#         sudo bash install-touchid-context.sh annuler    (retirer)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ICI=$(dirname "$(readlink -f "$0")")
BIN=/usr/local/lib/t1bridge/touchid-context
B=/root/backup-pam/$(date +%Y%m%d-%H%M%S)-touchid-context
# seteuid : sans lui, pam_exec lance le script sous l'utilisateur réel (pas root) -> /run/t1bridge non inscriptible
LIGNE="auth	optional	pam_exec.so quiet seteuid type=auth $BIN"

mkdir -p "$B"; cp -p /etc/pam.d/common-auth /etc/pam.d/gdm-fingerprint "$B/"
# retire une ligne d'une installation précédente (réinstallation = mise à jour)
sed -i "\#pam_exec\.so.*$BIN#d" /etc/pam.d/common-auth /etc/pam.d/gdm-fingerprint
if [ "${1:-}" = annuler ]; then
  rm -f "$BIN" /run/t1bridge/touch-id-context
  echo "== Retiré (sauvegarde : $B)"; exit 0
fi

install -Dm755 "$ICI/touchid-context" "$BIN"
# common-auth : avant pam_fprintd (essais et délai repris de sa ligne)
if ! grep -q "$BIN" /etc/pam.d/common-auth; then
  args=$(sed -n 's/.*pam_fprintd\.so.*max-tries=\([0-9]*\).*timeout=\([0-9]*\).*/\1 \2/p' /etc/pam.d/common-auth | head -1)
  sed -i "\#^auth.*pam_fprintd\.so#i $LIGNE ${args:-3 30}" /etc/pam.d/common-auth
fi
# gdm-fingerprint : pam_fprintd sans option = 3 essais, 30 s
grep -q "$BIN" /etc/pam.d/gdm-fingerprint || \
  sed -i "\#^auth.*pam_fprintd\.so#i $LIGNE 3 30" /etc/pam.d/gdm-fingerprint
echo "== common-auth :"; grep -n "pam_exec\|pam_fprintd" /etc/pam.d/common-auth
echo "== gdm-fingerprint :"; grep -n "pam_exec\|pam_fprintd" /etc/pam.d/gdm-fingerprint
echo "== Sauvegarde : $B"
echo "== Test : dans un NOUVEAU terminal, sudo -k && sudo true (garder celui-ci ouvert en cas de souci)"
