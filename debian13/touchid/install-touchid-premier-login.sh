#!/bin/bash
# Touch ID seulement après une première saisie du mot de passe depuis le démarrage (connexion, sudo, polkit…).
# Ajoute trois lignes pam_exec (script touchid-verrou) :
#   common-auth      : avant le contexte Touch ID, « verrouille » → saute contexte + pam_fprintd ;
#                      après pam_deny, « marquer » (atteint seulement si pam_unix a réussi) ;
#   gdm-fingerprint  : « ouvert » en requisite avant pam_fprintd (sinon GDM n'offre que le mot de passe).
# Les sauts sont choisis pour qu'un échec de pam_exec ne puisse ni bloquer ni ouvrir une session :
#   « verrouille » [success=2 default=ignore] : erreur → Touch ID proposé comme avant ;
#   « marquer » optional : son échec ne compte pas (pam_unix a déjà réussi).
# Usage : sudo bash install-touchid-premier-login.sh            (installer)
#         sudo bash install-touchid-premier-login.sh annuler    (retirer)
# Test : garder un terminal root ouvert, puis dans un autre : sudo -k && sudo true
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
ICI=$(dirname "$(readlink -f "$0")")
BIN=/usr/local/lib/t1bridge/touchid-verrou
CTX=/usr/local/lib/t1bridge/touchid-context
CA=/etc/pam.d/common-auth; GF=/etc/pam.d/gdm-fingerprint
B=/root/backup-pam/$(date +%Y%m%d-%H%M%S)-touchid-premier-login

mkdir -p "$B"; cp -p "$CA" "$GF" "$B/"
# installation précédente : retirer nos lignes et remettre le saut d'origine de pam_fprintd
sed -i "\#pam_exec\.so.*$BIN#d" "$CA" "$GF"
sed -i 's/^\(auth\s*\)\[success=3 default=ignore\]\(\s*pam_fprintd\.so\)/\1[success=2 default=ignore]\2/' "$CA"
if [ "${1:-}" = annuler ]; then
  rm -f "$BIN"; echo "== Retiré (sauvegarde : $B)"; exit 0
fi

grep -q "^auth.*\[success=2 default=ignore\].*pam_fprintd\.so" "$CA" || { echo "common-auth inattendu, rien fait"; exit 1; }
grep -q "^auth.*\[success=1 default=ignore\].*pam_unix\.so" "$CA" || { echo "common-auth inattendu, rien fait"; exit 1; }
grep -q "$CTX" "$CA" || { echo "lancer d'abord install-touchid-context.sh"; exit 1; }
install -Dm755 "$ICI/touchid-verrou" "$BIN"

# common-auth, ordre final :
#   [success=2 default=ignore] verrouille   (mot de passe pas encore saisi → saute contexte + fprintd)
#   optional                   touchid-context
#   [success=3 default=ignore] pam_fprintd  (saute pam_unix, pam_deny et marquer)
#   [success=1 default=ignore] pam_unix     (saute pam_deny)
#   requisite                  pam_deny
#   optional                   marquer      (seteuid : sudo lance pam_exec avec l'uid réel de l'utilisateur)
#   required                   pam_permit
sed -i "\#^auth.*pam_exec\.so.*$CTX#i auth\t[success=2 default=ignore]\tpam_exec.so quiet $BIN verrouille" "$CA"
sed -i 's/^\(auth\s*\)\[success=2 default=ignore\]\(\s*pam_fprintd\.so\)/\1[success=3 default=ignore]\2/' "$CA"
sed -i "\#^auth.*pam_deny\.so#a auth\toptional\t\t\tpam_exec.so quiet seteuid $BIN marquer" "$CA"
# gdm-fingerprint : avant pam_fprintd
sed -i "\#^auth.*pam_fprintd\.so#i auth\trequisite\tpam_exec.so quiet $BIN ouvert" "$GF"

echo "== common-auth :"; grep -nE '^auth' "$CA"
echo "== gdm-fingerprint :"; grep -nE '^auth' "$GF"
echo "== Sauvegarde : $B"
# déjà connecté par mot de passe depuis ce démarrage : on ne reverrouille pas la session en cours
"$BIN" marquer
echo "== Touch ID permis pour ce démarrage (session déjà ouverte) ; verrouillé au prochain démarrage."
echo "== Test : dans un NOUVEAU terminal, sudo -k && sudo true (garder celui-ci ouvert en cas de souci)"
