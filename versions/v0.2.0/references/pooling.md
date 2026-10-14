# Pooling de conexões (PgBouncer)

Cada conexão Postgres é um processo (~MBs, mais o custo de contexto). Centenas de conexões
ociosas degradam o servidor mesmo sem carga. A regra da casa: **`max_connections` baixo, pooler na
frente, aplicação fala com o pooler**. Pool no cliente (da linguagem) é complemento, não substituto
quando há muitas instâncias.

## 1. Modos do PgBouncer

| Modo | A conexão do servidor volta ao pool... | Quando |
|---|---|---|
| `session` | quando o cliente desconecta | sessão com estado; ganho pequeno |
| `transaction` | ao fim de cada transação | **default para aplicações web/API**: multiplexa milhares de clientes em dezenas de servidores |
| `statement` | ao fim de cada comando | quase nunca: proíbe transação de múltiplos comandos |

### O que o modo `transaction` quebra

Estado de **sessão** não sobrevive entre transações: `SET`/`SET SESSION`, `LISTEN/NOTIFY`,
`pg_advisory_lock` de sessão (use `pg_advisory_xact_lock`), cursores `WITH HOLD`, tabelas
temporárias de sessão, e `PREPARE` manual. Prepared statements do protocolo funcionam a partir do
PgBouncer 1.21 com `max_prepared_statements > 0`. Consequência para multi-tenant/RLS: o contexto
do tenant vai por **`SET LOCAL`/`set_config(..., true)` dentro da transação**, nunca `SET`
(`references/roles-e-rls.md`). Ferramentas administrativas (`pg_dump`, `pg_basebackup`, migration
com `CONCURRENTLY`/advisory lock) conectam **direto** ao Postgres, em porta/role reservada.

## 2. Dimensionamento

- O tamanho do pool de servidor é função de **núcleos e I/O do banco**, não de clientes:
  ponto de partida na ordem de 2-4x os núcleos, e meça. Mais conexões ativas que isso só enfileira
  dentro do banco com mais troca de contexto.
- `default_pool_size`, `max_client_conn` (clientes), `reserve_pool_size` (rajada) e
  `max_db_connections` (teto por banco, somando todos os pools, abaixo de `max_connections` menos
  as reservadas a admin e réplica).
- `server_idle_timeout`, `query_wait_timeout` (cliente que espera demais recebe erro em vez de
  empilhar) e `client_idle_timeout` coerentes com os timeouts da aplicação.
- Pooler **por cluster** é ponto único de falha: ao menos duas instâncias atrás de um VIP/DNS, ou
  pooler no mesmo host de cada aplicação, conforme a topologia.

## 3. Autenticação e segurança

- `auth_type = scram-sha-256`; credenciais por `auth_query` (role dedicada, `SECURITY DEFINER`)
  ou `auth_file` gerado do cofre, nunca `trust`, nunca `md5`.
- TLS cliente->pooler e pooler->servidor (`client_tls_sslmode`, `server_tls_sslmode = verify-full`).
- `admin_users`/`stats_users` mínimos; console admin fora da rede pública.
- **Mantenha o PgBouncer atualizado:** a versão 1.26.1 (2026-10-14) corrige três CVEs de
  autenticação e negação de serviço (detalhe e fonte em `stack-versoes.md`).

## 4. Observar

`SHOW POOLS;` (`cl_waiting` > 0 sustentado = pool curto ou query lenta), `SHOW STATS;` (`avg_wait_time`),
`SHOW CLIENTS/SERVERS`. Alerte em `cl_waiting` e em `maxwait`.
