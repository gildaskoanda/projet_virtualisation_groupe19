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

# apt_install <paquet...> : un seul « apt-get update » par démarrage de la
# machine (témoin dans /run), installation regroupée : connexion lente
# supportée, consigne du cahier des charges.
apt_install() {
  if [ ! -f /run/resultats-apt-maj ]; then
    apt-get update -qq
    touch /run/resultats-apt-maj
  fi
  apt-get install -y -qq --no-install-recommends "$@"
}

# ecrire_si_different <fichier> [mode] : lit le contenu sur l'entrée standard
# et n'écrit le fichier que s'il change (idempotence, R2).
# Code de retour : 0 = fichier modifié, 1 = déjà à jour.
# À utiliser dans un « if » pour ne pas déclencher « set -e ».
ecrire_si_different() {
  local dest=$1 mode=${2:-0644} tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi
  install -m "$mode" "$tmp" "$dest"
  rm -f "$tmp"
  return 0
}
