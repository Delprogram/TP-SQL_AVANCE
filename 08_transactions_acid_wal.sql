-- =====================================================================
-- TP SQL Avancé — Partie C — Question 8 (2 pts)
-- Non-Repeatable Read sous READ COMMITTED, résolution par REPEATABLE READ,
-- rôle du WAL lors d'une coupure serveur en plein virement
-- ---------------------------------------------------------------------
-- Dans le DataLab : Module 06 "Transactions ACID" > "Simulateur ACID,
-- niveaux d'isolation et WAL". Le simulateur rejoue les deux sessions
-- concurrentes ci-dessous (Session A = T1, Session B = T2).
-- Les blocs SQL sont écrits en PostgreSQL : pour les rejouer à la main,
-- ouvrir 2 terminaux psql et exécuter les étapes dans l'ordre indiqué.
-- =====================================================================


-- #####################################################################
-- PARTIE 1 — Reproduire le NON-REPEATABLE READ sous READ COMMITTED
-- Simulateur : Niveau d'isolation = "READ COMMITTED (défaut PG)"
--              Scénario = "Anomalie : non-repeatable read"
--              puis "Exécuter étape" 3 fois
-- #####################################################################

-- [Étape 1] SESSION A (T1)
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT solde FROM comptes_bancaires WHERE id = 1;     -- -> 15 000 €

-- [Étape 2] SESSION B (T2) — modifie la même ligne et valide
BEGIN;
UPDATE comptes_bancaires SET solde = 14000 WHERE id = 1;
COMMIT;
-- WAL : [0/3090] T2 · COMMIT : HexaTech : 15000 -> 14000  (COMMITTED)

-- [Étape 3] SESSION A (T1) — relit la même ligne dans la même transaction
SELECT solde FROM comptes_bancaires WHERE id = 1;     -- -> 14 000 € !
COMMIT;

-- Constat dans le simulateur :
--   "Même requête SELECT solde WHERE id = 1; -> renvoie maintenant 14 000 €
--    (non-repeatable read)"
-- Explication : en READ COMMITTED, PostgreSQL prend un NOUVEAU snapshot
-- MVCC au début de CHAQUE instruction. Le 2e SELECT de T1 voit donc le
-- COMMIT de T2 survenu entre-temps : la même lecture, dans la même
-- transaction, donne deux résultats différents. Pas de lecture sale ici
-- (T2 avait bien validé), mais la transaction T1 n'est plus cohérente
-- avec elle-même (ex. : un contrôle de solde puis un débit calculé sur
-- une valeur qui a changé).


-- #####################################################################
-- PARTIE 2 — REPEATABLE READ résout l'anomalie
-- Simulateur : Niveau d'isolation = "REPEATABLE READ"
--              même scénario, "Réinitialiser" puis "Exécuter étape" 3 fois
-- (Remettre d'abord le solde : UPDATE comptes_bancaires SET solde = 15000 WHERE id = 1;)
-- #####################################################################

-- [Étape 1] SESSION A (T1)
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT solde FROM comptes_bancaires WHERE id = 1;     -- -> 15 000 €

-- [Étape 2] SESSION B (T2)
BEGIN;
UPDATE comptes_bancaires SET solde = 14000 WHERE id = 1;
COMMIT;

-- [Étape 3] SESSION A (T1)
SELECT solde FROM comptes_bancaires WHERE id = 1;     -- -> toujours 15 000 €
COMMIT;
-- Après le COMMIT de T1, une nouvelle transaction verra bien 14 000 €.

-- Constat dans le simulateur :
--   "Snapshot MVCC (REPEATABLE READ) : renvoie toujours 15 000 € de
--    manière cohérente."
-- Explication : en REPEATABLE READ, le snapshot MVCC est figé à la
-- première instruction de la transaction et réutilisé jusqu'au COMMIT.
-- T1 lit les anciennes versions des lignes (MVCC conserve plusieurs
-- versions), sans bloquer T2 : les lectures sont répétables.
-- Contrepartie : si T1 tentait elle aussi un UPDATE de la ligne id = 1,
-- PostgreSQL lèverait "could not serialize access due to concurrent
-- update" ; l'application doit alors rejouer la transaction.
--
--   Niveau            | Dirty read | Non-repeatable read | Phantom read
--   READ COMMITTED    | protégé    | POSSIBLE            | possible
--   REPEATABLE READ   | protégé    | protégé             | protégé (MVCC PG)
--   SERIALIZABLE      | protégé    | protégé             | protégé (+ write skew)


-- #####################################################################
-- PARTIE 3 — Rôle du WAL lors d'une coupure serveur en plein virement
-- Simulateur : Scénario "Virement atomique et panne WAL",
--              "Exécuter étape" 1 fois puis "Simuler coupure serveur"
-- #####################################################################

-- Virement de 2 000 € de HexaTech (id 1) vers NovaLab (id 2)
BEGIN;
UPDATE comptes_bancaires SET solde = solde - 2000 WHERE id = 1;   -- débit
-- >>> COUPURE SERVEUR ICI (avant le crédit et avant le COMMIT) <<<
UPDATE comptes_bancaires SET solde = solde + 2000 WHERE id = 2;   -- crédit
COMMIT;

-- Constat dans le simulateur :
--   Avant la panne : WAL [0/104A] T1 · UPDATE : HexaTech 15000 -> 13000
--   (non validé, PENDING) ; somme des comptes = 21 400 € (incohérente).
--   Après la panne : "les écritures non commitées ont été annulées par le
--   WAL (atomicité)" ; l'entrée passe en [UNDO WAL] ROLLED_BACK,
--   HexaTech revient à 15 000 €, somme = 23 400 € : invariant préservé.
--
-- Fonctionnement du WAL (Write-Ahead Log, journal écrit AVANT les données) :
--   1. Toute modification est d'abord écrite séquentiellement dans le WAL,
--      avec son identifiant de transaction (LSN, ex. 0/104A), avant que
--      les pages de la table ne soient modifiées sur disque.
--   2. Au COMMIT, l'enregistrement de validation est forcé sur disque
--      (fsync) : c'est seulement à ce moment que le client reçoit "OK".
--   3. Au redémarrage après la coupure, PostgreSQL relit le WAL depuis le
--      dernier checkpoint (crash recovery) :
--      - transaction NON validée (notre virement interrompu) : ses
--        modifications sont ignorées / annulées (UNDO) => ATOMICITÉ,
--        "tout ou rien" : ni débit seul, ni argent perdu ;
--      - transaction VALIDÉE dont les pages n'étaient pas encore écrites
--        sur disque : ses modifications sont rejouées (REDO) => DURABILITÉ,
--        un COMMIT acquitté survit à la panne.
--   (Dans PostgreSQL l'annulation passe par MVCC : les versions créées par
--   une transaction jamais validée restent invisibles.)
