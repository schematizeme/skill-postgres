# Anexo volátil — versões, EOL e o que foi executado (PostgreSQL)

> Parte da skill **schematize-postgres**. **Fonte volátil:** número de versão, data de EOL e
> comportamento por versão mudam. O corpo normativo diz **princípio**; o número mora aqui.
>
> **Verificado em: 2026-10-14.** Cadência: revisão trimestral e a cada release da skill.

## Versões e EOL

| Major | Último minor | EOL (fim do suporte) | Fonte |
|---|---|---|---|
| 18 | 18.6 (2026-08-11) | 2030-11-14 | endoflife.date/api/postgresql.json + tags `REL_18_6` em `postgres/postgres` |
| 17 | 17.11 (2026-08-10) | 2029-11-08 | idem |
| 16 | 16.15 (2026-08-10) | 2028-11-09 | idem |
| 15 | 15.19 (2026-08-10) | 2027-11-11 | idem |
| 14 | 14.24 (2026-08-10) | **2026-11-12** (menos de 30 dias após a verificação) | idem |
| 13 | 13.23 | 2025-11-13 (já fora de suporte) | idem |

Política oficial: 5 anos por major, um major por ano (postgresql.org/support/versioning).
<!-- reverificar: a página de versioning não foi parseada nesta rodada; datas vêm do endoflife.date, que replica o calendário oficial -->

## Ferramentas

| Ferramenta | Corrente | Fonte |
|---|---|---|
| PgBouncer | **1.26.1** (2026-10-14): corrige CVE-2026-107350 (SCRAM, impersona usuário), CVE-2026-107349 e CVE-2026-107348 (negação de serviço) | `gh api repos/pgbouncer/pgbouncer/releases/latest` (notas do release) |
| pgBackRest | 2.59.3 (2026-10-04) | `gh api repos/pgbackrest/pgbackrest/releases/latest` |
| WAL-G | v3.0.9 (2026-08-20) | `gh api repos/wal-g/wal-g/releases/latest` |
| Patroni | <!-- reverificar --> | não consultado nesta rodada |

## Recursos por versão citados nas references (notas oficiais)

Fonte: `postgresql.org/docs/18/release-18.html` e `docs/17/release-17.html`, lidos em 2026-10-14.

- **PG 18:** subsistema de I/O assíncrono (`io_method`); `pg_upgrade` retém estatísticas do
  otimizador; skip scan em B-tree; `uuidv7()`; colunas geradas **virtuais** (agora o default);
  autenticação OAuth; `initdb` liga checksums por default (`--no-data-checksums` para o oposto;
  `pg_upgrade` exige configuração igual); `ALTER TABLE` pode definir `NOT VALID` em constraint
  `NOT NULL`; `EXPLAIN ANALYZE` inclui `BUFFERS` automaticamente; `idle_replication_slot_timeout`.
- **PG 17:** backup incremental nativo (`pg_basebackup --incremental`, `pg_combinebackup`);
  `pg_createsubscriber`; failover de slots lógicos (`sync_replication_slots`,
  `pg_sync_replication_slots()`); `pg_upgrade` migra slots e assinaturas lógicas.

## O que foi EXECUTADO (PostgreSQL 18.6, container `postgres:18`, 2026-10-14)

Provas em banco real (tabela de 100 mil linhas), citadas nas references:

| Afirmação | Resultado |
|---|---|
| `ADD COLUMN ... DEFAULT 'free'` (constante) | sem reescrita (mesmo `relfilenode`) |
| `ADD COLUMN ... DEFAULT now()` | sem reescrita |
| `ADD COLUMN ... DEFAULT gen_random_uuid()` | **reescreve** (`relfilenode` mudou) |
| `ADD COLUMN ... GENERATED ALWAYS AS (...) STORED` | **reescreve** |
| `ADD COLUMN ... GENERATED ALWAYS AS (...) VIRTUAL` | sem reescrita |
| `ALTER COLUMN id TYPE bigint` (de `integer`) | **reescreve** |
| `ALTER COLUMN nome TYPE varchar(100)` (de `varchar(50)`) | sem reescrita |
| `ADD CONSTRAINT ... NOT NULL col NOT VALID` + `VALIDATE CONSTRAINT` | aceito no PG 18 (constraint `convalidated = t`) |
| `SET lock_timeout='1s'` + `ALTER TABLE` com `ACCESS SHARE` segurado por outra sessão | `canceling statement due to lock timeout` |
| `CREATE INDEX CONCURRENTLY` dentro de `BEGIN` | `cannot run inside a transaction block` |
| `show autovacuum_freeze_max_age; show io_method; show data_checksums` | `200000000`; `worker`; `on` |
| `uuidv7()` | existe |

O gate `scripts/check-pg-migration.sh` foi exercitado com `scripts/check-pg-migration.test.sh`
(vermelhos e verdes plantados). Os `.sql` verdes do teste espelham receitas cujo SQL foi
executado acima.

## Não verificado nesta rodada

- Patroni (versão e requisitos de DCS); Neon/Supabase/RDS (calendários de EOL do provedor).
- Sintaxe de "sem transação" por runner de migration (Flyway, Liquibase, sqlx, Atlas, Ecto,
  EF Core, Rails): <!-- reverificar --> a documentação de cada um.
- Execução real de pgBackRest/PgBouncer/Patroni (só documentação e notas de release lidas).
