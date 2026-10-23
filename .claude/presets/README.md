# Préréglages d'outillage

Chaque fichier est un `project.conf` prêt à l'emploi. Pour adopter l'un d'eux :

```bash
cp .claude/presets/<nom>.conf .claude/project.conf
```

| Préréglage | Outillage |
| --- | --- |
| `docker-compose-npm.conf` | Docker Compose, services `back`/`front`, npm |
| `host-npm.conf` | npm directement sur l'hôte |

Pour un autre outillage (Python, PHP, Go, Java, Rust, .NET…), partir de
`../project.conf` (cibles `make`) ou d'un préréglage et ajuster les regex :
une commande simple, liste blanche stricte, jamais de shell ni d'installation
sans exception humaine.
