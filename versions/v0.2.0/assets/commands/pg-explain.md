---
description: schematize-postgres — lê um plano EXPLAIN (ANALYZE, BUFFERS) e propõe índice ou reescrita, criando sem lock
argument-hint: "<query ou plano colado>"
---

# /pg-explain — medir antes de indexar

1. **Obtenha o plano real:** se só há a query, entregue o comando
   `EXPLAIN (ANALYZE, BUFFERS, SETTINGS) <query>;` (em `BEGIN ... ROLLBACK` se for `INSERT`/`UPDATE`/
   `DELETE`) para ser rodado em dado de tamanho real. Plano de tabela pequena não vale.
2. **Leia na ordem de `references/explain-e-indices.md` §2:** estimado vs real; `Seq Scan` com filtro
   seletivo; `Buffers` (hit/read); `Sort Method` em disco; `Nested Loop` com `loops` alto;
   `Heap Fetches` em `Index Only Scan`.
3. **Diagnostique a causa** antes do remédio: estatística velha (`ANALYZE`, `SET STATISTICS`,
   `CREATE STATISTICS`), falta de índice, `work_mem`, bloat, plano genérico em prepared statement.
4. **Proponha o menor remédio:** reescrita da query, índice (coluna e ordem pelo predicado; o
   desenho é da `schematize-database`) criado com `CREATE INDEX CONCURRENTLY` em migration própria,
   fora de transação, com `lock_timeout`. Diga o custo (escrita, espaço) e como confirmar o ganho
   (`EXPLAIN` depois, `pg_stat_statements`).
5. Rode o gate no `.sql` produzido: `bash .claude/skills/schematize-postgres/scripts/check-pg-migration.sh <arquivo>`.
