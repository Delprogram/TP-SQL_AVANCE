-- =====================================================================
-- TP SQL Avancé — Partie A — Question 3 (2.5 pts)
-- Vue matérialisée mv_synthese_segments : nombre de commandes et CA total
-- par segment client ; insertion test, état obsolète (stale), REFRESH
-- Environnement : DataLab B2 (https://sql-avance.webdevoo.com/)
-- Exécuter les blocs dans l'ordre.
-- =====================================================================

-- 1. Création de la vue matérialisée (résultat calculé et stocké)
CREATE MATERIALIZED VIEW mv_synthese_segments AS
SELECT c.segment,
       COUNT(cmd.id)                    AS nb_commandes,
       ROUND(SUM(cmd.montant_total), 2) AS ca_total
FROM commandes cmd
JOIN clients c ON c.id = cmd.client_id
GROUP BY c.segment;

-- 2. Lecture de la vue (état initial)
SELECT segment, nb_commandes, ca_total
FROM mv_synthese_segments
ORDER BY segment;
-- Résultat obtenu :
--   segment       | nb_commandes | ca_total
--   Entreprise    | 70           | 314081.8
--   Grand Compte  | 60           | 322058.2
--   PME           | 70           | 325875.7
--   Startup       | 40           |  97458.9
--   Panneau "Vues matérialisées" : mv_synthese_segments "À jour (4 lig.)"

-- 3. Insertion d'une commande test (cliente n°3 Inès Bernard, segment PME)
INSERT INTO commandes (client_id, date_commande, statut, canal, montant_total)
VALUES (3, '2026-11-20', 'LIVREE', 'WEB', 4890.00);
-- => "1 ligne insérée dans commandes" (id attribué : 241)

-- 4. Constat : la vue est marquée obsolète (stale)
SELECT segment, nb_commandes, ca_total
FROM mv_synthese_segments
ORDER BY segment;
-- => Avertissement du DataLab : Vue matérialisée "mv_synthese_segments"
--    obsolète (stale). "Des écritures ont eu lieu depuis le dernier
--    rafraîchissement." Le panneau affiche "Obsolète".
--    La vue renvoie toujours PME | 70 | 325875.7 : la photo est figée,
--    la commande test n'y apparaît pas.

-- 4 bis. Preuve : la même agrégation calculée en direct sur les tables
SELECT c.segment,
       COUNT(cmd.id)                    AS nb_commandes,
       ROUND(SUM(cmd.montant_total), 2) AS ca_total
FROM commandes cmd
JOIN clients c ON c.id = cmd.client_id
GROUP BY c.segment
ORDER BY c.segment;
-- => PME | 71 | 330765.7 (écart de 1 commande et de 4 890 € avec la vue)

-- 5. Rafraîchissement de la vue
REFRESH MATERIALIZED VIEW mv_synthese_segments;
-- => "Vue matérialisée mv_synthese_segments rafraîchie (4 lignes)"
--    Le panneau repasse à "À jour (4 lig.)"

-- 6. Vérification de la mise à jour
SELECT segment, nb_commandes, ca_total
FROM mv_synthese_segments
ORDER BY segment;
-- Résultat obtenu :
--   Entreprise    | 70 | 314081.8
--   Grand Compte  | 60 | 322058.2
--   PME           | 71 | 330765.7   <- +1 commande, +4 890 €
--   Startup       | 40 |  97458.9

-- ---------------------------------------------------------------------
-- Explication
--   Une vue matérialisée stocke physiquement le résultat de sa requête :
--   la lecture est quasi instantanée (pas de jointure ni d'agrégation à
--   refaire), mais les données restent figées au dernier REFRESH. Toute
--   écriture (INSERT / UPDATE / DELETE) sur une table source rend la vue
--   obsolète tant qu'on ne relance pas REFRESH MATERIALIZED VIEW.
--   En production on planifie ce REFRESH (toutes les heures, la nuit), et
--   sous PostgreSQL on utilise REFRESH MATERIALIZED VIEW CONCURRENTLY
--   (avec un index UNIQUE sur segment) pour ne pas bloquer les lectures.
--
-- Nettoyage facultatif (supprime la commande test, puis resynchronise) :
-- DELETE FROM commandes WHERE id = 241;
-- REFRESH MATERIALIZED VIEW mv_synthese_segments;
-- ---------------------------------------------------------------------
