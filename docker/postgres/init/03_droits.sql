-- Droits de chaque rôle (moindre privilège). Personne d'autre que l'administrateur ne peut
-- supprimer une table ; Grafana ne peut que lire.

REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Pipeline (bloc 3) : écrit les données entrantes.
GRANT USAGE ON SCHEMA operationnel TO pipeline_ecriture;
GRANT SELECT, INSERT, UPDATE, DELETE ON operationnel.evenements_bruts, operationnel.fiches TO pipeline_ecriture;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA operationnel TO pipeline_ecriture;

-- API Sentinel (bloc 4) : lit les fiches, écrit prédictions et décisions.
GRANT USAGE ON SCHEMA operationnel TO api_sentinel;
GRANT SELECT ON operationnel.fiches, operationnel.versions_modele TO api_sentinel;
GRANT SELECT, INSERT ON operationnel.predictions, operationnel.decisions TO api_sentinel;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA operationnel TO api_sentinel;

-- Grafana : lecture seule de l'entrepôt et de la supervision, jamais des données
-- opérationnelles détaillées (pas d'accès aux identifiants des joueurs).
GRANT USAGE ON SCHEMA entrepot, supervision TO grafana_lecture;
GRANT SELECT ON ALL TABLES IN SCHEMA entrepot, supervision TO grafana_lecture;
REVOKE SELECT ON supervision.demandes_rgpd FROM grafana_lecture;  -- contient des identifiants

-- Les fonctions RGPD ne sont exécutables que par l'administrateur (DPO / exploitation).
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA supervision, entrepot FROM PUBLIC;
