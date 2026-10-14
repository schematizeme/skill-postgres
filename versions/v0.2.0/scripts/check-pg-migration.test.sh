#!/usr/bin/env bash
# Vermelho primeiro do gate check-pg-migration.sh. Cada caso é um .sql com UM defeito (ou um
# padrão seguro, que tem de passar).
#
# EXCEÇÃO DECLARADA (piso da schematize-shell, strict mode): harness de teste roda `set -u` sem `-e`
# — precisa continuar depois de um caso vermelho para reportar todos, em vez de parar no primeiro.
set -u
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="$AQUI/check-pg-migration.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT INT TERM
ok=0; fail=0
D=""; NOME=""

# novo <nome> [arquivo]: cria o caso; grava stdin em $TMP/<nome>/<arquivo> (default m.sql).
novo() { NOME="$1"; D="$TMP/$1"; mkdir -p "$D"; ARQ="${2:-m.sql}"; mkdir -p "$(dirname "$D/$ARQ")"; cat >"$D/$ARQ"; }
# esperar <exit> <agulha>: roda o gate no caso e confere exit e trecho da saída.
esperar() {
  local esp="$1" agulha="$2" saida rc
  saida="$(bash "$G" "$D" 2>&1)"; rc=$?
  if [ "$rc" != "$esp" ]; then echo "  FALHOU $NOME: exit $rc, esperado $esp"; printf '      %s\n' "${saida//$'\n'/$'\n'      }"; fail=$((fail+1)); return; fi
  if [ -n "$agulha" ] && ! grep -qF -- "$agulha" <<<"$saida"; then echo "  FALHOU $NOME: exit certo, saída sem \"$agulha\""; printf '      %s\n' "${saida//$'\n'/$'\n'      }"; fail=$((fail+1)); return; fi
  if [ -z "$agulha" ] && [ "$esp" = 0 ] && grep -q '\[' <<<"$saida"; then echo "  FALHOU $NOME: passou mas acusou algo"; printf '      %s\n' "${saida//$'\n'/$'\n'      }"; fail=$((fail+1)); return; fi
  echo "  ok $NOME"; ok=$((ok+1))
}
LT="SET lock_timeout = '3s';"

echo "== vermelhos =="
novo idx-sem-conc <<FIX
$LT
CREATE INDEX idx_users_email ON users (email);
FIX
esperar 1 "[index-sem-concurrently]"

novo idx-unique-sem-conc <<FIX
$LT
CREATE UNIQUE INDEX ux ON public.orders (ref);
FIX
esperar 1 "[index-sem-concurrently]"

novo conc-em-tx <<FIX
BEGIN;
$LT
CREATE INDEX CONCURRENTLY idx ON users (email);
COMMIT;
FIX
esperar 1 "[concurrently-em-transacao]"

novo sem-lock-timeout <<'FIX'
CREATE INDEX CONCURRENTLY idx ON users (email);
FIX
esperar 1 "[lock-timeout-ausente]"

novo lock-timeout-depois <<'FIX'
ALTER TABLE users ADD COLUMN apelido text;
SET lock_timeout = '3s';
FIX
esperar 1 "[lock-timeout-ausente]"

novo default-volatil <<FIX
$LT
ALTER TABLE events ADD COLUMN id2 uuid DEFAULT gen_random_uuid();
FIX
esperar 1 "[add-column-default-volatil]"

novo default-random-bigint <<FIX
$LT
ALTER TABLE events ADD COLUMN r double precision NOT NULL DEFAULT random();
FIX
esperar 1 "[add-column-default-volatil]"

novo add-serial <<FIX
$LT
ALTER TABLE events ADD COLUMN seq bigserial;
FIX
esperar 1 "[add-column-default-volatil]"

novo generated-stored <<FIX
$LT
ALTER TABLE items ADD COLUMN total numeric GENERATED ALWAYS AS (price * qty) STORED;
FIX
esperar 1 "[add-column-generated-stored]"

novo not-null-sem-default <<FIX
$LT
ALTER TABLE users ADD COLUMN plano text NOT NULL;
FIX
esperar 1 "[add-column-not-null-sem-default]"

novo set-not-null <<FIX
$LT
ALTER TABLE users ALTER COLUMN plano SET NOT NULL;
FIX
esperar 1 "[set-not-null-direto]"

novo alter-type <<FIX
$LT
ALTER TABLE orders ALTER COLUMN total TYPE bigint;
FIX
esperar 1 "[alter-type-reescrita]"

novo fk-sem-not-valid <<FIX
$LT
ALTER TABLE orders ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users (id);
FIX
esperar 1 "[fk-sem-not-valid]"

novo fk-inline <<FIX
$LT
ALTER TABLE orders ADD COLUMN user_id bigint REFERENCES users (id);
FIX
esperar 1 "[fk-sem-not-valid]"

novo check-sem-not-valid <<FIX
$LT
ALTER TABLE orders ADD CONSTRAINT ck CHECK (total >= 0);
FIX
esperar 1 "[check-sem-not-valid]"

novo unique-sem-using <<FIX
$LT
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email);
FIX
esperar 1 "[add-unique-sem-using-index]"

novo drop-column <<FIX
$LT
ALTER TABLE users DROP COLUMN legado;
FIX
esperar 1 "[drop-sem-expand-contract]"

novo drop-table <<FIX
$LT
DROP TABLE velha;
FIX
esperar 1 "[drop-sem-expand-contract]"

novo rename-column <<FIX
$LT
ALTER TABLE users RENAME COLUMN nome TO nome_completo;
FIX
esperar 1 "[rename-sem-expand-contract]"

novo drop-index-sem-conc <<FIX
$LT
DROP INDEX idx_velho;
FIX
esperar 1 "[drop-index-sem-concurrently]"

novo reindex <<FIX
$LT
REINDEX INDEX idx_a;
FIX
esperar 1 "[reindex-bloqueante]"

novo vacuum-full <<FIX
$LT
VACUUM FULL users;
FIX
esperar 1 "[reescrita-bloqueante]"

novo update-sem-where <<'FIX'
UPDATE users SET ativo = true;
FIX
esperar 1 "[update-sem-where]"

novo delete-sem-where <<'FIX'
DELETE FROM sessoes;
FIX
esperar 1 "[delete-sem-where]"

novo role-super <<'FIX'
CREATE ROLE app LOGIN SUPERUSER;
FIX
esperar 1 "[role-privilegiada]"

novo senha-literal <<'FIX'
CREATE ROLE app LOGIN PASSWORD 'hunter2';
FIX
esperar 1 "[senha-literal]"

novo grant-all <<'FIX'
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app;
FIX
esperar 1 "[grant-amplo]"

novo grant-public <<'FIX'
GRANT SELECT ON users TO PUBLIC;
FIX
esperar 1 "[grant-publico]"

novo rls-off <<FIX
$LT
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
FIX
esperar 1 "[rls-desligada]"

novo policy-true <<'FIX'
CREATE POLICY p ON docs USING (true);
FIX
esperar 1 "[policy-permissiva]"

novo waiver-sem-motivo <<FIX
$LT
-- pg-ok: set-not-null-direto
ALTER TABLE users ALTER COLUMN plano SET NOT NULL;
FIX
esperar 1 "[waiver-sem-motivo]"

novo na-dollar-quote <<'FIX'
DO $$
BEGIN
  CREATE INDEX idx_x ON users (email);
END
$$;
FIX
esperar 1 "[index-sem-concurrently]"

echo "== verdes =="
novo ok-index-conc <<FIX
$LT
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email ON users (email);
FIX
esperar 0 ""

novo ok-tabela-nova <<'FIX'
CREATE TABLE pedidos (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users (id),
  total bigint NOT NULL CHECK (total >= 0)
);
CREATE INDEX idx_pedidos_user ON pedidos (user_id);
FIX
esperar 0 ""

novo ok-default-estavel <<FIX
$LT
ALTER TABLE users ADD COLUMN criado_em timestamptz DEFAULT now();
ALTER TABLE users ADD COLUMN plano text NOT NULL DEFAULT 'free';
ALTER TABLE users ADD COLUMN apelido text;
FIX
esperar 0 ""

novo ok-fk-notvalid <<FIX
$LT
ALTER TABLE orders ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users (id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_user;
FIX
esperar 0 ""

novo ok-set-not-null-via-check <<FIX
$LT
ALTER TABLE users ADD CONSTRAINT users_plano_nn CHECK (plano IS NOT NULL) NOT VALID;
ALTER TABLE users VALIDATE CONSTRAINT users_plano_nn;
ALTER TABLE users ALTER COLUMN plano SET NOT NULL;
ALTER TABLE users DROP CONSTRAINT users_plano_nn;
FIX
esperar 0 ""

novo ok-pg18-not-null-not-valid <<FIX
$LT
ALTER TABLE users ADD CONSTRAINT users_plano_nn NOT NULL plano NOT VALID;
ALTER TABLE users VALIDATE CONSTRAINT users_plano_nn;
ALTER TABLE users ALTER COLUMN plano SET NOT NULL;
FIX
esperar 0 ""

novo ok-unique-using-index <<FIX
$LT
CREATE UNIQUE INDEX CONCURRENTLY ux_users_email ON users (email);
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE USING INDEX ux_users_email;
FIX
esperar 0 ""

novo ok-contract-com-marcador <<FIX
$LT
-- pg-contract: v42 parou de ler users.legado (release 2026-10-01)
ALTER TABLE users DROP COLUMN legado;
FIX
esperar 0 ""

novo ok-waiver-com-motivo <<FIX
$LT
-- pg-ok: alter-type-reescrita varchar(50)->varchar(100) é binário-compatível, sem reescrita
ALTER TABLE users ALTER COLUMN nome TYPE varchar(100);
FIX
esperar 0 ""

novo ok-waiver-mesma-linha <<FIX
$LT
ALTER TABLE users ALTER COLUMN nome TYPE varchar(100); -- pg-ok: alter-type-reescrita alarga varchar, sem reescrita
FIX
esperar 0 ""

novo ok-down-pode-dropar users.down.sql <<FIX
$LT
ALTER TABLE users DROP COLUMN apelido;
FIX
esperar 0 ""

novo ok-comentario-e-string <<FIX
$LT
-- CREATE INDEX idx ON users (email);  (comentário, não vale)
/* DROP TABLE users; */
INSERT INTO log (msg) VALUES ('DROP TABLE x; CREATE INDEX y ON z (a);');
CREATE INDEX CONCURRENTLY idx_a ON users (a);
FIX
esperar 0 ""

novo ok-update-com-where <<'FIX'
UPDATE users SET plano = 'free' WHERE plano IS NULL AND id BETWEEN 1 AND 10000;
FIX
esperar 0 ""

novo ok-role-minima <<'FIX'
CREATE ROLE app_ro NOLOGIN;
GRANT SELECT ON users TO app_ro;
FIX
esperar 0 ""

novo ok-drop-constraint <<FIX
$LT
ALTER TABLE users DROP CONSTRAINT users_plano_nn;
FIX
esperar 0 ""

echo "== entradas especiais =="
D="$TMP/vazio"; NOME="dir-sem-sql"; mkdir -p "$D"; esperar 2 "nenhum .sql"
D="$TMP/naoexiste"; NOME="alvo-inexistente"; esperar 2 ""
novo dump-ignorado dump.sql <<'FIX'
-- PostgreSQL database dump
CREATE INDEX x ON y (z);
FIX
esperar 2 ""

echo
echo "check-pg-migration.test.sh: $ok ok, $fail falha(s)"
[ "$fail" -eq 0 ]
