#!/usr/bin/env bash
# RÉSULTATS-BF — provisionnement commun à toutes les machines (base.sh).
# node_exporter sur chaque nœud alimente l'observabilité (extension E2).

. /tmp/lib.sh

log "installation des paquets communs (node_exporter, curl)"
apt_install curl ca-certificates prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
log "base OK"
