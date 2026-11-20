# A corriger

# TP SQL Avancé — DataLab B2

**Nom :** AHOUANHOU
**Prénom :** Fidel

Bachelor Développeur Web Fullstack — CODA Orléans, 2e année
Rendu du vendredi 20 novembre 2026

## Environnement

Les requêtes ont été exécutées dans l'environnement local **DataLab B2** (https://sql-avance.webdevoo.com/, base `datalab_b2` en IndexedDB, syntaxe PostgreSQL).
Les résultats et les plans d'exécution obtenus sont recopiés en commentaire dans chaque script.

## Livrables : un script par question

| Fichier | Question | Points |
|---|---|---|
| `01_explain_analyze_year.sql` | Q1 — EXPLAIN ANALYZE avec `YEAR(date_commande) = 2026`, les 2 défauts du plan | 2 |
| `02_index_partition_sargable.sql` | Q2 — Index couvrant, partitionnement RANGE, réécriture SARGable, comparaison des coûts, Partition Pruning | 2.5 |
| `03_vue_materialisee_segments.sql` | Q3 — Vue matérialisée `mv_synthese_segments`, commande test, état *stale*, `REFRESH` | 2.5 |
| `04_normalisation_3fn.sql` | Q4 — `affectations_brutes` en 3FN : dépendances fonctionnelles, PK/FK, migration des données | 2 |
| `05_cte_dense_rank.sql` | Q5 — CTE + `DENSE_RANK()` : top 2 des produits les plus chers par catégorie | 2 |
| `06_with_recursive_organigramme.sql` | Q6 — `WITH RECURSIVE` : organigramme depuis la CTO avec `niveau` et `chemin` | 2 |
| `07_piege_not_in_null.sql` | Q7 — Piège `NOT IN` avec `NULL`, corrections `NOT EXISTS` / `LEFT JOIN` | 2 |
| `08_transactions_acid_wal.sql` | Q8 — Non-Repeatable Read (READ COMMITTED vs REPEATABLE READ), rôle du WAL | 2 |
| `09_architecture_polyglotte.sql` | Q9 — Architecture polyglotte covoiturage (CAP / PACELC, 4 critères) | 3 |

## Résultats clés

- **Q2 :** coût total du plan passé de **74.16** (Seq Scan sur 240 lignes) à **11.11** (Index Only Scan + Partition Pruning sur `commandes_2026` seule, 1/3), soit environ 6,7 fois moins.
- **Q3 :** après l'insertion de la commande test, la vue passe à *Obsolète* ; après `REFRESH`, le segment PME passe de 70 à 71 commandes (+4 890 €).
- **Q7 :** la requête `NOT IN` renvoie 0 ligne ; `NOT EXISTS` renvoie les 6 employés qui ne managent personne.

## Remarques

- Le simulateur DataLab n'exécute pas `CREATE TABLE`, `BEGIN` ni `COMMIT`. Les scripts 04, 08 et 09 contiennent donc du SQL PostgreSQL standard (le script 04 a été testé sur PostgreSQL 16). La question 8 a été réalisée dans le simulateur ACID du module 06, et les observations sont reportées dans le script.
- Le partitionnement RANGE s'active dans le DataLab avec le bouton **Activer** du panneau « Index et partitionnement ». Le DDL PostgreSQL équivalent figure en commentaire dans le script 02.
