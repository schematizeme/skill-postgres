# Locks e migrations seguras em tabela viva

O **método** expand-contract é da `schematize-database → references/migrations.md`. Aqui: **o que
cada comando faz no motor** e a receita segura. O gate `scripts/check-pg-migration.sh` aplica
estas regras.

## 1. A fila de lock é o perigo real

Um `ALTER TABLE` pede `ACCESS EXCLUSIVE`, que conflita com **todo** lock, até um `SELECT`. Se uma
transação longa está lendo a tabela, o `ALTER` **espera**, e **todas as queries que chegarem
depois ficam na fila atrás dele**. O DDL "rápido" derruba a aplicação por causa da espera, não
do trabalho.

Defesa, sempre as duas:

```sql
SET lock_timeout = '3s';       -- desiste em vez de formar fila
SET statement_timeout = '15min'; -- teto de duração do que rodar (ajuste; 0 só com motivo)
```

Se estourar `lock_timeout`, **tente de novo** (retry com backoff no runner, ou manualmente na
janela mais calma). Provado em PG 18.6: com outra sessão segurando `ACCESS SHARE`, o `ALTER TABLE`
com `lock_timeout = '1s'` falha com `canceling statement due to lock timeout` e não trava ninguém.

Quem bloqueia quem: `SELECT pid, pg_blocking_pids(pid), wait_event_type, left(query,60) FROM
pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;`

## 2. Operação x risco

| Operação | Lock / custo | Seguro? | Receita |
|---|---|---|---|
| `CREATE INDEX` | bloqueia escrita | não | `CREATE INDEX CONCURRENTLY` |
| `CREATE INDEX CONCURRENTLY` | não bloqueia; 2 passadas | sim, **fora de transação** | uma por migration; limpe `INVALID` |
| `DROP INDEX` | ACCESS EXCLUSIVE | não | `DROP INDEX CONCURRENTLY` |
| `REINDEX` | bloqueia | não | `REINDEX ... CONCURRENTLY` |
| `ADD COLUMN` nullable, sem default | breve, só catálogo | sim | com `lock_timeout` |
| `ADD COLUMN ... DEFAULT <constante>` ou `now()` | só catálogo (PG 11+) | sim | verificado: sem reescrita |
| `ADD COLUMN ... DEFAULT <volátil>` (`gen_random_uuid()`, `random()`, `clock_timestamp()`, `nextval`), `serial`, identity | **reescreve a tabela** | não | nullable sem default, backfill em lotes, depois `SET DEFAULT` |
| `ADD COLUMN ... GENERATED ... STORED` | reescreve | não | backfill em lotes, ou coluna `VIRTUAL` (PG 18) |
| `ADD COLUMN ... NOT NULL` sem default | falha com linhas | não | nullable + backfill + `CHECK ... NOT VALID` |
| `ALTER COLUMN SET NOT NULL` | varre a tabela sob ACCESS EXCLUSIVE | não | antes, `CHECK (col IS NOT NULL) NOT VALID` + `VALIDATE`; o `SET NOT NULL` então pula a varredura (PG 12+). No PG 18: `ADD CONSTRAINT ... NOT NULL col NOT VALID` + `VALIDATE` |
| `ALTER COLUMN TYPE` | geralmente reescreve | não | coluna nova + backfill + troca. **Exceção binária-compatível** (ex.: `varchar(50)` -> `varchar(100)`: verificado, sem reescrita) com waiver e motivo. `int` -> `bigint` **reescreve** (verificado) |
| `ADD FOREIGN KEY` | varre; trava escrita nas duas tabelas | não | `... NOT VALID` e depois `VALIDATE CONSTRAINT` (lock leve, `SHARE UPDATE EXCLUSIVE`) |
| `ADD CHECK` | varre sob lock | não | `... NOT VALID` + `VALIDATE` |
| `ADD UNIQUE` / `PRIMARY KEY` | constrói índice sob lock | não | `CREATE UNIQUE INDEX CONCURRENTLY` + `ADD CONSTRAINT ... USING INDEX` |
| `DROP COLUMN` | rápido, **destrói dado** | só na fase contract | `-- pg-contract: ...` |
| `RENAME` coluna/tabela | rápido, **quebra o código em voo** | só na fase contract | coluna/tabela nova + dual-write |
| `UPDATE`/`DELETE` em massa | uma transação gigante, WAL, bloat | não | lotes com `WHERE` e `LIMIT` |
| `VACUUM FULL`, `CLUSTER` | reescreve, ACCESS EXCLUSIVE | não | `pg_repack` |
| `DROP TABLE`, `TRUNCATE` | destrói dado | só na fase contract | `-- pg-contract: ...` |
| Criar tabela nova | não afeta ninguém | sim | o gate dispensa índice/FK/CHECK na tabela criada no mesmo arquivo |

## 3. Receitas

**Coluna NOT NULL com default calculado (volátil):**

```sql
-- migration 1 (expand): sem reescrita
SET lock_timeout = '3s';
ALTER TABLE eventos ADD COLUMN ref uuid;
-- backfill (fora da migration, job em lotes; veja §4)
-- migration 2: depois do backfill completo
SET lock_timeout = '3s';
ALTER TABLE eventos ADD CONSTRAINT eventos_ref_nn CHECK (ref IS NOT NULL) NOT VALID;
ALTER TABLE eventos VALIDATE CONSTRAINT eventos_ref_nn;
ALTER TABLE eventos ALTER COLUMN ref SET NOT NULL;   -- instantâneo: a constraint validada prova
ALTER TABLE eventos DROP CONSTRAINT eventos_ref_nn;
ALTER TABLE eventos ALTER COLUMN ref SET DEFAULT gen_random_uuid();  -- só vale p/ linhas novas
```

**FK:**

```sql
SET lock_timeout = '3s';
ALTER TABLE pedidos
  ADD CONSTRAINT pedidos_user_fk FOREIGN KEY (user_id) REFERENCES users (id) NOT VALID;
ALTER TABLE pedidos VALIDATE CONSTRAINT pedidos_user_fk;   -- em outra transação/migration
```

**Unique:**

```sql
SET lock_timeout = '3s';
CREATE UNIQUE INDEX CONCURRENTLY ux_users_email ON users (email);   -- migration própria, fora de tx
ALTER TABLE users ADD CONSTRAINT uq_users_email UNIQUE USING INDEX ux_users_email;
```

## 4. Backfill em lotes

Nunca na migration de DDL. Um job idempotente, retomável, com pausa e métrica:

```sql
-- repetir até afetar 0 linhas; commit a cada lote; dormir entre lotes (sobra para replicação e vacuum)
WITH lote AS (
  SELECT id FROM eventos WHERE ref IS NULL ORDER BY id LIMIT 5000 FOR UPDATE SKIP LOCKED
)
UPDATE eventos e SET ref = gen_random_uuid() FROM lote WHERE e.id = lote.id;
```

Acompanhe lag de réplica e fila de vacuum; reduza o lote se o lag crescer. Backfill de dado
entre sistemas é pipeline: `schematize-data → references/armazenamento.md`.

## 5. Runner de migrations

- **Uma mudança arriscada por migration**, e DDL e backfill em migrations separadas.
- `CREATE INDEX CONCURRENTLY` exige execução **sem transação**; cada runner tem seu jeito
  (confira a documentação do seu: Flyway, Liquibase, sqlx, Atlas, golang-migrate, Ecto, EF Core,
  Rails). O gate acusa `BEGIN` no mesmo arquivo.
- A migration roda com a **role de migration** (dona do schema), nunca com a da aplicação
  (`references/roles-e-rls.md`).
- Reversível: `down` testado quando o expand tem volta; o `down` da fase contract é restaurar do
  backup, e isso se diz no PR.
- Ensaie em cópia com volume real; meça o tempo e o lock. "Passou em dev" não prova nada para DDL.
