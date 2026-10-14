# Upgrade: minor e major

## 1. Minor

Troca de binário + restart; sem `pg_upgrade`. Leia as notas do release (às vezes pede reindex
ou ação pós-update), aplique primeiro nas réplicas, depois promova/troque e atualize o primário.
Em hml antes de prd. Mensal ou a cada release de segurança.

## 2. Major: o plano

Major troca o formato do catálogo; precisa de `pg_upgrade` (in-place) ou de replicação lógica
(troca com downtime mínimo). O EOL entra no calendário com **6+ meses** de folga.

1. **Ensaiar em cópia de prd** restaurada do backup (`references/backup-e-pitr.md` §4), com o
   volume real: mede-se o tempo de downtime, a diferença de plano e os erros.
2. **Ler as notas de incompatibilidade** do major de destino (parâmetros removidos, mudança de
   default, extensões, tipos).
3. **Extensões:** a versão do pacote instalada no destino para cada uma; `ALTER EXTENSION ... UPDATE`
   depois.
4. **Collation (glibc):** se o SO do destino traz outra glibc, a ordenação de texto pode mudar e
   **corromper índices** de `text` (unicidade que passa a admitir duplicata). Verifique com
   `pg_amcheck`/`amcheck` e, se mudou, `REINDEX` dos índices dependentes de collation. Prefira
   provedor de collation versionado (ICU, ou o `builtin`/`C.UTF-8` do PG 17+) para bancos novos.
5. **Checksums:** `pg_upgrade` exige a mesma configuração nos dois clusters. A partir do PG 18 o
   `initdb` liga checksums por default; se o cluster antigo **não** tem, crie o novo com
   `initdb --no-data-checksums` (e habilite depois, com `pg_checksums`, em janela) ou habilite no
   antigo antes. Detalhe verificado nas notas do PG 18.
6. **Rodar:** `pg_upgrade --check` (sem alterar nada) primeiro; depois `--link` (hard links, rápido,
   downtime de minutos mesmo em TB) **ou** cópia (mais lenta, mantém o cluster antigo intacto).
   `--jobs` paraleliza. Com `--link`, depois de subir o cluster novo **não há volta** para o antigo:
   o plano de rollback é o backup/snapshot **tirado imediatamente antes** (ou uma réplica mantida
   no major antigo).
7. **Estatísticas:** até o PG 17, o upgrade **não** preserva estatísticas do planner: rode
   `vacuumdb --all --analyze-in-stages` antes de liberar tráfego, senão os primeiros minutos têm
   planos ruins. A partir do PG 18, `pg_upgrade` retém as estatísticas do otimizador (fonte nas notas do PG 18).
8. **Pós:** `ANALYZE`, reindex se preciso, reativar autovacuum/jobs, conferir `pg_stat_statements`
   (planos regrediram?), reconstruir réplicas físicas (precisam do novo major; `rsync` do
   `pg_upgrade` ou novo base backup), e **novo base backup** + WAL: o histórico de PITR do major
   antigo não restaura no novo.
9. **Critério de rollback escrito antes** (quais métricas, por quanto tempo, quem decide).

## 3. Major por replicação lógica (downtime mínimo)

Sobe o cluster no major novo, replica as tabelas por publicação/assinatura (`references/replicacao-e-failover.md`),
sincroniza sequences e DDL manualmente, valida, e faz o corte (parar escrita, esperar lag zero,
mover a aplicação). Exige `PRIMARY KEY` em toda tabela, cuida de sequences/large objects, e é
mais trabalho que `pg_upgrade --link`: use quando o downtime de minutos é inaceitável. Desde o PG 17,
`pg_upgrade` migra slots e assinaturas lógicas, e `pg_createsubscriber` cria réplica lógica a
partir de uma física.

## 4. Gerenciado

Em RDS/Cloud SQL e afins: o provedor faz o `pg_upgrade`, mas o ensaio em cópia, o plano de
rollback (snapshot antes), a revisão de extensões e o `ANALYZE` pós continuam seus.
