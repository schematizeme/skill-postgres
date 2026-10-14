# Versão suportada e configuração

> Números de versão e datas de EOL moram em `stack-versoes.md` (volátil). Aqui, a regra.

## 1. Versão

- O PostgreSQL publica **um major por ano** e dá **5 anos de suporte** a cada um. Depois do EOL
  não há correção de segurança: rodar major fora de suporte é incidente agendado.
- **Projeto novo:** o major mais recente que já tenha o primeiro ou segundo minor publicado (menos
  arestas), ou o anterior se o provedor gerenciado ainda não o oferece. Registre em ADR.
- **Minor** (`18.5` -> `18.6`): só troca de binário e restart, sem `pg_upgrade`, e traz correção
  de segurança e de corrupção. Aplique **todo** minor, em janela, em hml antes de prd. Atrasar
  minor é a dívida mais barata de pagar e a mais cara de adiar.
- **Major:** `references/upgrade.md`. O EOL do major em uso entra no calendário do time com pelo
  menos **6 meses** de folga.
- Em serviço gerenciado (RDS, Cloud SQL, Neon, Supabase...) a regra é a mesma: o provedor também
  tem calendário de EOL, e costuma forçar o upgrade em data que você não escolheu.

## 2. Parâmetros que importam (ponto de partida, sempre medir)

Os valores abaixo são **começo de conversa**, não receita. Mude um por vez, com métrica antes e
depois.

| Área | Parâmetro | Regra |
|---|---|---|
| Memória | `shared_buffers` | começa em ~25% da RAM do host dedicado |
| | `effective_cache_size` | ~50-75% da RAM (só informa o planner, não aloca) |
| | `work_mem` | é **por nó de plano, por conexão**: `work_mem x conexões x nós` pode estourar a RAM. Suba por role/sessão (`SET LOCAL`) para o relatório pesado, não global |
| | `maintenance_work_mem` | maior que `work_mem` (vacuum, índice); com autovacuum, veja `autovacuum_work_mem` |
| Conexões | `max_connections` | baixo (dezenas a poucas centenas) com **pooler** (`references/pooling.md`) |
| WAL | `wal_level` | `replica` por default; `logical` se houver CDC/replicação lógica |
| | `max_wal_size`, `checkpoint_timeout` | checkpoint por tempo (ex.: 15 min) e `max_wal_size` folgado: checkpoint "requested" frequente no log = `max_wal_size` curto |
| | `checkpoint_completion_target` | `0.9` |
| | `wal_compression` | ligar quando houver CPU de sobra |
| | `max_slot_wal_keep_size` | **sempre definido**: um slot parado não pode encher o disco |
| Planner | `random_page_cost` | ~`1.1` em SSD/NVMe (o default `4` é de disco giratório) |
| | `effective_io_concurrency` | ajustar ao armazenamento; no PG 18 há `io_method` (`worker` default; `io_uring` em Linux compatível) |
| Autovacuum | `autovacuum` | **nunca `off`**. Ajuste fino por tabela (`references/vacuum-e-bloat.md`) |
| Timeouts | `statement_timeout` | por role da aplicação (ex.: segundos), mais alto só para a role de migration/relatório |
| | `idle_in_transaction_session_timeout` | ligado (ex.: 1-5 min): transação esquecida segura o vacuum |
| | `lock_timeout` | na migration (`SET lock_timeout`), e um default curto na role da app |
| Segurança | `password_encryption` | `scram-sha-256` |
| | `ssl` | `on`, e `hostssl` no `pg_hba.conf` (`references/roles-e-rls.md`) |
| Integridade | checksums de página | habilitados (default do `initdb` a partir do PG 18; antes, `initdb --data-checksums`) |

## 3. Log que serve

```
log_min_duration_statement = 500ms     # ajuste ao SLO
log_lock_waits = on                    # espera de lock > deadlock_timeout vira linha de log
log_temp_files = 0                     # spill em disco por sort/hash: sinal de work_mem
log_autovacuum_min_duration = 0        # ver o que o autovacuum faz
log_checkpoints = on
log_line_prefix = '%m [%p] %q%u@%d app=%a '
```

Nunca logar valor de parâmetro de query com dado pessoal: `log_parameter_max_length` baixo ou
zero em tabelas com PII, e `log_min_duration_statement` em vez de `log_statement = 'all'`.

## 4. Extensões

- **`pg_stat_statements` é obrigatória** em todo cluster, com `track_io_timing = on`:
  ```
  shared_preload_libraries = 'pg_stat_statements'
  ```
  e `CREATE EXTENSION pg_stat_statements;` em cada banco (precisa de restart para o preload).
  `compute_query_id` fica em `auto`.
- Útil e opcional: `pg_trgm`, `pgstattuple` (medir bloat), `amcheck` (verificar índice e heap),
  `auto_explain` (plano das lentas no log), `pgaudit` (auditoria exigida por norma).
- Extensão é superfície de ataque e de upgrade: instale só o que usa, com versão registrada, e
  rode `ALTER EXTENSION ... UPDATE` depois de cada major.
