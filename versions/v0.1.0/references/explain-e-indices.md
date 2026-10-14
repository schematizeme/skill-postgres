# EXPLAIN e índices na prática

O **desenho** do índice (qual coluna, ordem em composto, parcial, cobertura) é da
`schematize-database → references/normalizacao-chaves-indices.md`. Aqui: **medir, decidir e
criar sem derrubar**.

## 1. Comece pelo que está caro

`pg_stat_statements` responde "o que vale otimizar":

```sql
SELECT queryid, calls, round(total_exec_time) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms, rows,
       shared_blks_read, left(query, 80) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 20;
```

Ordene por **`total_exec_time`** (impacto no servidor), não só por `mean_exec_time`: a query de 5 ms
chamada 50 milhões de vezes custa mais que a de 5 s chamada duas. Zere (`pg_stat_statements_reset()`)
depois de um deploy para medir só o novo comportamento.

## 2. EXPLAIN que prova

```sql
EXPLAIN (ANALYZE, BUFFERS, SETTINGS) SELECT ...;
```

- **`ANALYZE` executa a query de verdade.** Em `INSERT`/`UPDATE`/`DELETE`, envolva:
  `BEGIN; EXPLAIN (ANALYZE, BUFFERS) UPDATE ...; ROLLBACK;`.
- A partir do PG 18, `EXPLAIN ANALYZE` já inclui `BUFFERS`; nas versões anteriores peça explicitamente.
- Rode no **dado de tamanho real** (cópia de prd restaurada do backup, `references/backup-e-pitr.md`).
  Plano de tabela com 100 linhas mente.

### O que ler, nesta ordem

1. **`rows` estimado vs `actual rows`.** Diferença de ordem de grandeza = estatística ruim
   (`ANALYZE tabela`, `ALTER TABLE ... ALTER COLUMN ... SET STATISTICS 500`, estatística estendida
   `CREATE STATISTICS` para colunas correlacionadas). Plano ruim quase sempre nasce aqui.
2. **`Seq Scan` com filtro seletivo** sobre tabela grande (`Rows Removed by Filter` enorme) = falta
   índice. `Seq Scan` em tabela pequena ou em consulta que lê boa parte da tabela é correto.
3. **`Buffers: shared read` alto** = leu do disco; `shared hit` = cache. Compare o plano frio e o quente.
4. **`Sort Method: external merge Disk`** ou `Batches > 1` em hash = `work_mem` curto para aquele nó.
5. **`Nested Loop` com `loops` enorme** sobre o lado interno sem índice.
6. **`Heap Fetches` alto num `Index Only Scan`** = visibility map desatualizado (vacuum atrasado).
7. **`Rows Removed by Index Recheck` / `Heap Blocks: lossy`** em bitmap = `work_mem` curto.

## 3. Índice sem derrubar a produção

```sql
SET lock_timeout = '3s';
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pedidos_user_criado
  ON pedidos (user_id, criado_em DESC);
```

- **`CONCURRENTLY` não roda dentro de transação** (o Postgres recusa: verificado em PG 18.6) e leva
  duas passadas na tabela. Configure o runner de migrations para não envolver esse arquivo em
  transação e deixe **um** `CREATE INDEX CONCURRENTLY` por migration.
- Se falhar (deadlock, violação de unicidade, cancelamento), sobra um índice **`INVALID`** que
  ainda custa escrita: ache e remova.
  ```sql
  SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
  DROP INDEX CONCURRENTLY nome_do_invalido;
  ```
- Confirme que ele é usado: `EXPLAIN` depois do `ANALYZE tabela`; o índice novo só ajuda se o
  planner o escolher.
- `skip scan` do PG 18 deixa um B-tree composto servir a consultas que não filtram a primeira
  coluna quando ela tem poucos valores distintos; **não** substitui o índice certo.

## 4. Índice que não deveria existir

```sql
-- não usado desde o último reset das estatísticas (cuidado: réplica tem as suas)
SELECT s.indexrelid::regclass AS indice, s.relid::regclass AS tabela,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS tamanho, s.idx_scan
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.idx_scan = 0 AND NOT i.indisunique AND NOT i.indisprimary
ORDER BY pg_relation_size(s.indexrelid) DESC;
```

Antes de dropar: o período de estatística cobre um ciclo completo do negócio (fechamento de mês)?
A réplica de leitura usa? Drop é `DROP INDEX CONCURRENTLY` e, em dúvida, é contract: registre.
Também ache **FK sem índice** na coluna filha (join e `ON DELETE` viram varredura) e **índices
duplicados** (mesmas colunas, mesma ordem).

## 5. Plano que muda do nada

Plano bom que vira ruim sem mudança de código quase sempre é: estatística velha (vacuum/analyze
atrasado), parâmetro `$1` com valor atípico (plano genérico em prepared statement; veja
`plan_cache_mode`), crescimento do dado que cruzou um limiar (de index scan para seq scan), ou
bloat. `auto_explain` com `log_min_duration` captura o plano real na hora do problema.
