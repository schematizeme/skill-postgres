# Replicação e failover

## 1. Os dois tipos

| | Física (streaming) | Lógica |
|---|---|---|
| O que copia | o cluster inteiro, byte a byte (WAL) | tabelas escolhidas (publicação -> assinatura) |
| Réplica | idêntica, somente leitura (`hot_standby`) | banco independente, gravável |
| Versões | mesma major | pode ser major diferente (base do upgrade de baixo downtime) |
| Não replica | nada (inclui DDL) | **DDL**, e (em geral) sequences e large objects |
| Uso | HA, failover, leitura | CDC, migração, upgrade, integração |

Lógica: `wal_level = logical`; toda tabela publicada precisa de `PRIMARY KEY` ou `REPLICA IDENTITY`
para propagar `UPDATE`/`DELETE`; o **DDL tem de ser aplicado nos dois lados** (ordem importa:
coluna nova no assinante antes do publicador). O contrato do dado propagado (CDC, outbox) é da
`schematize-data`.

## 2. Síncrona ou assíncrona

- **Assíncrona** (default): menor latência, mas o failover pode **perder** transações confirmadas
  (RPO > 0 igual ao lag).
- **Síncrona** (`synchronous_standby_names = 'ANY 1 (r1, r2)'`, `synchronous_commit = on`/`remote_apply`):
  RPO ~0 ao custo de latência, e a escrita para se não houver réplica síncrona disponível. Use
  `ANY`/`FIRST` com pelo menos duas candidatas. Decisão de negócio: registre o RPO em ADR.
- `synchronous_commit` pode ser relaxado **por transação** para dado descartável.

## 3. Slots: úteis e perigosos

Slot garante que o WAL não seja removido antes de a réplica consumir. Slot **parado** acumula WAL
até **encher o disco** do primário. Piso: `max_slot_wal_keep_size` definido (a réplica que
estourar o teto é invalidada em vez de derrubar o primário), alerta em
`pg_replication_slots` com `active = false`, e no PG 18 `idle_replication_slot_timeout` para
invalidar slot inativo. Slot lógico segura também o `catalog_xmin` (inchaço de catálogo).

## 4. Failover

- **Orquestrador, não script à mão:** Patroni (com etcd/Consul/ZooKeeper como DCS, 3 ou 5 nós)
  ou o failover do serviço gerenciado. Ele elege, promove, reconfigura as outras réplicas e
  **faz fencing** do primário antigo.
- **Split-brain** (dois primários) é o pior caso: exige quórum no DCS, fencing (o antigo primário
  não aceita escrita nem por engano) e o cliente conectando via endpoint que segue o líder
  (VIP/DNS/pooler consciente do líder).
- Primário antigo que volta: `pg_rewind` (exige `wal_log_hints = on` ou checksums) para ressincronizar
  como réplica; senão, rebuild do base backup.
- PG 17+ tem **slots lógicos com failover** (`failover = true` no slot e `sync_replication_slots`
  na réplica), então assinantes lógicos sobrevivem à troca de primário.
- **Ensaio:** a promoção é testada em hml com carga, periodicamente (no mínimo trimestral) e a cada
  mudança de topologia: mede-se tempo de detecção, de promoção, de reconexão da aplicação e a
  perda de dados. Sem esse número, o RTO/RPO declarado é ficção. Runbook em `schematize-docs`.

## 5. Réplica de leitura: o que a aplicação precisa saber

Réplica atrasa (**lag**): leitura logo após escrita pode não ver a escrita (read-your-writes).
Roteie por intenção (relatório e busca na réplica; fluxo "escrevi e li" no primário, ou compare o LSN
de commit com `pg_last_wal_replay_lsn()` da réplica antes de ler). Consulta longa na réplica conflita
com o replay (`max_standby_streaming_delay`) ou, com `hot_standby_feedback = on`, segura o vacuum
do primário (`references/vacuum-e-bloat.md`): escolha conscientemente.

Monitore: `pg_stat_replication` (`write_lag`, `flush_lag`, `replay_lag`), `pg_stat_wal_receiver`,
`pg_replication_slots`, e alerte em lag acima do RPO acordado.
