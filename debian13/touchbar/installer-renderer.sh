#!/bin/bash
# Installe le renderer Touch Bar recompilé (~/git/t1/t1bridge, branche macbook-local) et le fournisseur bureau.
# Ordre imposé : renderer d'abord (l'ancien refuse les champs inconnus du nouveau fournisseur), puis fournisseur,
# puis redémarrage du service utilisateur. Ancien binaire gardé : /usr/lib/t1bridge/t1-touchbar.bak-<date>.
#   bash installer-renderer.sh            (sudo demandé pour /usr/lib/t1bridge)
#   bash installer-renderer.sh annuler    (remet le binaire et le fournisseur sauvegardés les plus récents)
set -euo pipefail
ICI=$(dirname "$(readlink -f "$0")")
SRC=$HOME/git/t1/t1bridge/target/release/t1-touchbar
BIN=/usr/lib/t1bridge/t1-touchbar
PROV=$HOME/.local/bin/t1-desktop-provider
DATE=$(date +%Y%m%d-%H%M%S)

if [ "${1:-}" = annuler ]; then
  ancien=$(ls -t /usr/lib/t1bridge/t1-touchbar.bak-* | head -1)
  prov=$(ls -t "$PROV".bak-* 2>/dev/null | head -1 || true)
  [ -n "$prov" ] && cp -p "$prov" "$PROV"
  sudo install -m 755 "$ancien" "$BIN"
  systemctl --user restart t1-touchbar.service
  echo "== remis : $ancien${prov:+, $prov}"; exit 0
fi

[ -x "$SRC" ] || { echo "binaire absent : cargo build --release -p t1-touchbar dans ~/git/t1/t1bridge"; exit 1; }
sudo sh -c "cp -p '$BIN' '$BIN.bak-$DATE' && install -s -m 755 '$SRC' '$BIN'"
cp -p "$PROV" "$PROV.bak-$DATE"
install -m 755 "$ICI/desktop-provider/t1-desktop-provider" "$PROV"
systemctl --user restart t1-touchbar.service
sleep 2
systemctl --user --no-pager --lines=3 status t1-touchbar.service | head -6
echo "== installé ; sauvegardes : $BIN.bak-$DATE et $PROV.bak-$DATE"
