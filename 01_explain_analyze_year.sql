-- =====================================================================
-- TP SQL Avancé — Partie A — Question 1 (2 pts)
-- EXPLAIN ANALYZE : 10 plus grosses commandes LIVREE de 2026,
-- écrite avec YEAR(date_commande) = 2026
-- Environnement : DataLab B2 (https://sql-avance.webdevoo.com/)
-- =====================================================================

EXPLAIN ANALYZE
SELECT *
FROM commandes
WHERE YEAR(date_commande) = 2026
  AND statut = 'LIVREE'
ORDER BY montant_total DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- Plan obtenu dans le DataLab (lecture des feuilles vers la racine)
--
--   Limit            Coût : 72.21..74.16   Lignes : 10   Temps : 8.53 ms
--   └─ Sort          Coût : 72.21..74.16   Lignes : 39   Tri sur montant_total DESC
--      └─ Seq Scan sur commandes
--                    Coût : 0..68.7        Lignes : 39   Buffers : 14 hit / 4 read
--                    Filtre : YEAR(date_commande) = 2026 AND statut = 'LIVREE'
--
--   Diagnostics affichés : "Prédicat non-SARGable détecté"
--                          "Utilisation de SELECT * détectée"
--   => Coût total AVANT optimisation : 74.16
-- ---------------------------------------------------------------------
--
-- DÉFAUT N°1 — Seq Scan complet causé par un prédicat NON-SARGable
--   La colonne date_commande est enveloppée dans la fonction YEAR().
--   Le moteur ne peut plus descendre dans un index B-Tree (qui est trié sur
--   la valeur brute de date_commande, pas sur YEAR(date_commande)) : il lit
--   les 240 lignes de commandes pour n'en garder que 39, soit plus de 80 %
--   de lectures inutiles. Sur une table de plusieurs millions de lignes,
--   cela devient un scan disque complet à chaque exécution.
--
-- DÉFAUT N°2 — Aucun index exploitable + SELECT * => tri coûteux en mémoire
--   Il n'existe aucun index sur (statut, date_commande) : toutes les lignes
--   candidates (39) remontent jusqu'au nœud Sort, qui doit les trier en
--   mémoire juste pour garder les 10 premières. Le SELECT * aggrave le
--   coût : il oblige à lire toutes les colonnes dans la table (heap) et
--   interdit tout Index Only Scan, même si un index existait.
--
-- => Corrections apportées dans 02_index_partition_sargable.sql
-- ---------------------------------------------------------------------
