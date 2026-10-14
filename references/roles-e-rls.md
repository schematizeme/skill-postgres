# Roles de menor privilégio e RLS multi-tenant

O desenho multi-tenant (coluna `tenant_id`, no índice, deny-by-default) é da
`schematize-database → references/seguranca-pii.md`. Aqui: **o mecanismo de enforcement no motor**.

## 1. Quem é quem

| Role | Pode | Não pode |
|---|---|---|
| `app_owner` (migration) | `CREATE`/`ALTER`/`DROP` no schema; é **dona** das tabelas | ser usada pela aplicação em runtime |
| `app_rw` (aplicação) | `SELECT/INSERT/UPDATE/DELETE` nas tabelas, `USAGE` em sequences | DDL, ser dona, `SUPERUSER`, `BYPASSRLS` |
| `app_ro` (leitura, BI, réplica) | `SELECT` | qualquer escrita |
| `admin` (humano, break-glass) | gestão; acesso auditado e com prazo | rodar a aplicação |

- Padrão: **grupo `NOLOGIN`** com os privilégios + **role `LOGIN`** que herda do grupo (rotacionar
  credencial sem refazer grants).
- `REVOKE ALL ON DATABASE ... FROM PUBLIC`; `REVOKE CREATE ON SCHEMA public FROM PUBLIC` (o default
  de PG 15+ já remove, confira em bancos antigos).
- `ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLES TO app_rw;` para o que ainda será criado.
- **Nunca** `GRANT ALL`, nunca `GRANT ... TO PUBLIC`, nunca `SUPERUSER`/`CREATEROLE`/`CREATEDB`/
  `BYPASSRLS` para role de aplicação. O gate acusa (`grant-amplo`, `grant-publico`, `role-privilegiada`).
- Segredos: a senha da role vem do cofre no provisionamento; `PASSWORD '...'` literal em `.sql`
  versionado vai para o git e para o log do servidor (`senha-literal`). Rotação por cofre.
  Identidade de **pessoa** acessando o banco passa pelo IdP da casa (`schematize-engineering → references/iam.md`), não por role compartilhada.

## 2. `pg_hba.conf`

```
# TYPE   DATABASE  USER      ADDRESS        METHOD
hostssl  app       app_rw    10.0.1.0/24    scram-sha-256
hostssl  all       admin     10.0.9.0/28    scram-sha-256
hostssl  replication replicator 10.0.2.0/24 scram-sha-256
host     all       all       0.0.0.0/0      reject
```

Sem `trust`. Sem `md5`. Sem `host` em claro. Endereços mínimos. Porta 5432 fora da internet
pública (rede privada, firewall, security group).

## 3. RLS

```sql
ALTER TABLE pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pedidos FORCE ROW LEVEL SECURITY;   -- vale também para o dono da tabela

CREATE POLICY tenant_isolamento ON pedidos
  USING      (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
```

Pontos que a máquina não pega:

- **Quem ignora RLS:** superuser, roles com `BYPASSRLS` e, **sem `FORCE`**, o dono da tabela. Por
  isso a aplicação não é dona nem privilegiada, e a tabela leva `FORCE`.
- **Fail-closed:** `current_setting('app.tenant_id', true)` devolve `NULL` quando o parâmetro não
  foi definido; `tenant_id = NULL` é nulo, logo nenhuma linha passa. Esqueceu de setar o contexto
  = zero linhas, não todas. Nunca escreva policy `USING (true)` (gate: `policy-permissiva`).
- **Contexto na transação, com pooler:** `SELECT set_config('app.tenant_id', $1, true)` ou `SET LOCAL`
  no início de **cada** transação. `SET` de sessão vaza para a próxima transação que reusar a
  mesma conexão no PgBouncer em modo transação, e o tenant errado enxerga dado alheio
  (`references/pooling.md`).
- O tenant vem do **token autenticado** no servidor, nunca de header/parâmetro do cliente.
- `WITH CHECK` impede inserir/atualizar linha de **outro** tenant; sem ele, só a leitura é isolada.
- **Views:** use `security_invoker = true` (PG 15+) para a view respeitar a RLS de quem consulta; sem
  isso, a view roda com os direitos do dono e pode vazar.
- **Desempenho:** a policy vira filtro em toda query; `tenant_id` é a primeira coluna dos índices
  quentes. Funções chamadas na policy devem ser `STABLE`/`IMMUTABLE`. Verifique com `EXPLAIN`.
- **Admin e jobs entre tenants:** role separada com `BYPASSRLS` usada só por processo auditado,
  nunca pela API de usuário.
- **Prove com teste:** dois tenants, mesma tabela; consulta com o contexto do tenant A nunca devolve
  linha de B, e sem contexto devolve zero. É teste de integração obrigatório; o ofensivo está em
  `schematize-pentest`.

## 4. Auditoria e extensões

`pgaudit` (quando norma exige trilha de DDL/leitura de dado sensível); `log_connections`/
`log_disconnections` ligados; acesso humano com prazo e registro.
