#!/usr/bin/env bash
# V5 — Reconstruction intégrale (R1) : vagrant destroy -f puis vagrant up.
# Exigence : plateforme fonctionnelle sans aucune intervention. Mesure :
# durée totale de la reconstruction.
. "$(dirname "$0")/_lib.sh"

note "V5 — destruction puis reconstruction complète de la plateforme"
echo "Machines actuelles : $(vagrant status --machine-readable | awk -F, '$3=="state" && $4=="running" {n++} END {print n+0}')"

t0=$(date +%s)
vagrant destroy -f
vagrant up
t1=$(date +%s)

duree=$((t1 - t0))
echo
echo "Durée totale de reconstruction : ${duree} s"

attente=0
code="000"
while [ "$attente" -lt 60 ]; do
  code=$(http_code "http://${VIP}/sante")
  [ "$code" = "200" ] && break
  sleep 2; attente=$((attente + 2))
done
echo "Sonde de santé après reconstruction : /sante -> ${code} (attendu : 200)"
[ "$code" = "200" ] && echo "RÉSULTAT V5 : OK" || { echo "RÉSULTAT V5 : ÉCHEC"; exit 1; }
