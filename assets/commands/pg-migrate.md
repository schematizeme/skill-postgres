---
description: schematize-postgres — transforma uma mudança de schema em passos seguros para tabela viva e roda o gate
argument-hint: "<mudança desejada, ex.: tornar users.plano NOT NULL com default 'free'>"
---

# /pg-migrate — a mesma mudança, sem tomar lock que derruba a aplicação

Entrada: a mudança em linguagem natural (ou o `.sql` ingênuo). Saída: a sequência de migrations
seguras, cada uma passando no gate.

1. **Pergunte o que falta** (uma rodada, só o que muda a receita): tamanho aproximado da tabela,
   se há réplica lógica/CDC lendo, qual runner de migration, se o código atual lê a coluna.
2. **Classifique** cada operação na tabela de `references/locks-e-migrations.md` §2 (seguro,
   reescreve, varre sob lock, destrutivo).
3. **Monte os passos**, com a receita do §3: expand (aditivo) -> backfill em lotes (job, não
   migration) -> constraint `NOT VALID` + `VALIDATE` -> contract (com `-- pg-contract: <motivo>`
   só quando ninguém mais lê). Cada migration começa com `SET lock_timeout = '3s';` e traz o
   `down` quando o passo é reversível.
4. **Escreva os `.sql`** (um arquivo por passo arriscado; `CREATE INDEX CONCURRENTLY` sozinho, sem
   `BEGIN`) e **rode o gate**: `bash .claude/skills/schematize-postgres/scripts/check-pg-migration.sh <dir>` até verde. Não
   use waiver para fazer o gate passar; waiver é exceção com motivo real.
5. **Entregue** os passos em ordem, o que muda na aplicação entre eles (dual-write, flag), o plano
   de ensaio em cópia de prd e o critério para o contract. O desenho da coluna/constraint em si é
   da `schematize-database`. **Nunca aplique** em produção.
