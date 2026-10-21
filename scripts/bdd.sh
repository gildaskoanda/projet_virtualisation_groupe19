#!/usr/bin/env bash
# RÉSULTATS-BF — bdd1 : base primaire (lecture/écriture).
# Provisionnement idempotent : rejoué deux fois de suite, il ne modifie
# rien, ne redémarre pas PostgreSQL et n'échoue pas (R2).

. /tmp/lib.sh

PG_MAJOR=16
CONF_D="/etc/postgresql/${PG_MAJOR}/main/conf.d"
HBA="/etc/postgresql/${PG_MAJOR}/main/pg_hba.conf"
changement=0

log "installation de PostgreSQL ${PG_MAJOR}"
apt_install postgresql postgresql-contrib

# Écoute sur l'adresse du réseau privé uniquement (R8 : le trafic interne ne
# quitte jamais le réseau privé). Fichier dédié dans conf.d : pas de guillemets
# à deviner, contenu entièrement maîtrisé.
if ecrire_si_different "${CONF_D}/resultats.conf" <<EOF
listen_addresses = '${IP}'
wal_level = replica
max_wal_senders = 5
EOF
then
  changement=1
fi

if ! grep -q '# resultats-bf' "$HBA"; then
  cat >> "$HBA" <<EOF
# resultats-bf — accès autorisés sur le réseau privé uniquement
host    ${DB_NAME}        ${DB_USER}        ${RESEAU}.0/24        scram-sha-256
host    replication       ${DB_REPL_USER}   ${RESEAU}.32/32       scram-sha-256
EOF
  changement=1
fi

systemctl enable postgresql
if [ "$changement" = 1 ]; then
  systemctl restart postgresql
elif ! pg_isready -q -h "$IP" -p 5432; then
  systemctl start postgresql
fi
attente 30 pg_isready -q -h "$IP" -p 5432

# Rôles et base : créés seulement s'ils n'existent pas ; mots de passe
# réappliqués à chaque fois (reste cohérent avec .env).
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_REPL_USER}') THEN
    CREATE ROLE ${DB_REPL_USER} LOGIN REPLICATION;
  END IF;
END
\$\$;
ALTER ROLE ${DB_USER} PASSWORD '${DB_PASSWORD}';
ALTER ROLE ${DB_REPL_USER} PASSWORD '${DB_REPL_PASSWORD}';
SQL

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
fi

log "jeu de données (50 000 lignes, déterministe, créé une seule fois)"
sudo -u postgres psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -q -f /tmp/schema.sql
sudo -u postgres psql -d "$DB_NAME" -q -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${DB_USER}"

log "bdd1 OK — matricule de test : 100001"
