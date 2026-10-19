-- RÉSULTATS-BF — schéma et jeu de données (exécuté sur bdd1).
-- Idempotent : la table est recréée à l'identique à chaque provisionnement.
-- Le jeu est déterministe pour que deux provisionnements successifs
-- produisent des données strictement identiques (R2).

DROP TABLE IF EXISTS resultats;

CREATE TABLE resultats (
    matricule BIGINT PRIMARY KEY,
    nom       TEXT    NOT NULL,
    serie     TEXT    NOT NULL,
    moyenne   NUMERIC(4,2) NOT NULL CHECK (moyenne >= 0 AND moyenne <= 20),
    admis     BOOLEAN NOT NULL
);

-- 50 000 lignes engendrées : volume suffisant pour que les mesures
-- de charge veuillent dire quelque chose.
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT
    100000 + g AS matricule,
    ('Candidat ' || lpad(g::text, 5, '0')) AS nom,
    (ARRAY['A1','A2','B','C','D'])[1 + (g % 5)] AS serie,
    round((g * 37 % 2000) / 100.0, 2) AS moyenne,
    ((g * 37 % 2000) / 100.0) >= 10.0 AS admis
FROM generate_series(1, 50000) AS g;
