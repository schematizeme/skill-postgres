# Backup, PITR e restore testado

**Backup que nunca foi restaurado é esperança.** O critério de pronto não é "o job de backup
passou", é "o restore passou, e levou tanto tempo".

## 1. O que é o backup de record

- **Base backup físico + arquivamento contínuo de WAL** = permite restaurar para **qualquer
  instante** (PITR, `recovery_target_time`/`recovery_target_lsn`/ponto nomeado). Ferramenta:
  **pgBackRest** (full/diferencial/incremental, paralelismo, compressão, cifra, verificação,
  S3-compatível/GCS/Azure/SFTP) ou **WAL-G** (S3/GCS/Azure, delta). Ambas ativas em 2026-10
  (`stack-versoes.md`). Escolha uma por cluster, registre em ADR.
- `pg_dump`/`pg_dumpall` é **complemento** (migração, extração de um banco/tabela, versionar
  schema), **não** o backup de record: sem PITR, lento para restaurar em volume grande e
  inconsistente entre bancos distintos.
- Snapshot de volume/disco só vale se for **crash-consistente** de dados e WAL juntos (mesmo
  volume atômico) e ainda assim sem PITR sem o WAL arquivado.
- PG 17+ tem backup incremental nativo (`pg_basebackup --incremental`, `pg_combinebackup`); a
  ferramenta externa continua sendo a base operacional por gerenciar retenção e verificação.

## 2. Configuração mínima (pgBackRest)

```
# postgresql.conf
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
# pgbackrest.conf (repositório cifrado e fora do host do banco)
[global]
repo1-type=s3
repo1-cipher-type=aes-256-cbc
repo1-retention-full=4
repo1-retention-diff=14
process-max=4
start-fast=y
[main]
pg1-path=/var/lib/postgresql/data
```

- `pgbackrest check` valida a cadeia de arquivamento; rode no setup e na CI do runbook.
- **Alerta em falha de `archive_command`:** `pg_stat_archiver` (`failed_count` subindo,
  `last_failed_time` recente). WAL que não sobe = PITR quebrado **e** disco enchendo.
- **Repositório em outra conta/projeto/bucket**, com credencial de escrita sem permissão de apagar
  e **object lock/versionamento** (ransomware e erro humano não apagam o histórico). Cifrado, com a
  chave de cifra guardada **fora** do repositório e do host do banco.

## 3. RPO e RTO declarados e medidos

- **RPO** (quanto dado posso perder): com WAL contínuo, é o intervalo do `archive_timeout`/lag do
  arquivamento (segundos a minutos); com réplica síncrona, ~0. **RTO** (quanto tempo fora): é o tempo
  de restore + replay de WAL, e **cresce com o volume**.
- Os números vão no ADR/runbook **e são medidos no ensaio**, não estimados.

## 4. O ensaio de restore (automatizado, no mínimo mensal)

1. Ambiente descartável (container/VM efêmero), **sem** rota para produção e sem efeito externo
   (job, webhook e e-mail do banco restaurado desligados).
2. `pgbackrest restore --stanza=main --type=time "--target=<instante>"` (PITR para um instante
   conhecido, de preferência logo antes de um marcador que o ensaio gravou).
3. Subir, esperar o fim do recovery, `pg_amcheck` (verifica heap e índices) e consultas de sanidade
   (contagens, o marcador, a linha mais recente esperada).
4. **Registrar o tempo total** (RTO real) e o ponto recuperado (RPO real); falha ou estouro do
   RTO vira incidente com dono.
5. Reaproveite a cópia restaurada para ensaiar migration, `EXPLAIN` em volume real e upgrade
   (`references/upgrade.md`): um restore, três usos.

## 5. LGPD e retenção

Dado pessoal apagado a pedido **continua** nos backups até a retenção vencer. A retenção do backup
é decisão registrada (alinhada à política de `schematize-data → references/governanca.md`): não
retenha além do necessário; se houver pedido de eliminação, a restauração deve **reaplicar** a
lista de eliminações antes de reabrir o banco ao tráfego.

## 6. Do lado do cliente

Salvar `postgresql.conf`, `pg_hba.conf` e os scripts de provisionamento no repo de infra (IaC), não
só no backup. Restaurar sem a configuração é refazer à mão sob pressão.
