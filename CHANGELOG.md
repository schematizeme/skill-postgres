# Changelog — schematize-postgres

Todas as mudanças relevantes deste pacote, no formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
com versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [0.1.0] — 2026-10-14
Primeira versão. A `schematize-database` cobre o **desenho** do schema (inclusive o método
expand-contract), mas ninguém na casa cobria o **motor**: qual DDL toma `ACCESS EXCLUSIVE`, por que a
migration "rápida" derruba a produção pela fila de lock, como medir antes de indexar, o que o
vacuum segura, quando o backup vale, como atualizar de major. Esta skill é o lado de operação.

### Adicionado
- `SKILL.md`: 15 pisos inegociáveis (versão suportada e EOL, `pg_stat_statements`, `lock_timeout`,
  `CONCURRENTLY`, `NOT VALID` + `VALIDATE`, sem reescrita sob lock, contract marcado, autovacuum,
  pooler, backup com restore testado, failover ensaiado, roles de menor privilégio, RLS com `FORCE`,
  credencial fora do SQL) e a fronteira com `database`, `data`, `infra`, `observability`.
- `references/`: `versao-e-config`, `explain-e-indices`, `vacuum-e-bloat`, `locks-e-migrations`,
  `pooling`, `replicacao-e-failover`, `backup-e-pitr`, `upgrade`, `roles-e-rls`, `stack-versoes`
  (anexo volátil com fonte e data; comportamentos de DDL provados em PostgreSQL 18.6).
- `scripts/check-pg-migration.sh` (gate estático de `.sql`, 24 regras, sem depender de Postgres) e
  `check-pg-migration.test.sh` (vermelhos e verdes plantados).
- Comandos `/pg-help`, `/pg-load`, `/pg-review`, `/pg-migrate`, `/pg-explain`, `/pg-backup`,
  `/pg-upgrade`, `/pg-claude`, `/pg-cc`, `/pg-handoff`; `assets/CLAUDE.md` sempre-on.
