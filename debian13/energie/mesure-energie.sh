#!/bin/bash
# Mesure énergie / performance du MacBook Pro 13,3 selon le plafond de fréquence CPU.
# Pour chaque réglage : 45 s de repos (bureau), puis une tâche fixe (xz sur 8 fils, 256 Mo),
# avec l'énergie totale (batterie), CPU (Intel RAPL package) et Radeon (amdgpu PPT).
# À lancer avec sudo, SUR BATTERIE, luminosité fixe. Tout réglage modifié est restauré en sortie.
# Réglage = plafond:EPP[:dpm Radeon, low par défaut] (préférence énergétique intel_pstate, qui pèse autant que le plafond :
# avec EPP=power le CPU reste vers 900 MHz quel que soit le plafond). Profils GNOME actuels :
# économie = 1200:power:low ; équilibré = 2700:balance_power:high sur batterie (balance_performance sur
# secteur) ; performance = turbo:performance:high.
# Ne pas changer de profil pendant le test (power-profiles-daemon réécrit l'EPP).
# Usage : sudo bash mesure-energie.sh [plafond:epp …]
set -u
[ "$(id -u)" = 0 ] || { echo "Lance-moi avec sudo"; exit 1; }
[ "$(cat /sys/class/power_supply/ADP1/online)" = 0 ] || [ "${FORCE:-0}" = 1 ] || {
  echo "Débranche le chargeur (ou FORCE=1 pour tester sans la mesure batterie)"; exit 1; }

ICI=$(dirname "$(readlink -f "$0")")
OUT=$ICI/resultats-$(date +%Y%m%d-%H%M%S).txt
SETTINGS=${*:-1200:power 1600:power 1600:balance_power 2000:balance_power 2700:balance_power 2700:balance_performance turbo:performance 2700:balance_power:high}
IDLE_S=30
export LC_ALL=C
CPU=/sys/devices/system/cpu
T=$CPU/intel_pstate/no_turbo
RAPL=/sys/class/powercap/intel-rapl:0
GPU=$(ls -d /sys/class/drm/card*/device/hwmon/hwmon*/power1_input 2>/dev/null | head -1)
BAT=/sys/class/power_supply/BAT0
BL=/sys/class/backlight/gmux_backlight
DATA=/dev/shm/mesure-energie.tar
SAMPLES=/dev/shm/mesure-energie.samples

# --- état d'origine, restauré quoi qu'il arrive ---
ORIG_MAX=$(cat $CPU/cpu0/cpufreq/scaling_max_freq); ORIG_NT=$(cat $T); ORIG_BL=$(cat $BL/brightness)
ORIG_EPP=$(cat $CPU/cpu0/cpufreq/energy_performance_preference)
DPM=/sys/class/drm/card0/device/power_dpm_force_performance_level; ORIG_DPM=$(cat $DPM)
restore() {
  echo "$ORIG_DPM" > $DPM
  for e in $CPU/cpu[0-9]*/cpufreq/energy_performance_preference; do echo "$ORIG_EPP" > "$e"; done
  echo "$ORIG_NT" > $T
  for m in $CPU/cpu[0-9]*/cpufreq/scaling_max_freq; do echo "$ORIG_MAX" > "$m"; done
  echo "$ORIG_BL" > $BL/brightness
  systemctl start amdgpu-power-sync.service
  rm -f "$DATA" "$DATA.xz" "$SAMPLES"
  [ -n "${SAMPLER:-}" ] && kill "$SAMPLER" 2>/dev/null
  echo "== Réglages d'origine restaurés, amdgpu-power-sync relancé."
}
trap restore EXIT
trap 'exit 130' INT TERM

systemctl stop amdgpu-power-sync.service   # il réimpose le plafond toutes les 2 s

echo "== Préparation des données (256 Mo, hors mesure)"
tar cf - /usr/lib/x86_64-linux-gnu 2>/dev/null | head -c 268435456 > "$DATA"

# --- échantillonneur : 1/s, puissance batterie (W) et Radeon (W) ---
sampler() {
  while :; do
    awk -v i="$(cat $BAT/current_now)" -v v="$(cat $BAT/voltage_now)" -v g="$(cat "$GPU" 2>/dev/null || echo 0)" \
      'BEGIN{printf "%s %.3f %.3f\n", systime(), i*v/1e12, g/1e6}' >> "$SAMPLES"
    sleep 1
  done
}
: > "$SAMPLES"; sampler & SAMPLER=$!

rapl() { cat $RAPL/energy_uj; }
rapl_delta() {  # µJ → J, compteur qui reboucle
  local a=$1 b=$2 max; max=$(cat $RAPL/max_energy_range_uj)
  [ "$b" -lt "$a" ] && b=$((b + max)); awk -v d=$((b - a)) 'BEGIN{printf "%.1f", d/1e6}'
}
avg_between() {  # moyenne batterie et Radeon entre deux instants (s)
  awk -v a="$1" -v b="$2" '$1>=a && $1<=b {n++; w+=$2; g+=$3} END{if(n) printf "%.2f %.2f", w/n, g/n; else print "- -"}' "$SAMPLES"
}

set_cap() {  # set_cap <plafond MHz|turbo>:<epp>
  local cap epp dpm
  IFS=: read -r cap epp dpm <<<"$1"
  echo "${dpm:-low}" > $DPM
  for e in $CPU/cpu[0-9]*/cpufreq/energy_performance_preference; do echo "$epp" > "$e"; done
  set -- "$cap"
  if [ "$1" = turbo ]; then
    echo 0 > $T; mx=$(cat $CPU/cpu0/cpufreq/cpuinfo_max_freq)
  else
    echo 1 > $T; mx=$(( $1 * 1000 ))
  fi
  for m in $CPU/cpu[0-9]*/cpufreq/scaling_max_freq; do echo $mx > "$m"; done
}

{
  echo "# Mesure énergie $(date '+%F %T') — $(uname -r)"
  echo "# luminosité=$ORIG_BL/$(cat $BL/max_brightness)  batterie=$(cat $BAT/capacity 2>/dev/null)%"
  echo "# repos : moyenne sur ${IDLE_S} s ; tâche : xz -T0 -6 sur 256 Mo"
  printf "%-26s | %8s %8s %8s | %7s %9s %9s %8s\n" réglage "repos W" "CPU W" "Radeon W" "tâche s" "tâche J" "CPU J" "MHz moy"
} | tee "$OUT"

for s in $SETTINGS; do
  set_cap "$s"; echo "$ORIG_BL" > $BL/brightness
  sleep 5   # stabilisation
  # repos
  t0=$(date +%s); e0=$(rapl); sleep $IDLE_S; e1=$(rapl); t1=$(date +%s)
  read -r idle_w idle_g <<<"$(avg_between "$t0" "$t1")"
  idle_cpu=$(awk -v j="$(rapl_delta "$e0" "$e1")" -v s=$((t1 - t0)) 'BEGIN{printf "%.2f", j/s}')
  # tâche
  rm -f "$DATA.xz"; sync
  t0=$(date +%s.%N); ts0=$(date +%s); e0=$(rapl)
  ( while :; do awk '/cpu MHz/{s+=$4;n++} END{print s/n}' /proc/cpuinfo; sleep 1; done ) > /dev/shm/mhz & MHZ=$!
  xz -T0 -6 -k -c "$DATA" > "$DATA.xz"
  e1=$(rapl); t1=$(date +%s.%N); ts1=$(date +%s); kill $MHZ 2>/dev/null
  dur=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')
  read -r task_w _ <<<"$(avg_between "$ts0" "$ts1")"
  task_j=$(awk -v w="$task_w" -v d="$dur" 'BEGIN{ if (w=="-") print "-"; else printf "%.0f", w*d}')
  mhz=$(awk '{s+=$1;n++} END{if(n) printf "%.0f", s/n}' /dev/shm/mhz); rm -f /dev/shm/mhz
  printf "%-26s | %8s %8s %8s | %7s %9s %9s %8s\n" "$s" "$idle_w" "$idle_cpu" "$idle_g" "$dur" "$task_j" \
    "$(rapl_delta "$e0" "$e1")" "$mhz" | tee -a "$OUT"
  sleep 10   # refroidissement
done
echo "== Résultats : $OUT"
