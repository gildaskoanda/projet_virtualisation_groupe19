#!/usr/bin/env bash
# RÉSULTATS-BF — bdd1 : base primaire (lecture/écriture).
# Provisionnement idempotent : rejoué deux fois de suite, il ne modifie
# rien et n'échoue pas (R2).

. /tmp/lib.sh

PG_MAJOR=16

log "installation de PostgreSQL ${PG_MAJOR}"
apt_install postgresql postgresql-contrib

# Écoute sur l'adresse du réseau privé uniquement (R8 : le trafic interne
# ne quitte jamais le réseau privé).
pg_conftool "$PG_MAJOR" main set listen_addresses "'${IP}'"
pg_conftool "$PG_MAJOR" main set wal_level replica
pg_conftool "$PG_MAJOR" main set max_wal_senders 3

HBA="/etc/postgresql/${PG_MAJOR}/main/pg_hba.conf"
if ! grep -q '# resultats-bf' "$HBA"; then
  cat >> "$HBA" <<EOF
# resultats-bf — accès autorisés sur le réseau privé uniquement
host    ${DB_NAME}        ${DB_USER}        ${RESEAU}.0/24        scram-sha-256
host    replication       ${DB_REPL_USER}   ${RESEAU}.32/32       scram-sha-256
EOF
fi
systemctl restart postgresql

PSQL="sudo -u postgres psql -tAc"

# Utilisateurs et base : créés seulement s'ils n'existent pas (idempotence).
if ! $PSQL "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}'"
fi
if ! $PSQL "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1;
then
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
fi
if ! $PSQL "SELECT 1 FROM pg_roles WHERE rolname='${DB_REPL_USER}'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE ROLE ${DB_REPL_USER} LOGIN REPLICATION PASSWORD '${DB_REPL_PASSWORD}'"
fi

log "jeu de données (50 000 lignes, déterministe)"
sudo -u postgres psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f /tmp/schema.sql
sudo -u postgres psql -d "$DB_NAME" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${DB_USER}"

log "bdd1 OK — matricule de test : 100001"
