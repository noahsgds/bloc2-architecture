-- Données de démonstration (synthétiques) : 30 jours d'activité d'Arena Strike.
-- En production, ces tables sont alimentées par le pipeline (bloc 3) et l'API (bloc 4).
-- setseed rend le tirage reproductible : mêmes données à chaque création de la base.

SELECT setseed(0.42);

INSERT INTO operationnel.versions_modele VALUES ('v1', '2026-10-15 08:29:02+00', 0.585, 0.692);

-- 30 jours x 1 500 fiches. Environ 3 % de tricheurs, plus précis et plus signalés.
INSERT INTO operationnel.fiches (player_id, match_id, match_date, accuracy, headshot_rate,
    kd_ratio, avg_reaction_ms, rank_tier, reports_received, input_device, platform,
    age_band, accessibility_mode)
SELECT gen_random_uuid(), gen_random_uuid(),
       date '2026-09-22' + (n % 30),
       least(0.95, 0.20 + random() * 0.15 + triche * 0.15),
       least(1, 0.15 + random() * 0.2 + triche * 0.3),
       0.5 + random() * 2 + triche * 1.5,
       CASE WHEN random() < 0.02 THEN NULL ELSE 300 - random() * 80 - triche * 120 END,
       1 + floor(random() * 8)::int,
       floor(random() * 3 + triche * 3)::int,
       CASE WHEN console THEN 'manette' ELSE 'clavier_souris' END,
       CASE WHEN console THEN 'console' ELSE 'pc' END,
       (ARRAY['16-17', '18-24', '18-24', '25-34', '35+'])[1 + floor(random() * 5)::int],
       random() < 0.04
FROM (SELECT n, (random() < 0.03)::int AS triche, random() < 0.3 AS console
      FROM generate_series(1, 45000) AS n) AS tirage;

-- Score du modèle : plus élevé pour les statistiques suspectes. Seuil de signalement : 0,692.
INSERT INTO operationnel.predictions (player_id, match_id, suspicion_score, flagged, model_version, cree_le)
SELECT player_id, match_id, s, s >= 0.692, 'v1', match_date + time '12:00'
FROM (SELECT player_id, match_id, match_date,
             least(0.999, greatest(0.001, (headshot_rate - 0.25) * 1.6 + random() * 0.35)) AS s
      FROM operationnel.fiches) AS scores;

-- Décisions des modérateurs sur les fiches signalées (environ 300 par jour au maximum).
INSERT INTO operationnel.decisions (player_id, match_id, decision, moderateur, cree_le)
SELECT player_id, match_id,
       CASE WHEN suspicion_score > 0.85 THEN 'triche_confirmee'
            WHEN random() < 0.5 THEN 'innocente' ELSE 'a_approfondir' END,
       'mod-0' || (1 + floor(random() * 5)::int), cree_le + interval '3 hours'
FROM operationnel.predictions WHERE flagged;

-- Quelques événements bruts au format JSON, tels qu'envoyés par les serveurs de jeu.
INSERT INTO operationnel.evenements_bruts (fichier, contenu)
SELECT 'fin_de_match_demo.json',
       jsonb_build_object('player_id', player_id, 'match_id', match_id, 'match_date', match_date,
                          'accuracy', accuracy, 'platform', platform, 'serveur', 'eu-west-1')
FROM operationnel.fiches LIMIT 1000;

SELECT entrepot.rafraichir();
