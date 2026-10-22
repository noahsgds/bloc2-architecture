# Pourquoi pas de Terraform dans ce projet

L'énoncé cite Terraform comme exemple d'outil d'infrastructure as code. J'ai choisi
**Docker Compose** (`docker-compose.yml` et dossier `docker/`) pour les raisons suivantes :

1. **Une seule machine, pas de cloud.** Terraform sert surtout à créer des ressources chez un
   fournisseur (serveurs, réseaux, bases managées). Ici, tout tourne en conteneurs sur un
   seul poste, sans cloud payant : Docker Compose décrit déjà toute l'infrastructure.
2. **Docker Compose est déjà de l'infrastructure as code.** Le fichier est déclaratif
   (on décrit l'état voulu, pas les commandes), versionné dans Git, et recrée la plateforme
   à l'identique avec `docker compose up -d`. La CI le prouve à chaque modification.
3. **Simplicité et maintenabilité.** Un outil de moins à installer, à apprendre et à
   maintenir pour une équipe d'une personne.

**Quand Terraform deviendrait pertinent :** passage dans le cloud (par exemple une base
Postgres managée répliquée dans deux zones, un réseau privé, un stockage objet pour les
sauvegardes). Terraform créerait alors ces ressources ; les conteneurs, les scripts SQL et
les tableaux de bord Grafana resteraient les mêmes.
