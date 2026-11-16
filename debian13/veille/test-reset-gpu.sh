#!/bin/bash
# Déclenche une réinitialisation de la Radeon à chaud (debugfs amdgpu_gpu_recover) pour tester une
# méthode de reset, sans passer par la veille. Écran noir possible pendant ~10 s, ou définitif si la
# méthode échoue (appui long alors, le journal garde les traces).
#   sudo bash test-reset-gpu.sh 5    BACO (la puce entière est éteinte puis rallumée, SMC compris)
#   sudo bash test-reset-gpu.sh 0    legacy (« PCI CONFIG reset », celui qui échoue aujourd'hui)
#   Attention : en 7.2, BACO vaut 5 (enum amd_reset_method : LINK=4 a été inséré), pas 4 comme le
#   dit encore la description du paramètre. 4 retombe en silence sur « PCI CONFIG reset ».
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
METHODE=${1:-5}
OUT=/var/log/t1-sleep/reset-$METHODE-$(date +%Y%m%d-%H%M%S).txt
mkdir -p /var/log/t1-sleep
D=$(grep -l "0000:01:00.0" /sys/kernel/debug/dri/*/name | head -1 | xargs dirname)
[ -e "$D/amdgpu_gpu_recover" ] || { echo "amdgpu_gpu_recover introuvable"; exit 1; }
AVANT=$(cat /sys/module/amdgpu/parameters/reset_method)
echo "$METHODE" > /sys/module/amdgpu/parameters/reset_method
start=$(date '+%F %T')
echo "# reset méthode $METHODE ($D) — $start — $(uname -r)" > "$OUT"
sync
echo "== Reset de la Radeon dans 3 s (méthode $METHODE)…"
sleep 3
cat "$D/amdgpu_gpu_recover" >> "$OUT" 2>&1 || true
sleep 10
echo "$AVANT" > /sys/module/amdgpu/parameters/reset_method
journalctl -k --since "$start" -o short-precise --no-pager >> "$OUT"
sync
echo "== Fini. Journal : $OUT"
grep -E "amdgpu-t1|BACO|PCI CONFIG|reset (succeeded|end)|SMU|ip_resume|ring .*timeout" "$OUT" | head -20
