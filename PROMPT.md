# Projet CalMirror

## Problème

J'ai plusieurs calendriers synchronisés dans l'app Apple Calendrier:

- perso: Google
- pro: Google
- client: Microsoft O365

Quand je dois planifier un rdv ou donner mes disponibilités à qqn j'ai besoin de connaitre facilement les créneaux "réellement" disponibles.
Pas disponible dans un calendrier, mais disponible au global, tout calendrier confondus.

Il existe des applications qui permettent de générer des liens de partage de ses disponibilités mais:

- Elles ne supportent pas toutes à la fois Google et Microsoft
- Je ne souhaite pas exposer les données de mon client en associant ce calendrier à une app SaaS
- Je peux synchroniser mon calendrier client avec Apple Calendrier, mais certaines fonctionnalités d'intégration sont bloquées par l'entreprise

## Solution

Je veux donc réaliser une petite application native macOS qui me permettrait de faire apparaître les events de mon calendrier client dans mon calendrier pro. L'objectif n'est pas de les répliquer complètement mais de la faire apparaître pour que les créneaux correspondants soient bloqués.

### Composants

L'application devrait se décomposer en 2 composants principaux:

- L'interface UI: interface native permettant de configurer les copies, les consulter, et consulter les logs
- Le démon: s'occupe d'exécuter la ou les synchronisations configurées à fréquence régulière en travaillant exclusivement avec l'application Calendrier locale du mac
  - Un seul démon pour l'ensemble des synchronisation
  - Sous forme de service (tout le temps up) ou de cron job (exécuté à fréquence régulière)
  - Le langage de développement reste à déterminer, il faut aller au plus simple tout en ayant l'empreinte la plus faible en ressources

### UI

- Interface native macOS
- Apparence intuitive et moderne

### Configuration d'une copie

Concretement, configurer une copie consiste à:

- Déterminer le calendrier qui servira de source (on choisit dans les calendrier existants dans Apple Calendrier), celui pour lequel les événements devront être répliqué
- Déterminer le calendrier cible (on choisit dans les calendrier existants dans Apple Calendrier), celui dans lequel les bloqueurs seront ajoutés
- Déterminer la fenêtre glissante d'étude (7j, 30j, etc.)
- Déterminer le libellé à mettre pour les bloqueurs (ex: "[MonClient] Busy")
  - Pour rappel, on ne réplique pas réellement les events (titre, invités, contenu) pour éviter les fuites de données et parce que cela n'a pas d'intérêt

Dans l'application, on peut avoir plusieurs copies configurées en parallèle, chacune avec sa propre configuration.

### Synchronisation

A fréquence régulière, on execute les synchronisations configurées dans l'application

- On récupère les events du calendrier source sur la plage d'étude demandée
- On créée les bloqueurs dans le calendrier cible s'ils n'existent pas déjà
- On supprime les bloqueurs du calendrier cible pour lesquels les events n'existent pas (ou plus) dans le calendrier source
- Dans AUCUN CAS on ne peut modifier les events du calendrier source
- Dans AUCUN CAS on ne peut modifier les events du calendrier cible autre que les bloqueurs gérer par la solution
  - On trace pour chaque exécution
  - La configuration de la synchro
  - Les bloqueurs ajoutés
  - Les bloqueurs supprimés

### Packaging

- Un packaging permettant une installation via brew serait idéal
- Une seule installation pour l'ensemble de l'app (UI + démon)
