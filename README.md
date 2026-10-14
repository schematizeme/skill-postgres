# schematize-postgres — operação do PostgreSQL

> **O Postgres perdoa SQL errado e castiga SQL correto no momento errado.** Versão suportada,
> configuração, `EXPLAIN` e índice na prática, vacuum, locks e migrations seguras em tabela viva,
> PgBouncer, replicação e failover, backup/PITR com restore testado, `pg_upgrade`, roles de menor
> privilégio e RLS multi-tenant.

Pacote de **skill normativa para [Claude Code](https://claude.com/claude-code)**.
Parte do catálogo **schematize skills**.

## Por que ela existe

A `schematize-database` desenha o schema. Faltava a especialista no **motor**: o `CREATE INDEX` que
bloqueia escrita, o `ADD COLUMN` com default volátil que reescreve a tabela, a migration que fica na
fila de lock e derruba a aplicação, o backup que nunca foi restaurado, o slot de replicação que
enche o disco. Tudo isso já foi incidente em algum lugar.

## Instalar

### Pelo app schematize (recomendado)

```bash
schematize install postgres    # requer o CLI schematize instalado
```

### Manual

```bash
git clone https://github.com/schematizeme/skill-postgres.git /tmp/skill-postgres
bash /tmp/skill-postgres/install.sh .        # instala em .claude/ do projeto atual
```

## O que tem dentro

- **SKILL.md** — o contrato: 15 pisos inegociáveis, a fronteira com `schematize-database` e o mapa de references.
- **references/** — `versao-e-config`, `explain-e-indices`, `vacuum-e-bloat`, `locks-e-migrations`,
  `pooling`, `replicacao-e-failover`, `backup-e-pitr`, `upgrade`, `roles-e-rls` e `stack-versoes`
  (anexo volátil com data, fonte e o que foi executado em PostgreSQL 18.6).
- **scripts/** — `check-pg-migration.sh`, o gate estático de migrations `.sql` (não precisa de
  Postgres; waiver rastreável `-- pg-ok:`), e `check-pg-migration.test.sh` (vermelhos plantados).
- **assets/** — `commands/` e `CLAUDE.md` sempre-on.

## Comandos

| Comando | O que faz |
|---|---|
| `/pg-help` | lista os comandos |
| `/pg-load` | carrega à força o corpo normativo |
| `/pg-review` | revisa migrations e config: gate + leitura humana |
| `/pg-migrate` | mudança de schema em passos seguros para tabela viva |
| `/pg-explain` | lê um plano e propõe índice ou reescrita sem lock |
| `/pg-backup` | audita backup/PITR e monta o ensaio de restore |
| `/pg-upgrade` | planeja o upgrade de major com ensaio e rollback |
| `/pg-claude` | `CLAUDE.md` sempre-on de operação Postgres |
| `/pg-cc` · `/pg-handoff` | context compact / handoff |

## Verificação

```bash
bash scripts/check-pg-migration.test.sh        # vermelho primeiro do gate
bash scripts/check-pg-migration.sh db/migrations
```

## Licença

MIT. Ver `LICENSE`. PostgreSQL é marca de seus respectivos titulares; este pacote não é afiliado
nem endossado pelo PostgreSQL Global Development Group.
