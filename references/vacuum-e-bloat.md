# Vacuum, autovacuum, wraparound e bloat

## 1. Por que existe

MVCC: `UPDATE` e `DELETE` não sobrescrevem, deixam versão morta. O vacuum (1) recicla o espaço,
(2) atualiza o visibility map (necessário para `Index Only Scan`), (3) congela transaction IDs
antigos para evitar o **wraparound**, e (4) o `ANALYZE` mantém as estatísticas do planner.
Autovacuum desligado ou atrasado = tabela inchada, plano ruim e, no limite, o banco parando para
escrita.

## 2. Autovacuum: ligado e ajustado por tabela

O default dispara o vacuum quando 20% da tabela mudou (`autovacuum_vacuum_scale_factor = 0.2`).
Em tabela de 500 milhões de linhas isso é 100 milhões de mortas. Ajuste **por tabela** quente:

```sql
ALTER TABLE eventos SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_vacuum_insert_scale_factor = 0.02,
  autovacuum_analyze_scale_factor = 0.01
);
```

Se o autovacuum não acompanha, o gargalo costuma ser o custo (`autovacuum_vacuum_cost_limit`,
`autovacuum_max_workers`) ou I/O, não o gatilho. Veja `log_autovacuum_min_duration` e
`pg_stat_progress_vacuum`. **`autovacuum = off` é vetado**, nem "temporariamente".

## 3. O que segura o vacuum (e o bloat)

O vacuum só remove versão morta que **nenhuma** transação ainda pode ver. Quem segura o `xmin`:

```sql
-- transações longas e "idle in transaction"
SELECT pid, usename, state, now() - xact_start AS idade, left(query, 60)
FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY xact_start LIMIT 10;
-- slots de replicação parados
SELECT slot_name, active, restart_lsn, xmin, catalog_xmin FROM pg_replication_slots;
-- transações preparadas esquecidas
SELECT * FROM pg_prepared_xacts;
```

Também `hot_standby_feedback = on` numa réplica com consulta longa. Remédio: `idle_in_transaction_session_timeout`,
`statement_timeout`, dropar slot órfão, `max_slot_wal_keep_size`, e consulta analítica longa em
réplica própria.

## 4. Wraparound: o alarme tem de tocar cedo

```sql
SELECT datname, age(datfrozenxid) AS idade FROM pg_database ORDER BY 2 DESC;
SELECT c.oid::regclass, age(c.relfrozenxid) FROM pg_class c WHERE c.relkind IN ('r','m','t')
ORDER BY 2 DESC LIMIT 10;
```

O autovacuum entra em modo agressivo ao passar de `autovacuum_freeze_max_age` (default
200 milhões, valor verificado em PG 18.6). O limite duro é ~2 bilhões; perto dele o banco se
recusa a aceitar escrita. **Alerta** em ~50% do `freeze_max_age` sustentado (algo está impedindo
o congelamento) e crítico bem antes de 1 bilhão. Em emergência: `VACUUM (FREEZE, VERBOSE) tabela`
na mais velha, depois de remover o que segura o `xmin`.

## 5. Bloat: medir e corrigir sem `VACUUM FULL`

Meça com `pgstattuple` (`pgstattuple_approx` para tabela grande) em vez de adivinhar:

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
SELECT * FROM pgstattuple_approx('pedidos');
```

| Remédio | Lock | Quando |
|---|---|---|
| `VACUUM` comum / autovacuum | não bloqueia | já recicla espaço para reuso, **não devolve** ao SO (exceto o fim do arquivo) |
| `REINDEX INDEX CONCURRENTLY` | não bloqueia escrita | índice inchado (muito comum) |
| `pg_repack` / `pg_squeeze` | breve no início/fim | tabela inchada e precisa devolver espaço, online |
| `VACUUM FULL`, `CLUSTER` | **ACCESS EXCLUSIVE**, reescreve | **vetado em prd na migration**; só em janela com a tabela fora do ar |
| Particionar por tempo e `DROP` da partição | rápido | histórico que cresce: apagar partição não gera bloat, `DELETE` em massa gera |

Prevenção: `fillfactor` menor (ex.: 85-90) em tabela com muito `UPDATE` ajuda os updates **HOT**
(sem tocar índice); não indexe coluna que muda sempre; apague em lotes pequenos; evite o padrão
"fila em tabela com `DELETE`" sem partição.
