---
description: Mapa da skill schematize-postgres (operação do PostgreSQL: locks e migrations seguras, EXPLAIN, vacuum, pooling, backup/PITR, upgrade, RLS).
---
**schematize-postgres** — operar o PostgreSQL (o motor). O desenho do schema é da `schematize-database`.

| Comando | O que faz |
|---|---|
| `/pg-help` | esta lista |
| `/pg-load` | carrega à força TODO o corpo normativo (versão e config, EXPLAIN, vacuum, locks, pooling, replicação, backup, upgrade, RLS) e passa a aplicá-lo |
| `/pg-review` | revisa migrations e config: roda `scripts/check-pg-migration.sh` e lê o que a máquina não lê |
| `/pg-migrate` | transforma uma mudança de schema em passos seguros para tabela viva (expand, backfill em lotes, contract) |
| `/pg-explain` | lê um plano `EXPLAIN (ANALYZE, BUFFERS)` e propõe índice ou reescrita sem lock |
| `/pg-backup` | audita backup/PITR e monta o ensaio de restore com RPO/RTO medidos |
| `/pg-upgrade` | planeja o upgrade de major com ensaio, rollback e checklist |
| `/pg-claude` | cria ou mescla o `CLAUDE.md` sempre-on de operação Postgres na raiz do repo |
| `/pg-cc` · `/pg-handoff` | context compact / handoff no archive |

Pareia com: `schematize-database` (desenho), `schematize-data` (pipeline/CDC), `schematize-infra`
(DR e plataforma), `schematize-observability` (métricas e alerta), `schematize-pentest` (RLS e roles).
