#!/usr/bin/env bash
# V4 — Panne de la base primaire.
# Exigence : vagrant halt bdd1 -> /sante renvoie proprement 503 (jamais de
# page blanche ni d'erreur de connexion brute). Puis bascule chronométrée
# sur bdd2 (scripts/bascule.sh, R6).
. "$(dirname "$0")/_lib.sh"

note "V4 — panne de bdd1, puis bascule sur bdd2"
echo "Avant panne : /sante -> $(http_code "http://${VIP}/sante") (attendu : 200)"

vagrant halt bdd1
code="000"
for _ in $(seq 1 20); do
  code=$(http_code "http://${VIP}/sante")
  [ "$code" = "503" ] && break
  sleep 1
done
echo "Après la panne : /sante -> ${code} (attendu : 503)"
if [ "$code" != "503" ]; then
  echo "RÉSULTAT V4 : ÉCHEC (la panne de la base doit se manifester par un 503 propre)"
  exit 1
fi

echo
echo "-> exécution de la procédure de bascule chronométrée"
bash scripts/bascule.sh

code=$(http_code "http://${VIP}/sante")
echo "Après bascule : /sante -> ${code} (attendu : 200)"
[ "$code" = "200" ] && echo "RÉSULTAT V4 : OK" || { echo "RÉSULTAT V4 : ÉCHEC"; exit 1; }
