#!/usr/bin/env bash
# V2 — Panne d'un serveur applicatif pendant une charge.
# Exigence : le service reste disponible ; plus aucune erreur au-delà de
# 5 secondes. Mesure : requêtes perdues, durée de la période dégradée,
# latence maximale, preuve que app1 est bien éjecté puis réintégré.
#
# Réglages (secondes, modifiables par variable d'environnement) :
#   V2_BASE   observation avant la panne           (défaut 5)
#   V2_PANNE  observation avec app1 réellement arrêtée (défaut 20)
#   V2_REPRISE attente maximale de la réintégration    (défaut 60)
#   V2_FORCE=1 coupure brutale (vagrant halt -f) : pire cas, sans RST TCP
. "$(dirname "$0")/_lib.sh"

BASE=${V2_BASE:-5}
PANNE=${V2_PANNE:-20}
REPRISE=${V2_REPRISE:-60}
URL="http://${VIP}/resultat?matricule=100001"
ARRET=(vagrant halt app1)
[ "${V2_FORCE:-0}" = 1 ] && ARRET=(vagrant halt -f app1)

note "V2 — arrêt de app1 pendant des consultations continues (/resultat) via le répartiteur"

if ! vagrant status app1 | grep -q 'running'; then
  echo "ERREUR : app1 n'est pas démarrée."; exit 1
fi

rm -f /tmp/v2.csv /tmp/v2.stop
# Sonde continue : « epoch code latence », 4 requêtes par seconde environ.
(
  while [ ! -f /tmp/v2.stop ]; do
    r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 3 "$URL" || true)
    printf '%s %s\n' "$(date +%s)" "$r"
    sleep 0.25
  done
) > /tmp/v2.csv &
SONDE=$!

sleep "$BASE"
echo "-> ${ARRET[*]}"
T_HALT=$(date +%s)
"${ARRET[@]}"
T_FIN_HALT=$(date +%s)
echo "   arrêt terminé en $((T_FIN_HALT - T_HALT)) s"

# Observation pendant que app1 est réellement arrêtée.
sleep "$PANNE"
echo "-> app1 arrêtée : 12 appels à /info (app1 ne doit plus répondre)"
for _ in $(seq 1 12); do
  { curl -s --max-time 3 "http://${VIP}/info" || true; echo; } \
    | sed -n 's/.*"hote": *"\([^"]*\)".*/\1/p'
done > /tmp/v2_info_panne.txt
sort /tmp/v2_info_panne.txt | uniq -c
vus_app1=$(grep -c '^app1$' /tmp/v2_info_panne.txt || true)

echo "-> vagrant up app1 (remise en service)"
vagrant up app1
reintegre="non"
t0=$SECONDS
while (( SECONDS - t0 < REPRISE )); do
  if { curl -s --max-time 3 "http://${VIP}/info" || true; echo; } | grep -q '"app1"'; then
    reintegre="oui, après $((SECONDS - t0)) s"; break
  fi
  sleep 1
done

touch /tmp/v2.stop
wait "$SONDE" || true

total=$(wc -l < /tmp/v2.csv | tr -d ' ')
erreurs=$(awk '$2 != 200 { n++ } END { print n+0 }' /tmp/v2.csv)
premiere_err=$(awk '$2 != 200 { print $1; exit }' /tmp/v2.csv)
derniere_err=$(awk '$2 != 200 { t=$1 } END { print t+0 }' /tmp/v2.csv)
lat_max=$(awk '{ if ($3+0 > m) m = $3+0 } END { printf "%.2f", m }' /tmp/v2.csv)
lentes=$(awk '$3+0 > 1.0 { n++ } END { print n+0 }' /tmp/v2.csv)

echo
echo "Mode d'arrêt          : ${ARRET[*]}"
echo "Réponses totales      : ${total}"
echo "Réponses en erreur    : ${erreurs} (≠200)"
if [ "$erreurs" -eq 0 ]; then
  echo "Première erreur       : aucune"
  echo "Période dégradée      : 0 s"
  duree_degradee=0
else
  duree_degradee=$((derniere_err - premiere_err))
  echo "Première erreur       : $((premiere_err - T_HALT)) s après le début de l'arrêt"
  echo "Période dégradée      : ${duree_degradee} s"
fi
echo "Latence maximale      : ${lat_max} s (requêtes > 1 s : ${lentes})"
echo "app1 vue pendant la panne : ${vus_app1} fois sur 12 (attendu : 0)"
echo "app1 réintégrée       : ${reintegre}"

if [ "$vus_app1" -ne 0 ]; then
  echo "RÉSULTAT V2 : ÉCHEC (app1 répond encore, ou n'est pas éjectée)"; exit 1
elif [ "$erreurs" -eq 0 ]; then
  echo "RÉSULTAT V2 : OK (aucune requête perdue)"
elif [ "$duree_degradee" -le 5 ] && [ "$erreurs" -lt $((total / 20)) ]; then
  echo "RÉSULTAT V2 : ACCEPTABLE (dégradation < 5 s, pertes marginales)"
else
  echo "RÉSULTAT V2 : ÉCHEC"; exit 1
fi
