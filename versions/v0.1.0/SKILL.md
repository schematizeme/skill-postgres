---
name: schematize-postgres
metadata:
  version: 0.1.0
description: >-
  Operar o PostgreSQL: config, EXPLAIN e índices, vacuum, locks e migrations seguras, PgBouncer, replicação, backup/PITR com restore testado, pg_upgrade, RLS e roles. Use ao tocar *.sql ou postgresql.conf. Schema: schematize-database.
---
<!-- cross-skill: modelo-relacional.md, migrations.md, normalizacao-chaves-indices.md -> schematize-database -->

# Operação do PostgreSQL (schematize-postgres)

Disciplina normativa para **operar o motor**: versão, configuração, plano de execução, vacuum,
lock, migration em tabela viva, pooling, replicação, backup, upgrade e isolamento por role/RLS.
A tese: **o Postgres perdoa SQL errado e castiga SQL correto no momento errado** — um `CREATE
INDEX` comum, um `ADD COLUMN` com default volátil ou um `ALTER TYPE` rodam em milissegundos na
máquina do desenvolvedor e travam a produção por minutos. E o backup que nunca foi restaurado
não é backup. O **desenho** do schema é da `schematize-database`; aqui é **o motor e a
operação**.

**Versão:** skill `schematize-postgres` v0.1.0. Changelog em `CHANGELOG.md`.

## Precedência e herança (leia antes de divergir)

<!-- herdado:engineering/precedencia:dominio intro="Esta skill é o recorte **operação do PostgreSQL (o motor)** da base: **ferramenta/domínio**, agnóstica de linguagem de aplicação — o schema em si é da `schematize-database`." cmd="pg" -->Esta skill é o recorte **operação do PostgreSQL (o motor)** da base: **ferramenta/domínio**, agnóstica de linguagem de aplicação — o schema em si é da `schematize-database`.

1. **Onde esta skill divergir da base, a BASE MANDA.** Aqui mora a especialização do domínio ou da
   ferramenta — o como, o padrão, o gate. Divergência de *piso* é defeito desta skill, não variante local.
2. **O que não está repetido aqui é HERDADO, não dispensado.** Esta skill herda os pisos da base e
   os comandos dela cobrem o **domínio**, não o piso geral. Valem integralmente, sem cópia local:
   - **§28 Archive** — `<projeto>/<projeto>_archive/` é **repositório git próprio, PRIVADO e
     obrigatório**, criticidade 0 (`schematize-archive`).
   - **§35 Definition of Done** e a lista de anti-padrões (citada por **título**, nunca por número).
   - **§39 Índice/MAPA** — enumeração exaustiva (uma entrada por unidade chamável, `M == N`) e grafo
     com arestas em ASCII (`A -> B`), nunca a seta unicode.
   - **IAM** (`schematize-engineering` → `references/iam.md`): identidade ≠ email, ≥2 fatores, ReBAC
     multi-tenant, argon2id-only para senha nova, sessão longa e logout irreversível.
   - **Efeito externo** nunca sai de não-produção (`schematize-engineering` →
     `references/efeitos-externos.md`).
   - **Orquestração** (`schematize-engineering` → `references/orquestracao.md` §9): o principal não
     desenvolve (é Claude Opus); executor mais barato que resolve — `haiku`/`sonnet` → Codex Terra → Cursor → `opus` só após falha; visual direto ao Codex; imagem nunca pelo Claude: detecta Codex/Gemini e pergunta ao usuário qual usar (Codex é a sugestão, não automática), nunca API paga.
3. **QA, ops, IAM e índice não têm comando próprio aqui:** vêm da base `/eng-*`. Para trabalho
   contínuo use `/eng-overdev`; para planejar `/eng-plan`; para varrer a base `/eng-scan`; para
   revisão geral `/eng-review` (e `/eng-ops`, `/eng-iam`, `/eng-index`). Os comandos
   `/pg-*` cobrem o domínio desta skill; o piso geral é o da base.<!-- /herdado -->

## Fronteira com as outras skills

| Assunto | Dono | Ponteiro |
|---|---|---|
| **Desenho** do schema: tabelas, tipos, chaves, constraints, qual índice faz sentido, expand-contract como método, PII marcada | `schematize-database` | `schematize-database → references/modelo-relacional.md`, `normalizacao-chaves-indices.md`, `migrations.md` |
| **Motor e operação**: config, EXPLAIN, vacuum, locks, migration segura (`lock_timeout`, `CONCURRENTLY`, `NOT VALID`), pooling, replicação, backup/PITR, `pg_upgrade`, RLS e roles | **esta skill** | `references/*.md` abaixo |
| Dado em movimento: pipeline, CDC, outbox, warehouse, backfill como pipeline | `schematize-data` | `schematize-data → references/armazenamento.md` |
| Backup/DR genérico, rede/TLS, segredos, isolamento por serviço, IaC | `schematize-infra` | `schematize-infra → references/resiliencia.md`, `isolamento.md`; aqui só o que é específico do Postgres |
| Métricas, SLO e alerta (como instrumentar) | `schematize-observability` | `schematize-observability`; aqui só **quais** métricas do Postgres importam |
| Container do Postgres, volume, healthcheck | `schematize-docker` | `schematize-docker → Dockerfile, compose` |
| Query parametrizada, ORM, pool no cliente | skill de linguagem | `schematize-go`/`rust`/`elixir`/`csharp`/`zig`/`ruby` |
| Teste ofensivo (cross-tenant, SQL injection, role excessiva) | `schematize-pentest` | lado ofensivo; aqui o construtivo |
| ADR, runbook (restore, failover, upgrade) | `schematize-docs` | decisões e procedimentos que esta skill manda escrever |

## Comandos (Claude Code)

| Comando | O que faz |
|---|---|
| `/pg-help` | lista os comandos |
| `/pg-load` | carrega à força o corpo normativo (versão e config, EXPLAIN, vacuum, locks, pooling, replicação, backup, upgrade, RLS) |
| `/pg-review` | revisa migrations e config: roda o gate e lê o que a máquina não lê |
| `/pg-migrate` | transforma uma mudança de schema em passos seguros em tabela viva (expand, backfill em lotes, contract) e roda o gate |
| `/pg-explain` | lê um plano `EXPLAIN (ANALYZE, BUFFERS)` e propõe o índice ou a reescrita, sem lock |
| `/pg-backup` | audita backup/PITR e monta o ensaio de restore com RPO/RTO medidos |
| `/pg-upgrade` | planeja um `pg_upgrade` (ou lógico) com ensaio, rollback e checklist |
| `/pg-claude` | cria/mescla o `CLAUDE.md` sempre-on de operação Postgres |
| `/pg-cc` · `/pg-handoff` | context compact / handoff arquivado |

## Como usar

1. **Rode o gate antes de discutir estilo:** `bash scripts/check-pg-migration.sh <dir ou .sql>` —
   `0` passa · `1` reprova · `2` **nada para verificar** (que não é aprovação). Não precisa de
   Postgres instalado. Waiver rastreável com motivo: `-- pg-ok: <regra> <motivo>`,
   `-- pg-ok-file: <regra> <motivo>` e `-- pg-contract: <motivo>` (fase contract).
2. **Fixe a versão e a config** (`references/versao-e-config.md`): major com EOL distante, minor
   sempre atual, `pg_stat_statements` ligado, timeouts por role.
3. **Meça antes de indexar** (`references/explain-e-indices.md`): plano real, `BUFFERS`, estimado
   vs real; índice criado `CONCURRENTLY`.
4. **Vacuum é saúde, não manutenção opcional** (`references/vacuum-e-bloat.md`).
5. **Migration em tabela viva** (`references/locks-e-migrations.md`): fila de lock, `lock_timeout`,
   `NOT VALID` + `VALIDATE`, backfill em lotes.
6. **Conexões** (`references/pooling.md`), **réplica** (`references/replicacao-e-failover.md`),
   **backup** (`references/backup-e-pitr.md`), **upgrade** (`references/upgrade.md`),
   **isolamento** (`references/roles-e-rls.md`).

Mapa de references:

| Tarefa | Reference |
|---|---|
| Versão suportada e EOL, minor vs major, parâmetros que importam (memória, WAL, autovacuum, timeouts, logs), extensões obrigatórias | `references/versao-e-config.md` |
| `EXPLAIN (ANALYZE, BUFFERS)`, ler o plano, `pg_stat_statements`, índice na prática, índice inválido/não usado, criar sem lock | `references/explain-e-indices.md` |
| MVCC, autovacuum por tabela, wraparound, o que segura o xmin, bloat e como corrigir sem `VACUUM FULL` | `references/vacuum-e-bloat.md` |
| Níveis de lock, fila de lock, tabela "operação x seguro/perigoso", receitas de migration, backfill, runner | `references/locks-e-migrations.md` |
| PgBouncer: modos, limites do modo transação, dimensionamento, autenticação | `references/pooling.md` |
| Streaming e lógica, sync/async, slots, Patroni, failover, ensaio | `references/replicacao-e-failover.md` |
| pgBackRest/WAL-G, PITR, restore testado, RPO/RTO, retenção e LGPD | `references/backup-e-pitr.md` |
| Minor e major, `pg_upgrade`, collation, checksums, upgrade lógico, rollback | `references/upgrade.md` |
| Roles de menor privilégio, `pg_hba.conf`, RLS multi-tenant com `FORCE` e pooler | `references/roles-e-rls.md` |
| Versões, EOL, fontes e o que foi executado (anexo volátil) | `references/stack-versoes.md` |

Assets: `assets/CLAUDE.md` (piso sempre-on) · `assets/commands/` (comandos `/pg-*`).

## Pisos inegociáveis (vetam o atalho)

1. **Só versão major suportada, e o EOL entra no calendário.** Produção nunca roda major fora de
   suporte; o upgrade é planejado com meses de folga, ensaiado e com rollback
   (`references/upgrade.md`). Minor sempre na última publicada.
2. **`pg_stat_statements` ligado em todo cluster** (`shared_preload_libraries` + `CREATE
   EXTENSION`), junto de `track_io_timing`. Sem ele, "está lento" é palpite.
3. **Nenhum DDL em tabela viva sem `lock_timeout`.** `SET lock_timeout` antes do primeiro DDL, com
   retry: a migration que espera lock bloqueia todas as queries que chegam depois dela.
4. **Índice em tabela viva é `CREATE INDEX CONCURRENTLY`** (e `DROP INDEX CONCURRENTLY`,
   `REINDEX ... CONCURRENTLY`), fora de transação. Índice que falhou fica `INVALID` e é removido.
5. **Constraint nova entra `NOT VALID` e é validada à parte.** FK e CHECK: `ADD ... NOT VALID` +
   `VALIDATE CONSTRAINT`; `NOT NULL`: via `CHECK (col IS NOT NULL) NOT VALID` (ou `NOT NULL ... NOT
   VALID` no PG 18); `UNIQUE`/`PRIMARY KEY`: índice `CONCURRENTLY` + `USING INDEX`.
6. **Nada de reescrever a tabela sob `ACCESS EXCLUSIVE`:** `ADD COLUMN` com default volátil,
   `serial`/identity, `GENERATED ... STORED`, `ALTER COLUMN TYPE`, `VACUUM FULL`, `CLUSTER`. Coluna
   nova nullable, backfill em lotes, troca. Default constante e `now()` não reescrevem (PG 11+).
7. **`DROP`/`RENAME`/`TRUNCATE` só na fase contract** do expand-contract, com a marca
   `-- pg-contract: <quem parou de ler>`. Backfill sem `WHERE` (`UPDATE`/`DELETE`) é vetado.
8. **Autovacuum nunca desligado.** Tabela grande ganha parâmetros próprios; `age(datfrozenxid)`
   vigiado e alertado muito antes do wraparound.
9. **`max_connections` baixo e pooler na frente.** A aplicação fala com o PgBouncer; nunca
   centenas de conexões diretas. Sessão com estado (`SET`, advisory lock de sessão) não vai para
   o modo transação.
10. **Backup só vale com restore testado.** Base + WAL contínuo (PITR), cifrado, em conta/bucket
    separado, com `restore` automatizado e medido (RPO/RTO) em ambiente descartável, no mínimo
    mensal. `pg_dump` não é o backup de record.
11. **Failover é ensaiado, não presumido.** Réplica sem monitor de lag e sem ensaio de promoção é
    enfeite; slot de replicação sem teto (`max_slot_wal_keep_size`) enche o disco.
12. **Menor privilégio de verdade:** role dona do schema (migration) ≠ role da aplicação (só DML)
    ≠ leitura ≠ admin. Aplicação nunca é superuser nem owner. `pg_hba.conf` com `scram-sha-256` e
    TLS; nada de `trust`.
13. **Multi-tenant com RLS ligada e `FORCE`**, tenant vindo de `SET LOCAL`/`set_config(..., true)`
    dentro da transação, **fail-closed** quando o contexto falta. Dono da tabela, superuser e
    `BYPASSRLS` ignoram RLS: a role da aplicação não pode ser nenhum deles.
14. **Credencial nunca em migration, `.sql` versionado ou log.** `CREATE ROLE ... PASSWORD '...'`
    literal é vetado; a senha vem do cofre na hora do provisionamento.
15. <!-- herdado:engineering/orquestracao:curto -->**Orquestrador não desenvolve; subagent barato executa.** O agent principal só planeja, despacha e revisa; ação onerosa vira micro-tasks para o executor mais barato que resolve: `haiku` (mecânico) / `sonnet` (código; falhou → mesmo subagent corrige, até 2 rodadas) → Codex `gpt-5.6-terra` → Cursor → subagent `opus` (motivo) → `park`; **visual vai direto ao Codex**; **imagem nunca pelo Claude: detectar Codex/Gemini e perguntar ao usuário qual usar (Codex é a sugestão), nunca API de imagem paga**; papéis em `agentes.toml`. No overdev, cada item do checklist vai a um subagent e o principal revisa antes do `- [x]`. **Sem frota ociosa:** idle com pendência volta ao trabalho; dependente de outro agent → mata e enfileira com gatilho; terminou → mata (§9.6). Detalhe: `schematize-engineering` → `references/orquestracao.md` §9.<!-- /herdado -->

## Regra de mídia

Diagrama de topologia (réplicas, pooler, backup) vai em Mermaid ou texto no repo. Imagem ou mídia
gerada **nunca** por modelo Claude: detecte Codex e Gemini disponíveis e **pergunte ao usuário
qual usar**. Nenhum disponível: avise sem rodeio que visual gerado pelo Claude tem qualidade
inversamente proporcional à de código (sai ruim de verdade) e ofereça alternativas — instalar
Codex ou Gemini, imagem de banco com licença comercial, ou asset do cliente. Claude é o melhor em
código.

## Relação com as outras skills

- **`schematize-database`** — o desenho. Ela decide *qual* coluna, índice e constraint; esta decide
  *como aplicar sem derrubar* e como o motor se comporta depois.
- **`schematize-data`** — o dado em movimento (CDC, outbox, warehouse). A replicação lógica daqui é
  o mecanismo; o contrato de propagação é de lá.
- **`schematize-infra`** — DR e plataforma. Aqui o ferramental e os números do Postgres.
- **`schematize-observability`** — como instrumentar; aqui, quais sinais do Postgres valem alerta
  (lag, wraparound, conexões, bloat, archiver).
- **`schematize-pentest`** — tenta furar RLS, role excessiva e `pg_hba.conf`.
- **`schematize-engineering`** — a base: DoD, archive, fluxo de ambientes, efeito externo.
