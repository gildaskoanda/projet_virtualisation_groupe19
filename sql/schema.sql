-- RÉSULTATS-BF — schéma et jeu de données (exécuté sur bdd1).
-- Idempotent (R2) : rejoué, ce fichier ne modifie rien. La table n'est créée
-- et remplie que si elle n'existe pas / est vide ; un « vagrant provision »
-- ne coupe donc jamais le service et ne réécrit pas 50 000 lignes.
-- Le jeu est déterministe : deux reconstructions donnent les mêmes données.

CREATE TABLE IF NOT EXISTS resultats (
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
    100000 + g,
    'Candidat ' || lpad(g::text, 5, '0'),
    (ARRAY['A1','A2','B','C','D'])[1 + (g % 5)],
    round((g * 37 % 2000) / 100.0, 2),
    ((g * 37 % 2000) / 100.0) >= 10.0
FROM generate_series(1, 50000) AS g
WHERE NOT EXISTS (SELECT 1 FROM resultats);
