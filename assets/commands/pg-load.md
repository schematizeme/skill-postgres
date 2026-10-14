---
description: schematize-postgres — carrega à força TODO o corpo normativo de operação do PostgreSQL e passa a aplicá-lo nesta sessão.
---
Carregue **agora** o corpo normativo da skill `schematize-postgres`. A partir daqui, nesta sessão,
isto **não é opcional**.

1. **Leia na íntegra, sem trabalhar de memória.** Caminho:
   `.claude/skills/schematize-postgres/references/*.md` (projeto) ou `~/.claude/skills/schematize-postgres/references/*.md` (global):
   - `versao-e-config.md` — major suportado e EOL, minor, parâmetros, log, `pg_stat_statements`.
   - `explain-e-indices.md` — `EXPLAIN (ANALYZE, BUFFERS)`, ler o plano, índice `CONCURRENTLY`, inválido e não usado.
   - `vacuum-e-bloat.md` — autovacuum por tabela, o que segura o xmin, wraparound, bloat sem `VACUUM FULL`.
   - `locks-e-migrations.md` — fila de lock, `lock_timeout`, tabela operação x risco, receitas, backfill.
   - `pooling.md` — PgBouncer: modos, o que o modo transação quebra, dimensionamento, autenticação.
   - `replicacao-e-failover.md` — física e lógica, sync/async, slots, failover, ensaio.
   - `backup-e-pitr.md` — pgBackRest/WAL-G, PITR, restore testado, RPO/RTO, LGPD.
   - `upgrade.md` — minor e major, `pg_upgrade`, collation, checksums, rollback.
   - `roles-e-rls.md` — roles de menor privilégio, `pg_hba.conf`, RLS com `FORCE` e pooler.
   - `stack-versoes.md` — anexo volátil: versões, EOL, fontes e o que foi executado.
2. **Rode o gate nas migrations do repo atual** antes de opinar sobre estilo:
   `bash .claude/skills/schematize-postgres/scripts/check-pg-migration.sh .`
3. **Aplique daqui em diante** a todo `.sql` e `postgresql.conf` que você escrever ou tocar, e diga
   qual piso está aplicando quando ele mudar o que você ia fazer. **Nunca rode DDL em produção**
   sem passar pelo gate, `lock_timeout` e o ensaio.
