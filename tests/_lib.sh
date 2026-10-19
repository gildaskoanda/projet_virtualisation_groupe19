#!/usr/bin/env bash
# RÉSULTATS-BF — bibliothèque commune des scénarios de validation.
# Les scripts doivent être lancés depuis la racine du dépôt, après un
# « vagrant up » complet (bdd1 bdd2 app* lb1 lb2 obs).
set -euo pipefail

if [ ! -f config/noeuds.tsv ]; then
  echo "ERREUR : lancez les scénarios depuis la racine du dépôt (config/noeuds.tsv absent)." >&2
  exit 1
fi

VIP="$(awk -F'\t' '$1 == "lb1" { print $4 }' config/noeuds.tsv)"
NB_APP="$(awk -F'\t' '$3 == "app"' config/noeuds.tsv | wc -l | tr -d ' ')"

note() { echo; echo "=== $* ==="; }
http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$1" || echo 000; }
