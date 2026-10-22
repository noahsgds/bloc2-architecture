#!/bin/sh
# Copie chiffrée de la dernière sauvegarde, à conserver HORS de ce serveur (disque externe,
# autre site). Chiffrement AES-256 avec une phrase secrète : sans elle, le fichier est illisible.
#
#   ./scripts/exporter_chiffre.sh                 -> crée sentinel_XXXX.dump.enc ici
#   Déchiffrer : openssl enc -d -aes-256-cbc -pbkdf2 -in fichier.enc -out fichier.dump
set -e
cd "$(dirname "$0")/.."

fichier=$(docker compose exec -T sauvegarde sh -c 'ls -t /sauvegardes | head -1')
docker compose cp "sauvegarde:/sauvegardes/$fichier" "./$fichier"
openssl enc -aes-256-cbc -pbkdf2 -salt -in "./$fichier" -out "./$fichier.enc"
rm "./$fichier"   # on ne garde que la version chiffrée
echo "Copie chiffrée prête : $fichier.enc"
