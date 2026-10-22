#!/bin/sh
# Sauvegarde de la base Sentinel (lancée par le service "sauvegarde" de Docker Compose).
#   sh /scripts/sauvegarde.sh            -> une sauvegarde par jour, en boucle
#   sh /scripts/sauvegarde.sh --une-fois -> une seule sauvegarde, tout de suite
#
# Chaque sauvegarde est un fichier pg_dump compressé, enregistré dans le volume "sauvegardes".
# Elle est inscrite dans supervision.sauvegardes : Grafana alerte si la dernière a plus de 26 h.
# Les sauvegardes de plus de 7 jours sont supprimées.
set -e

sauvegarder() {
  fichier="/sauvegardes/sentinel_$(date +%Y%m%d_%H%M%S).dump"
  pg_dump -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --file="$fichier"
  taille=$(du -k "$fichier" | cut -f1)
  psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c \
    "INSERT INTO supervision.sauvegardes (fichier, taille_ko) VALUES ('$(basename "$fichier")', $taille)"
  find /sauvegardes -name "sentinel_*.dump" -mtime +7 -delete
  echo "Sauvegarde faite : $fichier (${taille} Ko)"
}

if [ "$1" = "--une-fois" ]; then
  sauvegarder
else
  while true; do
    sauvegarder || echo "ERREUR : sauvegarde échouée, nouvel essai dans 1 heure" >&2
    sleep 86400
  done
fi
