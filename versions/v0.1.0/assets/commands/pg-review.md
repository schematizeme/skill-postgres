---
description: schematize-postgres — revisa migrations e configuração do PostgreSQL contra o piso: roda o gate e lê o que a máquina não lê
argument-hint: "[diretório de migrations ou arquivo .sql]"
---

# /pg-review — DDL é correto na máquina do dev e perigoso em tabela viva

## 1. A máquina primeiro

```bash
bash .claude/skills/schematize-postgres/scripts/check-pg-migration.sh "${ARGUMENTS:-.}"
```
`0` passa · `1` reprova · `2` **nada para verificar**, que não é aprovação.

O gate cobre: DDL sem `lock_timeout` antes dele; `CREATE`/`DROP` de índice e `REINDEX` sem
`CONCURRENTLY`; `CONCURRENTLY` dentro de transação; `ADD COLUMN` com default volátil, `serial`,
identity ou `GENERATED ... STORED`; `ADD COLUMN NOT NULL` sem default; `SET NOT NULL` direto;
`ALTER COLUMN TYPE`; FK e CHECK sem `NOT VALID`; `UNIQUE`/`PRIMARY KEY` sem `USING INDEX`;
`DROP`/`RENAME`/`TRUNCATE` sem a marca de contract; `UPDATE`/`DELETE` sem `WHERE`; role
privilegiada, senha literal, `GRANT ALL`/`PUBLIC`, RLS desligada, policy `USING (true)`.
Waiver: `-- pg-ok: <regra> <motivo>`, `-- pg-ok-file: <regra> <motivo>`, `-- pg-contract: <motivo>`.

## 2. Depois, o que a máquina não lê

- **Tamanho real:** a tabela tem quantas linhas em prd? O "rápido" em dev dura quanto lá? Foi
  ensaiado em cópia com volume real?
- **Expand-contract:** o código em produção hoje lê a coluna que esta migration derruba/renomeia?
  Existe a migration de contract com o release que parou de ler?
- **Backfill:** em lotes, retomável, com pausa e métrica de lag de réplica; fora da migration de DDL.
- **Runner:** o `CREATE INDEX CONCURRENTLY` roda sem transação? Uma mudança arriscada por migration?
- **Role:** a migration roda como `app_owner`, e a aplicação como `app_rw` (sem DDL, sem dono)?
- **RLS:** tabela nova com `tenant_id` tem `ENABLE` + `FORCE` + policy com `WITH CHECK`? Há teste de
  dois tenants?
- **Config (se o diff tocar `postgresql.conf`/`pg_hba.conf`):** `pg_stat_statements` carregado,
  autovacuum ligado, `max_connections` coerente com o pooler, `scram-sha-256`, sem `trust`,
  `max_slot_wal_keep_size` definido.
- **Backup:** a mudança afeta o PITR (nova tablespace, novo banco, `archive_command`)?
- **Reversão:** o `down` existe e foi aplicado? Se não há volta (contract), o PR diz "restore do
  backup" e cita o último ensaio.

## 3. Feche

Achado vira correção no mesmo PR ou item de checklist com dono. O vermelho do próprio gate:
`bash .claude/skills/schematize-postgres/scripts/check-pg-migration.test.sh`.
