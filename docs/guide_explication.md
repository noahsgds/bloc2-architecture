# Plateforme de données expliquée simplement — guide pour la soutenance (bloc 2)

## 1. En 30 secondes

**Ce que je dis :** « La plateforme héberge toutes les données de Sentinel dans une base
Postgres, organisée en trois espaces : les données vivantes, un entrepôt pour l'analyse et
la supervision. Grafana affiche l'activité, les résultats du modèle, l'équité et la santé
de la base, et alerte si la sauvegarde manque. Une sauvegarde est faite chaque jour, et
la CI vérifie à chaque modification qu'on sait la restaurer. Tout démarre avec une commande. »

## 2. Docker Compose = mon code d'infrastructure

**Ce que c'est :** un fichier qui décrit les 3 services (base, Grafana, sauvegarde), leurs
réglages, leurs volumes et leurs liens. `docker compose up -d` recrée la plateforme à
l'identique sur n'importe quel poste.

**Question probable — *Pourquoi pas Terraform ?*** Terraform crée des ressources chez un
fournisseur de cloud. Ici, tout tourne sur un seul poste, sans cloud : Compose décrit déjà
toute l'infrastructure, de façon déclarative et versionnée. Si on passait dans le cloud,
Terraform créerait la base managée et le réseau ; le reste ne changerait pas.

## 3. Le modèle de données

- **`operationnel`** : les données vivantes, comme dans une application (fiches, prédictions,
  décisions). Des contraintes empêchent les valeurs impossibles.
- **`entrepot`**, le modèle en étoile : une table de faits (une ligne par fiche analysée)
  entourée de dimensions (date, appareil, niveau, version du modèle). **Image :** la table
  de faits est le ticket de caisse, les dimensions sont le calendrier, le rayon, le magasin.
  On peut compter « par jour, par appareil » sans requêtes compliquées.
- **`supervision`** : sauvegardes, état de la base, demandes RGPD.

**Les 3 types de données :** structurées (les tables), semi-structurées (le JSON des
serveurs de jeu, dans une colonne JSONB qui accepte de nouveaux champs), non structurées
(rapports HTML, journaux, gardés en fichiers).

**Question probable — *Pourquoi pas de joueur dans l'entrepôt ?*** Il sert aux statistiques.
Ne pas y mettre d'identifiant, c'est de la minimisation : un analyste n'a pas besoin de
savoir qui est derrière une fiche.

## 4. Sécurité

- Un rôle par usage, avec le minimum de droits : le pipeline écrit les fiches, l'API écrit
  les prédictions, Grafana lit seulement l'entrepôt. La CI vérifie que Grafana ne peut pas
  lire les identifiants.
- Mots de passe dans `.env`, jamais dans Git ; la base refuse de démarrer avec « change-me ».
- Base et Grafana joignables seulement depuis le poste.
- Sauvegardes copiées hors du serveur en version chiffrée (AES-256).

**Limite à dire moi-même :** pas de chiffrement TLS entre les services en local (tout reste
sur le poste). En production : TLS entre services, HTTPS pour Grafana, disque chiffré.

## 5. Sauvegarde et continuité

- Une sauvegarde par jour, 7 jours gardés, inscrite en base.
- Grafana alerte si la dernière a plus de 26 heures.
- `./scripts/restaurer.sh` restaure dans une base de test et compte les fiches : une
  sauvegarde n'est utile que si on sait la restaurer.
- **Une anecdote utile au jury :** la CI a trouvé un vrai bug. Au premier démarrage, la
  sauvegarde partait pendant que la base s'initialisait, et le script affichait « sauvegarde
  faite (0 Ko) ». Je l'ai corrigé : le script attend la base et ne déclare jamais une
  sauvegarde ratée comme réussie.

**Question probable — *Et si le serveur tombe ?*** Les services redémarrent seuls ; si les
données sont perdues, on restaure la dernière sauvegarde en quelques minutes (perte
maximale : 24 h). En production, une réplique et un basculement automatique réduiraient
l'interruption à quelques secondes.

## 6. RGPD

- `supervision.droit_acces(player_id)` : tout ce qu'on sait sur un joueur, en un JSON.
- `supervision.droit_effacement(player_id)` : suppression partout, sauf si une triche est
  confirmée (preuve gardée pendant la contestation, article 17.3.e).
- Chaque demande est enregistrée : preuve qu'elle a été traitée.

## 7. Volume

30 000 fiches par jour, c'est environ 11 millions par an et 7 Go : un Postgres sur un poste
s'en sort très bien. Au-delà, on découperait les tables par mois (partitionnement).

## Petit glossaire

| Mot | En simple |
|---|---|
| Infrastructure as code | L'infrastructure décrite dans des fichiers versionnés, recréable à l'identique |
| Schéma (Postgres) | Un espace de rangement dans la base |
| Modèle en étoile | Une table de faits au centre, des dimensions autour, pour l'analyse |
| JSONB | Colonne qui stocke du JSON et permet d'y chercher |
| Rôle | Un compte de connexion à la base, avec ses droits |
| Moindre privilège | Chacun n'a que les droits dont il a besoin |
| Réplique | Copie de la base tenue à jour en continu, prête à prendre le relais |
