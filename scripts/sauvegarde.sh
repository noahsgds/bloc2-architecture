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
  # Attendre que la base accepte les connexions (au premier démarrage, elle s'initialise).
  until pg_isready -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q; do sleep 2; done

  fichier="/sauvegardes/sentinel_$(date +%Y%m%d_%H%M%S).dump"
  # En cas d'échec, on s'arrête AVANT d'écrire « sauvegarde faite » : jamais d'échec silencieux.
  pg_dump -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --file="$fichier" \
    || { rm -f "$fichier"; return 1; }
  taille=$(du -k "$fichier" | cut -f1)
  psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -c \
    "INSERT INTO supervision.sauvegardes (fichier, taille_ko) VALUES ('$(basename "$fichier")', $taille)" \
    || return 1
  find /sauvegardes -name "sentinel_*.dump" -mtime +7 -delete
  echo "Sauvegarde faite : $fichier (${taille} Ko)"
}

if [ "$1" = "--une-fois" ]; then
  sauvegarder
else
  while true; do
    if sauvegarder; then
      sleep 86400                      # prochaine sauvegarde dans 24 h
    else
      echo "ERREUR : sauvegarde échouée, nouvel essai dans 5 minutes" >&2
      sleep 300                        # et Grafana alerte si cela dure plus de 26 h
    fi
  done
fi
