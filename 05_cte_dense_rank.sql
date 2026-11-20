-- =====================================================================
-- TP SQL Avancé — Partie B — Question 5 (2 pts)
-- CTE + fonction de fenêtrage DENSE_RANK() :
-- les 2 produits les plus chers de chaque catégorie
-- Environnement : DataLab B2 (https://sql-avance.webdevoo.com/)
-- =====================================================================

WITH classement AS (
    SELECT cat.nom         AS categorie,
           p.nom           AS produit,
           p.prix_unitaire,
           DENSE_RANK() OVER (
               PARTITION BY p.categorie_id        -- une fenêtre par catégorie
               ORDER BY p.prix_unitaire DESC      -- du plus cher au moins cher
           ) AS rang_prix
    FROM produits p
    JOIN categories cat ON cat.id = p.categorie_id
)
SELECT categorie, produit, prix_unitaire, rang_prix
FROM classement
WHERE rang_prix <= 2
ORDER BY categorie ASC, rang_prix ASC;

-- ---------------------------------------------------------------------
-- Résultat obtenu (12 lignes = 6 catégories x 2 produits) :
--   categorie               | produit                        | prix  | rang
--   Accessoires Datacenter  | PDU Connecté 16A               |  310  | 1
--   Accessoires Datacenter  | Sonde Température SNMP         |  145  | 2
--   Licences & Cloud        | Licence SGBD Cluster 1 An      | 1800  | 1
--   Licences & Cloud        | Pack Monitoring APM            |  750  | 2
--   Périphériques Pro       | Écran 32" 4K Calibré           |  670  | 1
--   Périphériques Pro       | Station d'accueil Thunderbolt  |  245  | 2
--   Postes de travail       | Workstation GPU Dual           | 3890  | 1
--   Postes de travail       | Station Dev Ultra 64Go         | 2180  | 2
--   Réseau & Sécurité       | Pare-feu UTM Enterprise        | 1650  | 1
--   Réseau & Sécurité       | Switch L3 48 Ports PoE+        | 1120  | 2
--   Serveurs & Stockage     | Rack Serveur Xeon E24          | 2450  | 1
--   Serveurs & Stockage     | Baie NAS 12To Redondante       | 1390  | 2
--
-- Pourquoi DENSE_RANK() ?
--   * ROW_NUMBER() : 1, 2, 3, 4 -> en cas d'égalité de prix, un produit
--     ex-aequo serait arbitrairement exclu du top 2.
--   * RANK()       : 1, 2, 2, 4 -> crée des trous après les ex-aequo.
--   * DENSE_RANK() : 1, 2, 2, 3 -> rangs contigus : on garde les 2 niveaux
--     de prix les plus élevés, ex-aequo compris. Idéal pour un "Top N".
-- Le filtre rang_prix <= 2 doit être appliqué hors de la CTE : une fonction
-- de fenêtrage est calculée après le WHERE, on ne peut donc pas la filtrer
-- dans le même SELECT.
-- Coût : O(N log N), tri de chaque partition (nœud WindowAgg + Sort).
-- ---------------------------------------------------------------------
