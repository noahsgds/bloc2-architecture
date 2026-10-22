-- Modèle de données de la plateforme Sentinel.
-- Exécuté une seule fois, à la création de la base (dossier docker-entrypoint-initdb.d).
--
-- Trois schémas, un par usage :
--   operationnel : les données vivantes, écrites par le pipeline (bloc 3) et l'API (bloc 4) ;
--   entrepot     : le modèle en étoile pour l'analyse et les tableaux de bord ;
--   supervision  : l'état de la plateforme (sauvegardes, demandes RGPD).

CREATE SCHEMA operationnel;
CREATE SCHEMA entrepot;
CREATE SCHEMA supervision;

-- ===========================================================================================
-- 1. Données opérationnelles
-- ===========================================================================================

-- Données SEMI-STRUCTURÉES : événements bruts des serveurs de jeu, au format JSON (JSONB).
-- Leur structure peut évoluer (nouveau champ) sans modifier la table. Conservés 30 jours.
CREATE TABLE operationnel.evenements_bruts (
    id        BIGSERIAL PRIMARY KEY,
    fichier   TEXT        NOT NULL,
    recu_le   TIMESTAMPTZ NOT NULL DEFAULT now(),
    contenu   JSONB       NOT NULL
);

-- Données STRUCTURÉES : une fiche = un joueur sur un match (contrat de données de Sentinel).
CREATE TABLE operationnel.fiches (
    player_id                  UUID     NOT NULL,   -- identifiant pseudonyme
    match_id                   UUID     NOT NULL,
    match_date                 DATE     NOT NULL,
    accuracy                   REAL     NOT NULL CHECK (accuracy BETWEEN 0 AND 1),
    headshot_rate              REAL     NOT NULL CHECK (headshot_rate BETWEEN 0 AND 1),
    kd_ratio                   REAL     NOT NULL CHECK (kd_ratio >= 0),
    avg_reaction_ms            REAL,                -- peut manquer (télémétrie perdue)
    rank_tier                  SMALLINT NOT NULL CHECK (rank_tier BETWEEN 1 AND 8),
    reports_received           SMALLINT NOT NULL CHECK (reports_received >= 0),
    input_device               TEXT     NOT NULL CHECK (input_device IN ('clavier_souris', 'manette')),
    platform                   TEXT     NOT NULL CHECK (platform IN ('pc', 'console')),
    age_band                   TEXT     NOT NULL,   -- audit d'équité uniquement
    accessibility_mode         BOOLEAN  NOT NULL,   -- audit d'équité uniquement
    charge_le                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (player_id, match_id)
);

-- Versions du modèle d'IA (fiche technique du bloc 4).
CREATE TABLE operationnel.versions_modele (
    version     TEXT PRIMARY KEY,
    cree_le     TIMESTAMPTZ NOT NULL,
    pr_auc      REAL        NOT NULL,
    seuil       REAL        NOT NULL
);

-- Score de suspicion calculé par l'API Sentinel pour chaque fiche.
CREATE TABLE operationnel.predictions (
    id               BIGSERIAL PRIMARY KEY,
    player_id        UUID        NOT NULL,
    match_id         UUID        NOT NULL,
    suspicion_score  REAL        NOT NULL CHECK (suspicion_score BETWEEN 0 AND 1),
    flagged          BOOLEAN     NOT NULL,
    model_version    TEXT        NOT NULL REFERENCES operationnel.versions_modele (version),
    cree_le          TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (player_id, match_id) REFERENCES operationnel.fiches (player_id, match_id)
        ON DELETE CASCADE
);
CREATE INDEX ON operationnel.predictions (player_id);

-- Décision HUMAINE d'un modérateur (le modèle ne sanctionne jamais seul).
CREATE TABLE operationnel.decisions (
    id         BIGSERIAL PRIMARY KEY,
    player_id  UUID        NOT NULL,
    match_id   UUID        NOT NULL,
    decision   TEXT        NOT NULL CHECK (decision IN ('triche_confirmee', 'innocente', 'a_approfondir')),
    moderateur TEXT        NOT NULL,
    cree_le    TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (player_id, match_id) REFERENCES operationnel.fiches (player_id, match_id)
        ON DELETE CASCADE
);
CREATE INDEX ON operationnel.decisions (player_id);

-- ===========================================================================================
-- 2. Entrepôt : modèle en étoile (une table de faits entourée de dimensions)
-- ===========================================================================================
-- Pourquoi une étoile ? Les tableaux de bord posent toujours la même question : « combien,
-- par jour / par plateforme / par version du modèle ? ». Une table de faits au centre et
-- des dimensions autour rendent ces requêtes simples et rapides.

CREATE TABLE entrepot.dim_date (
    date_id       DATE PRIMARY KEY,
    annee         SMALLINT NOT NULL,
    mois          SMALLINT NOT NULL,
    semaine       SMALLINT NOT NULL,
    jour_semaine  TEXT     NOT NULL
);

CREATE TABLE entrepot.dim_appareil (
    appareil_id   SERIAL PRIMARY KEY,
    input_device  TEXT NOT NULL,
    platform      TEXT NOT NULL,
    UNIQUE (input_device, platform)
);

CREATE TABLE entrepot.dim_modele (
    version  TEXT PRIMARY KEY,
    cree_le  TIMESTAMPTZ NOT NULL,
    pr_auc   REAL        NOT NULL
);

CREATE TABLE entrepot.dim_rang (
    rank_tier  SMALLINT PRIMARY KEY,
    niveau     TEXT     NOT NULL      -- débutant, intermédiaire, confirmé, élite
);

-- Table de faits : une ligne par fiche analysée. Pas d'identifiant de joueur : l'entrepôt
-- sert aux statistiques, pas à suivre une personne (minimisation).
CREATE TABLE entrepot.fait_fiche (
    fiche_id          BIGSERIAL PRIMARY KEY,
    match_id          UUID     NOT NULL,
    date_id           DATE     NOT NULL REFERENCES entrepot.dim_date,
    appareil_id       INTEGER  NOT NULL REFERENCES entrepot.dim_appareil,
    rank_tier         SMALLINT NOT NULL REFERENCES entrepot.dim_rang,
    model_version     TEXT     REFERENCES entrepot.dim_modele,
    suspicion_score   REAL,
    signale           BOOLEAN,
    decision          TEXT,               -- NULL tant qu'aucun modérateur n'a statué
    reports_received  SMALLINT NOT NULL
);
CREATE INDEX ON entrepot.fait_fiche (date_id);

-- Remplit l'entrepôt à partir des données opérationnelles. Rejouable sans doublon.
CREATE FUNCTION entrepot.rafraichir() RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    nb INTEGER;
BEGIN
    INSERT INTO entrepot.dim_date
    SELECT DISTINCT match_date, extract(year FROM match_date), extract(month FROM match_date),
           extract(week FROM match_date), to_char(match_date, 'TMDay')
    FROM operationnel.fiches
    ON CONFLICT DO NOTHING;

    INSERT INTO entrepot.dim_appareil (input_device, platform)
    SELECT DISTINCT input_device, platform FROM operationnel.fiches
    ON CONFLICT DO NOTHING;

    INSERT INTO entrepot.dim_modele SELECT version, cree_le, pr_auc FROM operationnel.versions_modele
    ON CONFLICT DO NOTHING;

    TRUNCATE entrepot.fait_fiche;
    INSERT INTO entrepot.fait_fiche (match_id, date_id, appareil_id, rank_tier, model_version,
                                     suspicion_score, signale, decision, reports_received)
    SELECT f.match_id, f.match_date, a.appareil_id, f.rank_tier,
           p.model_version, p.suspicion_score, p.flagged, d.decision, f.reports_received
    FROM operationnel.fiches f
    JOIN entrepot.dim_appareil a USING (input_device, platform)
    LEFT JOIN LATERAL (SELECT * FROM operationnel.predictions p
                       WHERE p.player_id = f.player_id AND p.match_id = f.match_id
                       ORDER BY cree_le DESC LIMIT 1) p ON true
    LEFT JOIN LATERAL (SELECT * FROM operationnel.decisions d
                       WHERE d.player_id = f.player_id AND d.match_id = f.match_id
                       ORDER BY cree_le DESC LIMIT 1) d ON true;
    GET DIAGNOSTICS nb = ROW_COUNT;
    RETURN nb;
END $$;

INSERT INTO entrepot.dim_rang VALUES
    (1, 'débutant'), (2, 'débutant'), (3, 'intermédiaire'), (4, 'intermédiaire'),
    (5, 'confirmé'), (6, 'confirmé'), (7, 'élite'), (8, 'élite');

-- ===========================================================================================
-- 3. Supervision et RGPD
-- ===========================================================================================

-- Chaque sauvegarde est enregistrée : Grafana alerte si la dernière date de plus de 26 h.
CREATE TABLE supervision.sauvegardes (
    id         BIGSERIAL PRIMARY KEY,
    faite_le   TIMESTAMPTZ NOT NULL DEFAULT now(),
    fichier    TEXT        NOT NULL,
    taille_ko  INTEGER     NOT NULL
);

-- Registre des demandes RGPD (preuve que chaque demande a été traitée).
CREATE TABLE supervision.demandes_rgpd (
    id         BIGSERIAL PRIMARY KEY,
    faite_le   TIMESTAMPTZ NOT NULL DEFAULT now(),
    player_id  UUID        NOT NULL,
    type       TEXT        NOT NULL CHECK (type IN ('acces', 'effacement')),
    lignes     INTEGER     NOT NULL
);

-- Droit d'accès : toutes les données d'un joueur, en un seul document JSON.
CREATE FUNCTION supervision.droit_acces(joueur UUID) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
    resultat JSONB;
BEGIN
    SELECT jsonb_build_object(
        'player_id', joueur,
        'fiches', (SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]') FROM operationnel.fiches f WHERE player_id = joueur),
        'predictions', (SELECT coalesce(jsonb_agg(to_jsonb(p)), '[]') FROM operationnel.predictions p WHERE player_id = joueur),
        'decisions', (SELECT coalesce(jsonb_agg(to_jsonb(d)), '[]') FROM operationnel.decisions d WHERE player_id = joueur),
        'evenements_bruts', (SELECT coalesce(jsonb_agg(contenu), '[]') FROM operationnel.evenements_bruts WHERE contenu ->> 'player_id' = joueur::text)
    ) INTO resultat;
    INSERT INTO supervision.demandes_rgpd (player_id, type, lignes)
    VALUES (joueur, 'acces', jsonb_array_length(resultat -> 'fiches'));
    RETURN resultat;
END $$;

-- Droit à l'effacement : supprime le joueur de toute la base (les prédictions et décisions
-- suivent par ON DELETE CASCADE). L'entrepôt ne contient aucun identifiant de joueur.
-- Exception (art. 17.3.e) : une triche confirmée est conservée le temps de la contestation.
CREATE FUNCTION supervision.droit_effacement(joueur UUID) RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    nb INTEGER;
    nb_bruts INTEGER;
BEGIN
    IF EXISTS (SELECT 1 FROM operationnel.decisions
               WHERE player_id = joueur AND decision = 'triche_confirmee') THEN
        RAISE EXCEPTION 'Effacement différé : sanction en cours de contestation pour %', joueur;
    END IF;
    DELETE FROM operationnel.fiches WHERE player_id = joueur;
    GET DIAGNOSTICS nb = ROW_COUNT;
    DELETE FROM operationnel.evenements_bruts WHERE contenu ->> 'player_id' = joueur::text;
    GET DIAGNOSTICS nb_bruts = ROW_COUNT;
    INSERT INTO supervision.demandes_rgpd (player_id, type, lignes)
    VALUES (joueur, 'effacement', nb + nb_bruts);
    RETURN nb + nb_bruts;
END $$;

-- Vue d'état de la base pour Grafana (taille, connexions, dernière sauvegarde).
CREATE VIEW supervision.etat_base AS
SELECT
    pg_database_size(current_database()) / 1024 / 1024                         AS taille_mo,
    (SELECT count(*) FROM pg_stat_activity WHERE datname = current_database())  AS connexions,
    (SELECT max(faite_le) FROM supervision.sauvegardes)                         AS derniere_sauvegarde,
    extract(epoch FROM now() - (SELECT max(faite_le) FROM supervision.sauvegardes)) / 3600
                                                                                AS heures_depuis_sauvegarde;
