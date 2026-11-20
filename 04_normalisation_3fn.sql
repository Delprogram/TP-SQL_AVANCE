-- =====================================================================
-- TP SQL Avancé — Partie B — Question 4 (2 pts)
-- Passage en 3FN de la table brute
--   affectations_brutes(employe_id, employe_nom, dept_nom, projets_liste,
--                       chef_projet, chef_projet_tel)
-- ---------------------------------------------------------------------
-- NB : le simulateur DataLab n'exécute pas CREATE TABLE. Ce script est du
-- DDL PostgreSQL standard (testé sur PostgreSQL 16). Tout est créé dans un
-- schéma séparé "tp_3fn" pour ne pas toucher aux tables du DataLab.
-- =====================================================================

DROP SCHEMA IF EXISTS tp_3fn CASCADE;
CREATE SCHEMA tp_3fn;
SET search_path TO tp_3fn;

-- ---------------------------------------------------------------------
-- 0. La table brute (non normalisée) et un jeu d'exemple
--    Hypothèse : projets_liste contient plusieurs projets séparés par ", " ;
--    chef_projet et chef_projet_tel donnent, dans le même ordre, le chef
--    de chaque projet (export de tableur classique).
-- ---------------------------------------------------------------------
CREATE TABLE affectations_brutes (
    employe_id      INT,
    employe_nom     VARCHAR(80),
    dept_nom        VARCHAR(40),
    projets_liste   TEXT,
    chef_projet     TEXT,
    chef_projet_tel TEXT
);

INSERT INTO affectations_brutes VALUES
 (9,  'Émilie Maillard', 'Data',  'Migration PG16, Data Lake',  'Antoine Renaud, Nadia Benali', '0601020304, 0605060708'),
 (10, 'Bastien Royer',   'Data',  'Data Lake, Dashboard BI',    'Nadia Benali, Marc Delacroix', '0605060708, 0611121314'),
 (11, 'Kévin Giraud',    'Data',  'Data Lake',                  'Nadia Benali',                 '0605060708'),
 (12, 'Océane Simon',    'Infra', 'Refonte Datacenter Lyon',    'Pauline Lefort',               '0615161718'),
 (8,  'Romain Fabre',    'Infra', 'Refonte Datacenter Lyon, Migration PG16', 'Pauline Lefort, Antoine Renaud', '0615161718, 0601020304');

-- ---------------------------------------------------------------------
-- 1. ANALYSE : anomalies et dépendances fonctionnelles (DF)
--
--   Violation de la 1FN : projets_liste, chef_projet et chef_projet_tel
--   contiennent des listes (valeurs non atomiques). Impossible d'indexer
--   ou de joindre proprement un projet, de compter les employés par projet.
--
--   Après atomisation (1 ligne = 1 employé sur 1 projet), la clé candidate
--   de la relation est le couple (employe_id, projet).
--
--   Dépendances fonctionnelles :
--     DF1 : employe_id  -> employe_nom, dept_nom
--     DF2 : projet      -> chef_projet
--     DF3 : chef_projet -> chef_projet_tel
--     (donc projet -> chef_projet_tel, par transitivité)
--
--   Violation de la 2FN : DF1 et DF2 sont des dépendances PARTIELLES
--   (elles ne dépendent que d'une partie de la clé (employe_id, projet)).
--   => Anomalies : le nom d'un employé est répété sur chaque projet ;
--      renommer un projet ou changer de chef oblige à modifier N lignes.
--
--   Violation de la 3FN : DF3 est une dépendance TRANSITIVE
--   (projet -> chef_projet -> chef_projet_tel). Le téléphone d'un chef
--   est répété sur tous ses projets : risque d'incohérence à la mise à
--   jour, et on perd le téléphone si on supprime son dernier projet.
--   De même, dept_nom est une donnée texte répétée : on la sort dans une
--   table de référence departements.
--
-- 2. DÉCOMPOSITION EN 3FN
--
--   departements (id PK, nom UNIQUE)
--   employes     (id PK, nom, departement_id FK -> departements.id)        <- DF1
--   chefs_projet (id PK, nom, telephone)                                   <- DF3
--   projets      (id PK, nom UNIQUE, chef_projet_id FK -> chefs_projet.id) <- DF2
--   affectations (employe_id FK -> employes.id,
--                 projet_id  FK -> projets.id,
--                 PK (employe_id, projet_id))                              <- table d'association N-N
--
--   Chaque attribut non clé dépend de la clé, de toute la clé et de rien
--   d'autre que la clé : le schéma est en 3FN (et même en BCNF, chaque
--   déterminant étant une clé).
-- ---------------------------------------------------------------------

CREATE TABLE departements (
    id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE employes (
    id             INT PRIMARY KEY,
    nom            VARCHAR(80) NOT NULL,
    departement_id INT NOT NULL REFERENCES departements(id)
);

CREATE TABLE chefs_projet (
    id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom       VARCHAR(80) NOT NULL UNIQUE,
    telephone VARCHAR(20)
);

CREATE TABLE projets (
    id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom            VARCHAR(120) NOT NULL UNIQUE,
    chef_projet_id INT NOT NULL REFERENCES chefs_projet(id)
);

CREATE TABLE affectations (
    employe_id INT NOT NULL REFERENCES employes(id),
    projet_id  INT NOT NULL REFERENCES projets(id),
    PRIMARY KEY (employe_id, projet_id)
);

-- Index sur la FK non couverte par la PK (recherche "qui travaille sur le projet X")
CREATE INDEX idx_affectations_projet ON affectations (projet_id);

-- ---------------------------------------------------------------------
-- 3. MIGRATION des données brutes vers le modèle 3FN
-- ---------------------------------------------------------------------

-- 1FN : une ligne par (employé, projet, chef, téléphone)
CREATE TEMP VIEW v_1fn AS
SELECT b.employe_id,
       b.employe_nom,
       b.dept_nom,
       trim(x.projet) AS projet,
       trim(x.chef)   AS chef_projet,
       trim(x.tel)    AS chef_projet_tel
FROM affectations_brutes b
CROSS JOIN LATERAL unnest(string_to_array(b.projets_liste,   ','),
                          string_to_array(b.chef_projet,     ','),
                          string_to_array(b.chef_projet_tel, ',')) AS x(projet, chef, tel);

INSERT INTO departements (nom)
SELECT DISTINCT dept_nom FROM v_1fn;

INSERT INTO employes (id, nom, departement_id)
SELECT DISTINCT v.employe_id, v.employe_nom, d.id
FROM v_1fn v
JOIN departements d ON d.nom = v.dept_nom;

INSERT INTO chefs_projet (nom, telephone)
SELECT DISTINCT chef_projet, chef_projet_tel FROM v_1fn;

INSERT INTO projets (nom, chef_projet_id)
SELECT DISTINCT v.projet, cp.id
FROM v_1fn v
JOIN chefs_projet cp ON cp.nom = v.chef_projet;

INSERT INTO affectations (employe_id, projet_id)
SELECT DISTINCT v.employe_id, p.id
FROM v_1fn v
JOIN projets p ON p.nom = v.projet;

-- ---------------------------------------------------------------------
-- 4. CONTRÔLE : on reconstruit la vue métier d'origine par jointures
--    (aucune perte d'information : décomposition sans perte)
-- ---------------------------------------------------------------------
SELECT e.id   AS employe_id,
       e.nom  AS employe_nom,
       d.nom  AS dept_nom,
       p.nom  AS projet,
       cp.nom AS chef_projet,
       cp.telephone AS chef_projet_tel
FROM affectations a
JOIN employes     e  ON e.id  = a.employe_id
JOIN departements d  ON d.id  = e.departement_id
JOIN projets      p  ON p.id  = a.projet_id
JOIN chefs_projet cp ON cp.id = p.chef_projet_id
ORDER BY e.id, p.nom;

RESET search_path;
