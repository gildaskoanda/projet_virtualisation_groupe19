#!/usr/bin/env bash
# V6 — Panne du répartiteur actif (extension E1) : vagrant halt lb1.
# Exigence : le service reste joignable à la même adresse (la VIP), en moins
# de 5 secondes. Mesure : durée de l'interruption visible pour un client.
#
# La reprise se mesure à partir de la PREMIÈRE ERREUR observée après l'ordre
# d'arrêt (pas à partir de l'ordre lui-même : lb1 répond encore pendant son
# arrêt « propre »). Sans erreur, aucune interruption n'a été vue.
#
# Réglages : V6_APRES (défaut 15) = secondes d'observation après l'arrêt ;
#            V6_FORCE=1 = coupure brutale (vagrant halt -f), pire cas : lb1
#            n'annonce pas son départ, lb2 doit le déduire des annonces VRRP.
. "$(dirname "$0")/_lib.sh"

APRES=${V6_APRES:-15}
ARRET=(vagrant halt lb1)
[ "${V6_FORCE:-0}" = 1 ] && ARRET=(vagrant halt -f lb1)

note "V6 — arrêt de lb1 pendant une sonde continue sur la VIP ${VIP}"

if ! awk -F'\t' '$1 == "lb2"' config/noeuds.tsv | grep -q .; then
  echo "ERREUR : lb2 absent (EXTENSIONS=0). V6 demande l'extension E1 : EXTENSIONS=1 vagrant up lb2"; exit 1
fi
if ! vagrant status lb1 | grep -q 'running'; then
  echo "ERREUR : lb1 n'est pas démarré."; exit 1
fi

rm -f /tmp/v6.csv /tmp/v6.stop
# Sonde continue : « epoch.fraction code », environ 5 requêtes par seconde.
(
  while [ ! -f /tmp/v6.stop ]; do
    c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://${VIP}/sante" || true)
    printf '%s %s\n' "$(date +%s.%N)" "$c"
    sleep 0.2
  done
) > /tmp/v6.csv &
SONDE=$!

sleep 4
echo "-> ${ARRET[*]}"
T_HALT=$(date +%s.%N)
"${ARRET[@]}"
T_FIN=$(date +%s.%N)
echo "   arrêt terminé en $(awk -v a="$T_HALT" -v b="$T_FIN" 'BEGIN { printf "%.0f", b - a }') s"
sleep "$APRES"
touch /tmp/v6.stop
wait "$SONDE" || true

total=$(wc -l < /tmp/v6.csv | tr -d ' ')
erreurs=$(awk -v th="$T_HALT" '$1 >= th && $2 != 200 { n++ } END { print n+0 }' /tmp/v6.csv)
premiere=$(awk -v th="$T_HALT" '$1 >= th && $2 != 200 { print $1; exit }' /tmp/v6.csv)

echo
echo "Mode d'arrêt              : ${ARRET[*]}"
echo "Réponses totales          : ${total}"
echo "Réponses en erreur (après l'ordre d'arrêt) : ${erreurs}"

verdict="OK"
if [ -z "$premiere" ]; then
  echo "Interruption visible      : aucune (la VIP est restée joignable)"
else
  reprise=$(awk -v te="$premiere" '$1 > te && $2 == 200 { print $1; exit }' /tmp/v6.csv)
  if [ -z "$reprise" ]; then
    echo "Interruption visible      : sans reprise pendant l'observation"
    verdict="ECHEC"
  else
    duree=$(awk -v a="$premiere" -v b="$reprise" 'BEGIN { printf "%.1f", b - a }')
    echo "Première erreur           : $(awk -v a="$premiere" -v b="$T_HALT" 'BEGIN { printf "%.1f", a - b }') s après l'ordre d'arrêt"
    echo "Interruption visible      : ${duree} s (exigence < 5 s)"
    awk -v d="$duree" 'BEGIN { exit !(d < 5) }' || verdict="ECHEC"
  fi
fi

echo "VIP portée par lb2        : $(vagrant ssh lb2 -c "ip -4 addr show | grep -c ${VIP}" 2>/dev/null | tr -d '\r') (attendu : 1)"
echo "-> remise en service de lb1"
vagrant up lb1 >/dev/null 2>&1 || vagrant up lb1

if [ "$verdict" = "OK" ]; then
  echo "RÉSULTAT V6 : OK"
else
  echo "RÉSULTAT V6 : ÉCHEC"; exit 1
fi
