---
description: schematize-postgres — audita backup/PITR do PostgreSQL e monta o ensaio de restore com RPO/RTO medidos
argument-hint: "[diretório com a config do backup, opcional]"
---

# /pg-backup — backup só vale com restore testado

1. **Inventário** (de arquivos e config, sem tocar o banco de produção): ferramenta (pgBackRest,
   WAL-G, snapshot, `pg_dump`), `archive_mode`/`archive_command`, repositório (onde, quem apaga,
   object lock, cifra e onde mora a chave), retenção, agenda, monitor de `pg_stat_archiver`.
2. **Compare com o piso** de `references/backup-e-pitr.md`: base + WAL contínuo (PITR); repositório
   em outra conta; `pg_dump` não é o backup de record; cifrado; retenção alinhada à LGPD.
3. **RPO e RTO:** os declarados em ADR/runbook existem? Quando foi o **último restore medido**? Se
   não há, esse é o achado principal.
4. **Monte o ensaio** (`references/backup-e-pitr.md` §4) como script ou job agendado: ambiente
   descartável sem efeito externo, `restore --type=time`, `pg_amcheck`, consultas de sanidade, tempo
   total registrado. Entregue o runbook no formato de `schematize-docs`.
5. **Saída:** lista de achados com dono e prazo (`- [ ]` máquina, `- [H ]` humano). Nunca rode
   restore sobre o banco de produção.
