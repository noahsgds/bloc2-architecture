#!/bin/sh
# Rôles de la base : un rôle par usage, avec le minimum de droits (moindre privilège).
# Les mots de passe viennent du fichier .env, jamais du code.
#   pipeline_ecriture : le pipeline (bloc 3) écrit les événements et les fiches ;
#   api_sentinel      : l'API (bloc 4) lit les fiches, écrit prédictions et décisions ;
#   grafana_lecture   : les tableaux de bord lisent, sans jamais rien modifier.
set -e

# Refus de démarrer avec un mot de passe par défaut (sécurité).
for valeur in "$POSTGRES_PASSWORD" "$PIPELINE_PASSWORD" "$API_PASSWORD" "$GRAFANA_DB_PASSWORD"; do
  if [ -z "$valeur" ] || [ "$valeur" = "change-me" ]; then
    echo "ERREUR : remplacer tous les mots de passe 'change-me' du fichier .env" >&2
    exit 1
  fi
done

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE ROLE pipeline_ecriture LOGIN PASSWORD '${PIPELINE_PASSWORD}';
CREATE ROLE api_sentinel      LOGIN PASSWORD '${API_PASSWORD}';
CREATE ROLE grafana_lecture   LOGIN PASSWORD '${GRAFANA_DB_PASSWORD}';
SQL
