-- =====================================================================
-- TP SQL Avancé — Partie C — Question 7 (2 pts)
-- Le piège de NOT IN face aux valeurs NULL
-- Environnement : DataLab B2 (https://sql-avance.webdevoo.com/)
-- =====================================================================

-- 1. Requête piégée : elle cherche les employés qui ne managent personne
SELECT id, nom
FROM employes
WHERE id NOT IN (SELECT manager_id FROM employes);
-- => 0 ligne renvoyée, alors que 6 employés n'ont aucun subordonné !

-- ---------------------------------------------------------------------
-- EXPLICATION
--   La sous-requête renvoie la liste des manager_id :
--   (NULL, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 7)
--   Le NULL vient de la CTO Claire Moreau (manager_id IS NULL).
--
--   x NOT IN (a, b, NULL) est équivalent à :
--   x <> a AND x <> b AND x <> NULL
--
--   En logique ternaire SQL (TRUE / FALSE / UNKNOWN), toute comparaison
--   avec NULL vaut UNKNOWN. Donc pour un employé comme id = 6 :
--   6 <> 1 (TRUE) AND ... AND 6 <> NULL (UNKNOWN)  =>  UNKNOWN
--   Le WHERE ne garde que les lignes évaluées à TRUE : UNKNOWN est rejeté,
--   comme FALSE. Résultat : AUCUNE ligne n'est jamais retournée dès qu'un
--   seul NULL apparaît dans la sous-requête. C'est un bug silencieux :
--   pas d'erreur, juste un résultat faux.
-- ---------------------------------------------------------------------

-- 2. CORRECTION FIABLE (recommandée) : NOT EXISTS
--    NOT EXISTS teste seulement l'existence d'une ligne correspondante :
--    les NULL de manager_id ne produisent simplement aucune correspondance.
SELECT e.id, e.nom
FROM employes e
WHERE NOT EXISTS (
    SELECT 1
    FROM employes sub
    WHERE sub.manager_id = e.id
)
ORDER BY e.id;

-- Résultat obtenu (6 lignes) :
--    6 | Julien Caron
--    8 | Romain Fabre
--    9 | Émilie Maillard
--   10 | Bastien Royer
--   11 | Kévin Giraud
--   12 | Océane Simon

-- 3. Alternative équivalente : anti-jointure LEFT JOIN ... IS NULL
SELECT e.id, e.nom
FROM employes e
LEFT JOIN employes sub ON sub.manager_id = e.id
WHERE sub.id IS NULL
ORDER BY e.id;

-- 4. Si on tient à NOT IN : exclure explicitement les NULL
SELECT id, nom
FROM employes
WHERE id NOT IN (SELECT manager_id FROM employes WHERE manager_id IS NOT NULL)
ORDER BY id;

-- ---------------------------------------------------------------------
-- Les 3 corrections renvoient les mêmes 6 employés dans le DataLab.
-- NOT EXISTS est à privilégier : il reste juste même si une nouvelle
-- valeur NULL apparaît un jour, et l'optimiseur le transforme en
-- Hash Anti Join, efficace sur de gros volumes.
-- ---------------------------------------------------------------------
