-- =====================================================================
-- TP SQL Avancé — Partie B — Question 6 (2 pts)
-- WITH RECURSIVE : organigramme complet de employes depuis la CTO
-- (manager_id IS NULL), avec niveau hiérarchique et chemin complet
-- Environnement : DataLab B2 (https://sql-avance.webdevoo.com/)
-- =====================================================================

WITH RECURSIVE organigramme AS (
    -- 1. Terme d'ancrage : la CTO, sans manager (niveau 1)
    SELECT id, nom, poste, departement, manager_id,
           1                 AS niveau,
           CAST(nom AS TEXT) AS chemin   -- TEXT : le chemin s'allonge à chaque niveau
    FROM employes
    WHERE manager_id IS NULL

    UNION ALL

    -- 2. Terme récursif : les subordonnés directs des lignes déjà trouvées
    SELECT e.id, e.nom, e.poste, e.departement, e.manager_id,
           o.niveau + 1               AS niveau,
           o.chemin || ' > ' || e.nom AS chemin
    FROM employes e
    JOIN organigramme o ON e.manager_id = o.id
    WHERE o.niveau < 20               -- garde-fou contre une boucle infinie (cycle A->B->A)
)
SELECT id, nom, poste, departement, niveau, chemin
FROM organigramme
ORDER BY niveau ASC, id ASC;

-- ---------------------------------------------------------------------
-- Résultat obtenu (12 employés, 4 niveaux) :
--  id | nom             | niveau | chemin
--   1 | Claire Moreau   | 1 | Claire Moreau
--   2 | Marc Delacroix  | 2 | Claire Moreau > Marc Delacroix
--   3 | Sophie Vasseur  | 2 | Claire Moreau > Sophie Vasseur
--   4 | Antoine Renaud  | 3 | Claire Moreau > Marc Delacroix > Antoine Renaud
--   5 | Nadia Benali    | 3 | Claire Moreau > Marc Delacroix > Nadia Benali
--   6 | Julien Caron    | 3 | Claire Moreau > Marc Delacroix > Julien Caron
--   7 | Pauline Lefort  | 3 | Claire Moreau > Sophie Vasseur > Pauline Lefort
--   8 | Romain Fabre    | 3 | Claire Moreau > Sophie Vasseur > Romain Fabre
--   9 | Émilie Maillard | 4 | Claire Moreau > Marc Delacroix > Antoine Renaud > Émilie Maillard
--  10 | Bastien Royer   | 4 | Claire Moreau > Marc Delacroix > Antoine Renaud > Bastien Royer
--  11 | Kévin Giraud    | 4 | Claire Moreau > Marc Delacroix > Nadia Benali > Kévin Giraud
--  12 | Océane Simon    | 4 | Claire Moreau > Sophie Vasseur > Pauline Lefort > Océane Simon
--
-- Fonctionnement :
--   * L'ancrage produit la ligne de départ (Claire Moreau, niveau 1).
--   * À chaque tour, le terme récursif joint employes à la CTE pour trouver
--     les employés dont le manager a été trouvé au tour précédent, en
--     ajoutant 1 au niveau et en concaténant leur nom au chemin.
--   * La récursion s'arrête quand un tour ne produit plus aucune ligne.
--   * UNION ALL (et pas UNION) : pas de dédoublonnage inutile à chaque tour.
--   * CAST(nom AS TEXT) dans l'ancrage : sous PostgreSQL, le type de la
--     colonne chemin est fixé par l'ancrage ; en VARCHAR(80) la requête
--     échouerait dès que le chemin concaténé dépasse ce type.
-- ---------------------------------------------------------------------
