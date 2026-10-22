#!/bin/sh
# Restaure une sauvegarde dans une base. Par défaut, dans une base de TEST : on vérifie
# qu'une sauvegarde est vraiment utilisable, sans toucher à la base en service.
#
#   ./scripts/restaurer.sh                        -> dernière sauvegarde, base "restauration_test"
#   ./scripts/restaurer.sh sentinel_XXXX.dump     -> sauvegarde choisie, base "restauration_test"
#   ./scripts/restaurer.sh sentinel_XXXX.dump sentinel   -> restauration réelle après un incident
set -e
cd "$(dirname "$0")/.."

fichier=${1:-$(docker compose exec -T sauvegarde sh -c 'ls -t /sauvegardes | head -1')}
cible=${2:-restauration_test}
echo "Restauration de $fichier dans la base « $cible »..."

docker compose exec -T sauvegarde sh -c "
  psql -h postgres -U \$POSTGRES_USER -d postgres -q -c 'DROP DATABASE IF EXISTS $cible' &&
  psql -h postgres -U \$POSTGRES_USER -d postgres -q -c 'CREATE DATABASE $cible' &&
  pg_restore -h postgres -U \$POSTGRES_USER -d $cible --no-owner /sauvegardes/$fichier
"
fiches=$(docker compose exec -T sauvegarde sh -c \
  "psql -h postgres -U \$POSTGRES_USER -d $cible -tA -c 'SELECT count(*) FROM operationnel.fiches'")
echo "Restauration terminée : $fiches fiches dans la base « $cible »."
