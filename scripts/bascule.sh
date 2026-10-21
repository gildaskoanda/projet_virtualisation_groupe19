#!/usr/bin/env bash
# RÉSULTATS-BF — procédure de bascule de la base primaire vers la réplique
# (R6, scénario V4). À exécuter depuis la racine du dépôt, sur l'hôte.
#
# La procédure suppose que bdd1 est arrêtée ou hors service (panne simulée
# par « vagrant halt bdd1 » dans le scénario V4). Elle mesure et affiche le
# temps total de bascule.
set -euo pipefail

BDD2="$(awk -F'\t' '$3 == "replique" { print $2; exit }' config/noeuds.tsv)"
APPS="$(awk -F'\t' '$3 == "app" { print $1 }' config/noeuds.tsv)"
VIP="$(awk -F'\t' '$1 == "lb1" { print $4 }' config/noeuds.tsv)"

t0=$(date +%s)
echo "=== Bascule RÉSULTATS-BF : primaire bdd1 -> ${BDD2} (bdd2) ==="

echo "[1/2] promotion de bdd2 en primaire"
vagrant ssh bdd2 -c "sudo -u postgres pg_ctlcluster 16 main promote" >/dev/null
etat=""
for _ in $(seq 1 30); do
  etat="$(vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'" 2>/dev/null | tr -d '\r' || true)"
  [ "$etat" = "f" ] && break
  sleep 1
done
if [ "$etat" != "f" ]; then
  echo "ERREUR : bdd2 n'a pas été promue (pg_is_in_recovery = '${etat}')"
  exit 1
fi
echo "      bdd2 est désormais primaire"

echo "[2/2] pointage des applications vers ${BDD2} + redémarrage"
for app in $APPS; do
  vagrant ssh "$app" -c \
    "sudo sed -i 's/^DB_HOST=.*/DB_HOST=${BDD2}/' /etc/default/resultats && sudo systemctl restart resultats" \
    >/dev/null
  echo "      ${app} rebasculé"
done

echo "[+] vérification de la sonde de santé via le répartiteur"
code="000"
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://${VIP}/sante" || echo 000)
  [ "$code" = "200" ] && break
  sleep 1
done

t1=$(date +%s)
echo "=== Bascule terminée en $((t1 - t0)) secondes — /sante renvoie ${code} ==="
[ "$code" = "200" ] || exit 1
