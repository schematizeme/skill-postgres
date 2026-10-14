---
description: schematize-postgres — context compact: grava o handoff no archive e roda /compact.
---
Antes de compactar, **grave o handoff** em `<projeto>/<projeto>_archive/context/` no par
**context + checklist** do padrão da `schematize-archive` (prefixo `AAAA-MM-DD-<slug>-`), FEITO vs
ABERTO. Inclua: as migrations revisadas ou escritas, os achados do `scripts/check-pg-migration.sh`
que ficaram abertos, as exceções (`-- pg-ok:` / `-- pg-contract:`) com o motivo, e o RPO/RTO do
último ensaio de restore. Nunca inclua senha, DSN ou dado de cliente. Só então rode `/compact`.
