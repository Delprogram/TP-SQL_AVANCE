-- =====================================================================
-- TP SQL Avancé — Partie C — Question 9 (3 pts)
-- Architecture polyglotte pour une application de covoiturage temps réel
--   (a) suivi GPS toutes les 3 s de 30 000 véhicules
--   (b) facturation bancaire des trajets
--   (c) suggestion d'itinéraires / amis communs à 3 degrés de séparation
-- Justification par CAP / PACELC et les 4 critères de choix :
--   cohérence, scalabilité, structure des données, nature des accès
-- =====================================================================

-- ---------------------------------------------------------------------
-- VUE D'ENSEMBLE
--
--   App mobile / API
--     |-- positions GPS ------> Cassandra (colonnes larges)  PA/EL
--     |                            '--> Redis : dernière position (carte live)
--     |-- paiement trajet ----> PostgreSQL (relationnel ACID)  PC/EC
--     '-- suggestions --------> Neo4j (graphe)  alimenté par événements
--                                (trajet terminé, ami ajouté)
--   Les bases communiquent par événements asynchrones (file de messages) :
--   aucune transaction distribuée entre elles. Seule la facturation exige
--   une cohérence stricte.
-- ---------------------------------------------------------------------

-- =====================================================================
-- (a) SUIVI GPS => Apache Cassandra (Colonnes larges) — profil PA / EL
-- =====================================================================
-- Volume : 30 000 véhicules / 3 s = 10 000 écritures par seconde en continu,
-- soit environ 864 millions de points par jour.
--
-- 1. Cohérence : faible exigence. Une position en retard de 1 à 2 s ou
--    perdue est remplacée 3 s plus tard par la suivante : la cohérence
--    éventuelle suffit.
-- 2. Scalabilité : écriture massive et continue => sharding horizontal
--    linéaire (on ajoute des nœuds), écriture append-only (LSM-Tree),
--    aucun maître unique qui serait un goulot.
-- 3. Structure : série temporelle simple et figée (vehicule, horodatage,
--    lat, lon, vitesse).
-- 4. Accès : toujours par clé connue ("trace du véhicule V aujourd'hui",
--    ordre chronologique), jamais de requête ad hoc.
-- CAP/PACELC : PA/EL. En cas de partition réseau, on continue d'accepter
-- les positions (A) ; en temps normal on privilégie la latence (L,
-- consistency level ONE) plutôt qu'une confirmation par tous les réplicas.
-- PostgreSQL (PC/EC, maître unique) saturerait en écriture.
--
-- Modélisation CQL (1 table = 1 requête, partition bornée par jour) :
--   CREATE TABLE positions_par_vehicule (
--       vehicule_id UUID,
--       jour        DATE,
--       ts          TIMESTAMP,
--       lat DOUBLE, lon DOUBLE, vitesse_kmh FLOAT,
--       PRIMARY KEY ((vehicule_id, jour), ts)   -- partition key + clustering key
--   ) WITH CLUSTERING ORDER BY (ts DESC)
--     AND default_time_to_live = 2592000;     -- purge auto après 30 jours
--
-- Complément : Redis (clé-valeur en RAM, AP/EL) pour la dernière position
-- de chaque véhicule (SET vehicule:V:pos ... EX 10 + index GEO pour
-- "véhicules à moins de 2 km"), lue en O(1) par la carte temps réel.

-- =====================================================================
-- (b) FACTURATION BANCAIRE => PostgreSQL (Relationnel ACID) — profil PC / EC
-- =====================================================================
-- 1. Cohérence : stricte, zéro erreur tolérée. Débit passager + crédit
--    conducteur + commission doivent être atomiques : transactions ACID,
--    contraintes CHECK / FK, isolation SERIALIZABLE ou verrou
--    SELECT ... FOR UPDATE pour éviter double paiement ou solde négatif.
-- 2. Scalabilité : volume modéré (1 facture par trajet, pas 10 000/s) :
--    montée en charge verticale + réplicas en lecture suffisent.
-- 3. Structure : schéma stable et relationnel (utilisateurs, trajets,
--    paiements, factures) avec intégrité référentielle.
-- 4. Accès : requêtes analytiques imprévisibles (CA par mois, litiges,
--    rapprochement bancaire, audit) => SQL et ses jointures.
-- CAP/PACELC : PC/EC. En cas de partition, on préfère refuser un paiement
-- (indisponibilité temporaire) plutôt que de débiter deux fois ;
-- en temps normal, réplication synchrone avant de valider (C > L).
-- Le WAL garantit l'atomicité et la durabilité en cas de panne (cf. Q8).

CREATE TABLE IF NOT EXISTS factures_trajets (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trajet_id        BIGINT        NOT NULL UNIQUE,         -- 1 facture par trajet : pas de double facturation
    passager_id      BIGINT        NOT NULL,
    conducteur_id    BIGINT        NOT NULL,
    montant_ttc      NUMERIC(10,2) NOT NULL CHECK (montant_ttc > 0),
    commission       NUMERIC(10,2) NOT NULL CHECK (commission >= 0),
    statut           VARCHAR(20)   NOT NULL DEFAULT 'EN_ATTENTE'
                     CHECK (statut IN ('EN_ATTENTE', 'PAYEE', 'REMBOURSEE', 'ECHEC')),
    date_facturation TIMESTAMPTZ   NOT NULL DEFAULT now()
);
-- (DDL PostgreSQL donné à titre d'illustration : le simulateur DataLab
--  n'exécute pas CREATE TABLE.)
--
-- Paiement d'un trajet = une seule transaction :
--   BEGIN ISOLATION LEVEL SERIALIZABLE;
--     UPDATE portefeuilles SET solde = solde - 18.50 WHERE user_id = :passager;   -- CHECK solde >= 0
--     UPDATE portefeuilles SET solde = solde + 15.50 WHERE user_id = :conducteur;
--     INSERT INTO factures_trajets (trajet_id, passager_id, conducteur_id, montant_ttc, commission, statut)
--     VALUES (:trajet, :passager, :conducteur, 18.50, 3.00, 'PAYEE');
--   COMMIT;

-- =====================================================================
-- (c) AMIS COMMUNS / ITINÉRAIRES À 3 DEGRÉS => Neo4j (Graphe)
-- =====================================================================
-- 1. Cohérence : modérée. Une suggestion calculée avec quelques secondes
--    de retard n'a aucune conséquence ; le graphe est alimenté de façon
--    asynchrone par les événements (trajet terminé, ami ajouté).
-- 2. Scalabilité : surtout en lecture (suggestions très fréquentes) =>
--    cluster causal Neo4j avec réplicas en lecture.
-- 3. Structure : réseau relationnel profond :
--    (:Utilisateur)-[:AMI]->(:Utilisateur),
--    (:Utilisateur)-[:A_PARTAGE]->(:Trajet)-[:PASSE_PAR]->(:Lieu)
-- 4. Accès : parcours multi-sauts (3 degrés). En SQL, cela exige 3
--    auto-jointures ou une CTE récursive dont le coût explose avec le
--    nombre d'amis (N^3). Neo4j suit directement les pointeurs entre
--    nœuds (index-free adjacency) : le coût dépend du voisinage exploré,
--    pas de la taille totale de la base.
-- CAP/PACELC : Neo4j en cluster écrit via un leader (Raft) => plutôt
-- PC/EC en écriture, avec des réplicas de lecture à cohérence causale
-- (lecture rapide, éventuellement légèrement en retard).
--
-- Exemple Cypher : amis jusqu'à 3 degrés non encore connectés, classés
-- par nombre de chemins communs :
--   MATCH (moi:Utilisateur {id: $id})-[:AMI*2..3]-(suggere:Utilisateur)
--   WHERE suggere <> moi AND NOT (moi)-[:AMI]-(suggere)
--   RETURN suggere.nom, count(*) AS liens_communs
--   ORDER BY liens_communs DESC
--   LIMIT 10;

-- =====================================================================
-- SYNTHÈSE
--
-- | Besoin                | Moteur              | Famille        | PACELC        | Critère décisif                              |
-- |-----------------------|---------------------|----------------|---------------|----------------------------------------------|
-- | (a) GPS 10 000 écr./s | Cassandra (+ Redis) | Colonnes larges| PA / EL       | Scalabilité en écriture, accès par clé+temps |
-- | (b) Facturation       | PostgreSQL          | Relationnel    | PC / EC       | Cohérence ACID stricte, intégrité            |
-- | (c) Amis à 3 degrés   | Neo4j               | Graphe         | PC/EC (+ lectures causales) | Structure en réseau, parcours multi-sauts |
--
-- Le théorème CAP impose de choisir entre C et A en cas de partition
-- réseau : on ne fait donc pas porter la même exigence à toutes les
-- données. Seul l'argent exige C ; la télémétrie GPS privilégie A et la
-- latence. Une base unique serait soit trop lente pour le GPS (PostgreSQL),
-- soit trop permissive pour l'argent (Cassandra) : l'architecture
-- polyglotte utilise chaque moteur pour ce qu'il fait de mieux.
-- =====================================================================
