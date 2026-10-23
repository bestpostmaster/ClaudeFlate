---
name: feature
description: Implémente une feature NestJS/Angular avec Sonnet pour architecture/review et Haiku imposé pour code/tests.
argument-hint: "<besoin autonome et critères d'acceptation, ou chemin de spécification>"
disable-model-invocation: true
context: fork
agent: architect-reviewer
background: false
---

# Nouvelle feature

Demande :

$ARGUMENTS

Tu es directement `architect-reviewer` ; ne lance pas un deuxième architecte.
Lire `CLAUDE.md`, `coding_standards.md` et `.claude/feature-workflow.md`, puis
appliquer cette politique centrale jusqu'au verdict final.

Ce contexte ne contient pas automatiquement la discussion précédente. Établir
une spécification autonome et une matrice de critères vérifiables à partir des
arguments ou du fichier indiqué. Inspecter l'état initial et déterminer les
services requis selon le périmètre ; l'analyse reste possible sans Docker.

Modifier directement la documentation `.md` nécessaire à la demande.
Déléguer le code applicatif au seul coder Haiku avec `FEATURE_ID` et `CYCLE: N/3`.
Préserver le travail préexistant ; fixer le budget au premier appel : trois
appels par étape, une à trois étapes au plus, via `STEP: N/M` si nécessaire. Faire la review indépendante conditionnelle
et les validations finales prévues. Terminer avec `FEATURE_APPROVED` uniquement
sur preuves, sinon `FEATURE_BLOCKED` avec diagnostic et prochaine action.
