-- =====================================================================
-- TP SQL Avancé — Partie A — Question 2 (2.5 pts)
-- Index pertinent + partitionnement RANGE + réécriture SARGable
-- (sans SELECT *), comparaison des coûts et Partition Pruning
-- Environnement : DataLab B2 (https://sql-avance.webdevoo.com/)
-- =====================================================================

-- ---------------------------------------------------------------------
-- ÉTAPE 1 — Index pertinent sur commandes
--   * statut en 1re colonne : filtre d'égalité (règle du préfixe gauche)
--   * date_commande en 2e colonne : filtre d'intervalle
--   * INCLUDE (id, client_id, montant_total) : index couvrant, toutes les
--     colonnes du SELECT sont dans l'index => Index Only Scan, la table
--     (heap) n'est plus lue du tout
-- ---------------------------------------------------------------------
CREATE INDEX idx_cmd_statut_date
    ON commandes (statut, date_commande)
    INCLUDE (id, client_id, montant_total);

-- ---------------------------------------------------------------------
-- ÉTAPE 2 — Activer le partitionnement RANGE de commandes
--   Dans le DataLab : panneau "Index et partitionnement"
--   > "Partitionnement RANGE (commandes)" > bouton "Activer"
--   (le simulateur ne gère pas le DDL de partitionnement).
--
--   Équivalent PostgreSQL de ce que fait le bouton :
--
--   CREATE TABLE commandes_part (
--       id            INT           NOT NULL,
--       client_id     INT           NOT NULL REFERENCES clients(id),
--       date_commande DATE          NOT NULL,
--       statut        VARCHAR(20)   NOT NULL,
--       canal         VARCHAR(20),
--       montant_total NUMERIC(10,2) NOT NULL,
--       PRIMARY KEY (id, date_commande)   -- la clé de partition doit être dans la PK
--   ) PARTITION BY RANGE (date_commande);
--
--   CREATE TABLE commandes_2024 PARTITION OF commandes_part
--       FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
--   CREATE TABLE commandes_2025 PARTITION OF commandes_part
--       FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
--   CREATE TABLE commandes_2026 PARTITION OF commandes_part
--       FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
--
--   INSERT INTO commandes_part SELECT id, client_id, date_commande, statut,
--          canal, montant_total FROM commandes;
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- ÉTAPE 3 — Requête réécrite : SARGable, colonnes explicites
--   YEAR(date_commande) = 2026
--   ==> date_commande >= '2026-01-01' AND date_commande < '2027-01-01'
--   (intervalle semi-ouvert : inclut tout le 31/12, même avec une heure)
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT id, client_id, date_commande, montant_total
FROM commandes
WHERE statut = 'LIVREE'
  AND date_commande >= '2026-01-01'
  AND date_commande <  '2027-01-01'
ORDER BY montant_total DESC
LIMIT 10;

-- =====================================================================
-- COMPARAISON DU COÛT TOTAL (relevés dans le DataLab, nœud racine Limit)
--
-- | Version                                   | Nœud d'accès                         | Coût total | Buffers         | Temps   |
-- |-------------------------------------------|--------------------------------------|------------|-----------------|---------|
-- | AVANT : SELECT * + YEAR() (Q1)            | Seq Scan commandes (240 lignes)      | 74.16      | 14 hit / 4 read | 8.53 ms |
-- | SARGable seule, sans index                | Seq Scan commandes (240 lignes)      | 74.16      | 14 hit / 4 read | 8.53 ms |
-- | SARGable + index couvrant                 | Index Only Scan idx_cmd_statut_date  | 12.46      | 2 hit / 0 read  | 0.64 ms |
-- | SARGable + index + partitionnement RANGE  | Partition Pruning : commandes_2026   | 11.11      | 2 hit / 0 read  | 0.64 ms |
--
-- Bilan : le coût passe de 74.16 à 11.11, soit environ 6,7 fois moins.
--  * La réécriture SARGable seule ne suffit pas : sans index, le moteur
--    reste en Seq Scan. Elle rend en revanche l'index utilisable.
--  * L'index composite couvrant fait passer en Index Only Scan : le moteur
--    lit directement les entrées 'LIVREE' de 2026 dans le B-Tree, sans
--    toucher la table (0 read disque).
--  * Le partitionnement réduit encore le coût du scan (7 -> 5.65) car seul
--    le tiroir 2026 est parcouru.
--
-- EFFET DU PARTITION PRUNING (élagage de partitions)
--   La table commandes est découpée en 3 partitions physiques par
--   intervalle de date : commandes_2024, commandes_2025, commandes_2026.
--   Chaque partition porte ses bornes (FOR VALUES FROM ... TO ...).
--   Au moment de planifier, l'optimiseur compare le prédicat
--   date_commande >= '2026-01-01' AND date_commande < '2027-01-01'
--   à ces bornes : commandes_2024 et commandes_2025 ne peuvent contenir
--   aucune ligne correspondante, elles sont retirées du plan avant toute
--   lecture. Le DataLab affiche "Partitions scannées : commandes_2026 (1/3)".
--   => 2/3 des données (66 %) sont ignorées sans être lues.
--   Condition : le filtre doit porter directement sur la clé de partition.
--   Dans un vrai PostgreSQL, YEAR(date_commande) / EXTRACT(...) masque la
--   clé et empêche l'élagage : toutes les partitions seraient scannées.
--   Bonus : l'archivage devient un simple DROP TABLE commandes_2024,
--   instantané, au lieu d'un DELETE massif.
-- =====================================================================
