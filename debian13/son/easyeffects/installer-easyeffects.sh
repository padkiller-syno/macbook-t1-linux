#!/bin/bash
# EasyEffects pour MacBookPro13,3 (Debian 13) : préréglages haut-parleurs / micro,
# DeepFilterNet (débruitage) et correctif du volume de la sortie EasyEffects.
# À lancer en utilisateur normal (pas de sudo). Prérequis :
#   sudo apt install easyeffects lsp-plugins-lv2 calf-plugins
set -euo pipefail
cd "$(dirname "$0")"

DFN_VER=0.5.6
DFN_SHA=2ca3205c2911d389604a826a240e745597d50252b5cab81c8248252b335e2236
DFN_URL=https://github.com/Rikorose/DeepFilterNet/releases/download/v$DFN_VER/libdeep_filter_ladspa-$DFN_VER-x86_64-unknown-linux-gnu.so

for p in easyeffects calf-plugins lsp-plugins-lv2; do
  dpkg -s "$p" >/dev/null 2>&1 || { echo "manque $p : sudo apt install easyeffects lsp-plugins-lv2 calf-plugins"; exit 1; }
done

EE=~/.config/easyeffects
mkdir -p "$EE/output" "$EE/input" "$EE/autoload/output" ~/.ladspa ~/.config/environment.d \
         ~/.local/share/wireplumber/scripts ~/.config/wireplumber/wireplumber.conf.d
install -m644 output/*.json   "$EE/output/"
install -m644 input/*.json    "$EE/input/"
install -m644 autoload/*.json "$EE/autoload/output/"
install -m644 wireplumber/ee-sink-volume.lua      ~/.local/share/wireplumber/scripts/
install -m644 wireplumber/60-ee-sink-volume.conf  ~/.config/wireplumber/wireplumber.conf.d/
install -m644 60-ladspa.conf ~/.config/environment.d/

# DeepFilterNet (absent du paquet Debian), vérifié par SHA-256
so=~/.ladspa/libdeep_filter_ladspa.so
if ! echo "$DFN_SHA  $so" | sha256sum -c --quiet 2>/dev/null; then
  tmp=$(mktemp); curl -fL --progress-bar -o "$tmp" "$DFN_URL"
  echo "$DFN_SHA  $tmp" | sha256sum -c --quiet || { rm -f "$tmp"; echo "SHA-256 DeepFilterNet incorrect"; exit 1; }
  install -m644 "$tmp" "$so"; rm -f "$tmp"
fi

# appliquer tout de suite (sinon au prochain login)
export LADSPA_PATH=$HOME/.ladspa:/usr/local/lib/ladspa:/usr/lib/x86_64-linux-gnu/ladspa:/usr/lib/ladspa
systemctl --user set-environment LADSPA_PATH="$LADSPA_PATH"
systemctl --user restart wireplumber
if pgrep -x easyeffects >/dev/null; then easyeffects -q; sleep 2; fi
setsid -f easyeffects --gapplication-service >/dev/null 2>&1
sleep 3
easyeffects -l "MacBook HP"; easyeffects -l "Micro MacBook"
# quitter EasyEffects fait retomber la sortie par défaut sur la carte : la remettre
id=$(pw-dump | python3 -c 'import json,sys;print(next(o["id"] for o in json.load(sys.stdin) if o.get("info",{}).get("props",{}).get("node.name")=="easyeffects_sink"))')
wpctl set-default "$id"
echo "OK : préréglages « MacBook HP » (haut-parleurs) et « Micro MacBook » chargés"
echo "⚠ relancez les applis audio ouvertes qui passent par ALSA (Plexamp…) : elles perdent leur sortie au redémarrage de WirePlumber"
