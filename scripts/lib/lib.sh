#!/usr/bin/env bash
# RÉSULTATS-BF — fonctions communes aux scripts de provisionnement.
# Ce fichier est déposé dans /tmp/lib.sh par le provisionneur « file ».

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

log() { echo "[resultats-bf] $(hostname -s) — $*"; }

# attente <secondes_max> <commande...> : réessaie jusqu'à succès.
attente() {
  local delai_max=$1
  shift
  local t0=$SECONDS
  until "$@"; do
    if (( SECONDS - t0 >= delai_max )); then
      return 1
    fi
    sleep 1
  done
}

# apt_install <paquet...> : un seul apt-get update par provisionnement,
# installation regroupée (connexion lente supportée, consigne du cahier).
apt_install() {
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "$@"
}
