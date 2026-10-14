#!/usr/bin/env bash
# check-pg-migration.sh — gate estático de migrations PostgreSQL (*.sql).
#
# Motivo: a maioria dos incidentes de migration em Postgres não é SQL errado, é SQL correto que
# toma um lock pesado (ACCESS EXCLUSIVE) ou reescreve a tabela inteira com o sistema no ar. O
# gate lê o arquivo e reprova o padrão perigoso ANTES de ele rodar em dado vivo.
# Como funciona: um tokenizador em awk separa os comandos (respeitando comentário, string e
# dollar-quote), normaliza cada um e aplica as regras abaixo. Não precisa de Postgres instalado.
# Entrada: $1.. = arquivos .sql e/ou diretórios (varre *.sql recursivamente). Default: ".".
# Saída: linhas "arquivo:linha: [regra] mensagem". Exit 0 passa · 1 reprova · 2 nada para verificar
# (que NÃO é aprovação).
#
# Waiver rastreável (motivo obrigatório):
#   -- pg-ok: <regra> <motivo>        no comando (comentário antes dele ou na mesma linha)
#   -- pg-ok-file: <regra> <motivo>   no arquivo inteiro
#   -- pg-contract: <motivo>          fase contract do expand-contract (vale p/ DROP/RENAME)
# Regras: lock-timeout-ausente, index-sem-concurrently, concurrently-em-transacao,
#   drop-index-sem-concurrently, reindex-bloqueante, reescrita-bloqueante,
#   add-column-default-volatil, add-column-generated-stored, add-column-not-null-sem-default,
#   set-not-null-direto, alter-type-reescrita, fk-sem-not-valid, check-sem-not-valid,
#   add-unique-sem-using-index, drop-sem-expand-contract, rename-sem-expand-contract,
#   update-sem-where, delete-sem-where, role-privilegiada, senha-literal, grant-amplo,
#   grant-publico, rls-desligada, policy-permissiva, waiver-sem-motivo.
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit 0
fi

[ "$#" -gt 0 ] || set -- .

arquivos=()
for alvo in "$@"; do
  if [ -d "$alvo" ]; then
    while IFS= read -r -d '' f; do arquivos+=("$f"); done < <(
      find "$alvo" \( -name .git -o -name node_modules -o -name versions -o -name .terraform \) -prune -o \
        -type f -name '*.sql' -print0 | sort -z)
  elif [ -f "$alvo" ]; then
    arquivos+=("$alvo")
  else
    echo "check-pg-migration: não existe: $alvo" >&2
  fi
done

if [ "${#arquivos[@]}" -eq 0 ]; then
  echo "check-pg-migration: nenhum .sql para verificar (isto NÃO é aprovação)." >&2
  exit 2
fi

AWK_PROG="$(cat <<'AWK'
function viol(i, regra, msg,    k) {
  if (wf[regra] != "" ) return
  if (wv[i, regra] != "") return
  if ((regra == "drop-sem-expand-contract" || regra == "rename-sem-expand-contract") && wv[i, "contract"] != "") return
  if ((regra == "drop-sem-expand-contract" || regra == "rename-sem-expand-contract") && wf["contract"] != "") return
  printf "%s:%d: [%s] %s\n", FILENAME, sl[i], regra, msg
  achados++
}
function addw(i, texto,    r, m, t) {
  # texto = comentário sem o "--"
  if (match(texto, "pg-ok-file:[ \t]*[a-z0-9-]+")) {
    t = substr(texto, RSTART + 11); sub(/^[ \t]*/, "", t)
    r = t; sub(/[ \t].*$/, "", r)
    m = t; sub(/^[a-z0-9-]+[ \t]*/, "", m)
    if (m == "") { printf "%s:%d: [waiver-sem-motivo] pg-ok-file: %s exige motivo\n", FILENAME, NR, r; achados++ }
    else wf[r] = m
  } else if (match(texto, "pg-ok:[ \t]*[a-z0-9-]+")) {
    t = substr(texto, RSTART + 6); sub(/^[ \t]*/, "", t)
    r = t; sub(/[ \t].*$/, "", r)
    m = t; sub(/^[a-z0-9-]+[ \t]*/, "", m)
    if (m == "") { printf "%s:%d: [waiver-sem-motivo] pg-ok: %s exige motivo\n", FILENAME, NR, r; achados++ }
    else if (i == 0) pendw[r] = m
    else wv[i, r] = m
  } else if (match(texto, "pg-contract:")) {
    m = substr(texto, RSTART + 12); gsub(/^[ \t]+|[ \t]+$/, "", m)
    if (m == "") { printf "%s:%d: [waiver-sem-motivo] pg-contract exige motivo\n", FILENAME, NR; achados++ }
    else if (i == 0) pendw["contract"] = m
    else wv[i, "contract"] = m
  }
}
function fechar(   k) {
  s = tolower(buf)
  gsub(/[ \t\r\n]+/, " ", s)
  gsub(/ *\( */, " (", s); gsub(/ *\)/, ")", s)
  gsub(/^ +| +$/, "", s)
  if (s ~ /^do /) { # bloco anônimo: cada comando interno é verificado como se fosse do arquivo
    b = s
    sub(/^do (language [a-z_]+ )?\$[a-z_0-9]*\$ ?/, "", b); sub(/ ?\$[a-z_0-9]*\$( language [a-z_]+)?$/, "", b)
    sub(/^(declare .* )?begin /, "", b); sub(/ end( if)?$/, "", b); sub(/ end$/, "", b)
    nd = split(b, DS, ";")
    for (j = 1; j <= nd; j++) { x = DS[j]; gsub(/^ +| +$/, "", x); if (x != "") { n++; st[n] = x; sl[n] = stline; for (k in pendw) wv[n, k] = pendw[k] } }
    delete pendw; ultimo = n; ultimo_fim = NR
  } else if (s != "") {
    n++; st[n] = s; sl[n] = stline
    for (k in pendw) wv[n, k] = pendw[k]
    delete pendw
    ultimo = n; ultimo_fim = NR
  }
  buf = ""; stline = 0
}
function nome(s,    t) { # extrai o 1o identificador, sem aspas nem schema
  sub(/^ +/, "", s)
  t = s; sub(/[ (;].*$/, "", t)
  gsub(/"/, "", t)
  sub(/^.*\./, "", t)
  return t
}
function acoes(s, arr,    i, c, d, ini, k, n2) {
  d = 0; ini = 1; n2 = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(") d++
    else if (c == ")") d--
    else if (c == "," && d == 0) { n2++; arr[n2] = substr(s, ini, i - ini); ini = i + 1 }
  }
  n2++; arr[n2] = substr(s, ini)
  for (k = 1; k <= n2; k++) gsub(/^ +| +$/, "", arr[k])
  return n2
}
function cria_tabela(s,    t) {
  t = s
  if (t !~ /^create (unlogged |temp |temporary |global |local )*table /) return ""
  sub(/^create (unlogged |temp |temporary |global |local )*table (if not exists )?/, "", t)
  return nome(t)
}
function nova(tb, i,    k) { return (tb in novat) && novat[tb] < sl[i] }

{ linha = $0
  if (NR == 1 && linha ~ /PostgreSQL database dump/) dump = 1
  L = length(linha); p = 1
  if (emcom) { # dentro de /* */
    q = index(linha, "*/")
    if (q == 0) next
    p = q + 2; emcom = 0
  }
  if (emdq) { # dentro de $tag$ ... $tag$
    q = index(linha, emdq)
    if (q == 0) { buf = buf " " linha; next }
    buf = buf " " substr(linha, 1, q + length(emdq) - 1); p = q + length(emdq); emdq = ""
  }
  if (emstr) { # string multilinha
    while (p <= L) {
      c = substr(linha, p, 1)
      if (c == "'") { if (substr(linha, p + 1, 1) == "'") { p += 2; continue } emstr = 0; p++; break }
      p++
    }
    if (emstr) next
  }
  while (p <= L) {
    c = substr(linha, p, 1); c2 = substr(linha, p, 2)
    if (c2 == "--") {
      com = substr(linha, p + 2)
      if (buf ~ /^[ \t]*$/ && ultimo > 0 && ultimo_fim == NR) addw(ultimo, com); else addw(0, com)
      # comentário dentro de comando em andamento: vale para ele (pendw é aplicado no fechar)
      break
    }
    if (c2 == "/*") {
      q = index(substr(linha, p + 2), "*/")
      if (q == 0) { emcom = 1; break }
      p += q + 3; buf = buf " "; continue
    }
    if (c == "'") {
      if (stline == 0) stline = NR
      buf = buf "''"; p++
      while (p <= L) {
        c = substr(linha, p, 1)
        if (c == "'") { if (substr(linha, p + 1, 1) == "'") { p += 2; continue } p++; break }
        p++
      }
      if (p > L && substr(linha, L, 1) != "'") emstr = 1
      continue
    }
    if (c == "$" && match(substr(linha, p), /^\$([A-Za-z_][A-Za-z_0-9]*)?\$/)) {
      tag = substr(linha, p, RLENGTH)
      if (stline == 0) stline = NR
      rest = substr(linha, p + RLENGTH)
      q = index(rest, tag)
      if (q == 0) { buf = buf " " substr(linha, p); emdq = tag; p = L + 1; break }
      buf = buf " " substr(linha, p, RLENGTH + q + length(tag) - 1); p += RLENGTH + q + length(tag) - 1
      continue
    }
    if (c == ";") { fechar(); p++; continue }
    if (c !~ /[ \t\r]/ && stline == 0) stline = NR
    buf = buf c; p++
  }
  buf = buf " "
}

END {
  if (buf ~ /[^ \t\r\n]/) fechar()
  if (dump) { print FILENAME ": dump do pg_dump, ignorado (não é migration)" > "/dev/stderr"; exit 3 }
  # passe 1: tabelas criadas no próprio arquivo, lock_timeout, begin, check not valid
  for (i = 1; i <= n; i++) {
    s = st[i]
    t = cria_tabela(s); if (t != "" && !(t in novat)) novat[t] = sl[i]
    if (s ~ /^set (local |session )?lock_timeout( |=)/ || s ~ /set_config \(.lock_timeout/) { if (!lt || sl[i] < lt) lt = sl[i] }
    if (s ~ /^(begin|start transaction)( |$)/) tx = 1
    if (s ~ /^alter table .* add (constraint [^ ]+ )?check \(.*is not null\).* not valid/) chknn = 1
    if (s ~ /^alter table .* add (constraint [^ ]+ )?not null .* not valid/) chknn = 1
  }
  primeiro_risco = 0
  for (i = 1; i <= n; i++) {
    s = st[i]
    risco = 0
    # ---- CREATE INDEX
    if (s ~ /^create (unique )?index /) {
      conc = (s ~ /^create (unique )?index concurrently /)
      t = s; sub(/^.* on (only )?/, "", t); tb = nome(t)
      if (!conc) {
        if (!nova(tb, i)) { risco = 1; viol(i, "index-sem-concurrently", "CREATE INDEX sem CONCURRENTLY bloqueia escrita em " tb " durante a construção; use CREATE INDEX CONCURRENTLY (fora de transação)") }
      } else if (tx) viol(i, "concurrently-em-transacao", "CREATE INDEX CONCURRENTLY não roda dentro de transação (há BEGIN no arquivo); tire-o do bloco")
      else risco = 1
    }
    else if (s ~ /^drop index /) {
      risco = 1
      if (s !~ /^drop index concurrently /) viol(i, "drop-index-sem-concurrently", "DROP INDEX sem CONCURRENTLY toma ACCESS EXCLUSIVE na tabela; use DROP INDEX CONCURRENTLY")
    }
    else if (s ~ /^reindex /) {
      risco = 1
      if (s !~ /^reindex (\([^)]*\) )?(index|table|schema|database|system) concurrently /) viol(i, "reindex-bloqueante", "REINDEX sem CONCURRENTLY bloqueia a tabela; use REINDEX ... CONCURRENTLY")
    }
    else if (s ~ /^vacuum (\(.*full.*\)|full)/ || s ~ /^cluster( |$)/) {
      risco = 1; viol(i, "reescrita-bloqueante", "VACUUM FULL/CLUSTER reescreve a tabela sob ACCESS EXCLUSIVE; use pg_repack/pg_squeeze fora da migration")
    }
    else if (s ~ /^lock table /) { risco = 1 }
    # ---- ALTER TABLE
    else if (s ~ /^alter table /) {
      t = s; sub(/^alter table (if exists )?(only )?/, "", t); tb = nome(t)
      rest = t; sub(/^[^ ]+ /, "", rest); sub(/^\* /, "", rest)
      if (!nova(tb, i)) {
        risco = 1
        na = acoes(rest, A)
        for (k = 1; k <= na; k++) {
          a = A[k]
          if (a ~ /^add (column )?(if not exists )?("[^"]+"|[a-z_][a-z_0-9]*) / && a !~ /^add (constraint|primary|unique|check|foreign|exclude)( |$)/) {
            if (a ~ / default (random|gen_random_uuid|uuid_generate_v[0-9a-z]*|clock_timestamp|timeofday|nextval|uuidv[0-9]+|txid_current|pg_current_[a-z_]+|statement_timestamp|setseed|md5 \(random) ?\(/ || a ~ / (big|small)?serial( |$)/ || a ~ / generated (always|by default) as identity/)
              viol(i, "add-column-default-volatil", "ADD COLUMN com default volátil/serial/identity reescreve a tabela inteira sob ACCESS EXCLUSIVE; adicione sem default, preencha em lotes e só então fixe o default")
            if (a ~ / generated always as \(.*\) stored/)
              viol(i, "add-column-generated-stored", "coluna GENERATED ... STORED reescreve a tabela; calcule em lotes ou use coluna virtual (PG 18+)")
            if (a ~ / not null/ && a !~ / default / && a !~ / generated /)
              viol(i, "add-column-not-null-sem-default", "ADD COLUMN NOT NULL sem DEFAULT falha em tabela com linhas; adicione nullable, backfill em lotes, depois NOT NULL via CHECK NOT VALID")
            if (a ~ / references /)
              viol(i, "fk-sem-not-valid", "FK inline em ADD COLUMN valida na hora; adicione a coluna e depois ADD CONSTRAINT ... FOREIGN KEY ... NOT VALID + VALIDATE CONSTRAINT")
            if (a ~ / (unique|primary key)( |$)/)
              viol(i, "add-unique-sem-using-index", "UNIQUE/PRIMARY KEY inline constrói índice sob lock; crie CREATE UNIQUE INDEX CONCURRENTLY e ADD CONSTRAINT ... USING INDEX")
            if (a ~ / check \(/)
              viol(i, "check-sem-not-valid", "CHECK inline valida a tabela sob lock; adicione ADD CONSTRAINT ... CHECK (...) NOT VALID e depois VALIDATE CONSTRAINT")
          }
          else if (a ~ /^add (constraint [^ ]+ )?foreign key/ && a !~ / not valid$/ && a !~ / not valid /)
            viol(i, "fk-sem-not-valid", "ADD FOREIGN KEY sem NOT VALID varre a tabela travando escrita; use NOT VALID e depois VALIDATE CONSTRAINT")
          else if (a ~ /^add (constraint [^ ]+ )?check/ && a !~ / not valid$/ && a !~ / not valid /)
            viol(i, "check-sem-not-valid", "ADD CHECK sem NOT VALID varre a tabela sob lock; use NOT VALID e depois VALIDATE CONSTRAINT")
          else if (a ~ /^add (constraint [^ ]+ )?(unique|primary key)/ && a !~ / using index /)
            viol(i, "add-unique-sem-using-index", "ADD UNIQUE/PRIMARY KEY constrói índice sob lock; crie o índice CONCURRENTLY e use ADD CONSTRAINT ... USING INDEX")
          else if (a ~ /^alter (column )?[^ ]+ (set data )?type /)
            viol(i, "alter-type-reescrita", "ALTER COLUMN TYPE costuma reescrever a tabela sob ACCESS EXCLUSIVE; use coluna nova + backfill + troca (expand-contract). Se for binário-compatível, waiver com motivo")
          else if (a ~ /^alter (column )?[^ ]+ set not null/ && !chknn)
            viol(i, "set-not-null-direto", "SET NOT NULL varre a tabela sob ACCESS EXCLUSIVE; antes crie CHECK (col IS NOT NULL) NOT VALID + VALIDATE (PG 12+ pula a varredura)")
          else if (!DOWN && (a ~ /^drop column / || (a ~ /^drop / && a !~ /^drop (constraint|default|not null|identity|expression)/)))
            viol(i, "drop-sem-expand-contract", "DROP COLUMN destrói dado e quebra quem ainda lê; só na fase contract, com -- pg-contract: <migration que parou de ler>")
          else if (!DOWN && (a ~ /^rename (column |to )/ ))
            viol(i, "rename-sem-expand-contract", "RENAME quebra o código em voo; faça expand (coluna/tabela nova) e contract depois, ou -- pg-contract: <motivo>")
          else if (a ~ /^(disable|no force) row level security/)
            viol(i, "rls-desligada", "desligar RLS expõe linhas de todos os tenants; se for deliberado, waiver com motivo")
        }
      }
    }
    # ---- DROP / TRUNCATE
    else if (s ~ /^(drop (table|schema|database)|truncate)( |$)/) {
      risco = 1
      if (!DOWN) viol(i, "drop-sem-expand-contract", "DROP/TRUNCATE destrói dado e quebra quem ainda lê; só na fase contract, com -- pg-contract: <motivo>")
    }
    else if (s ~ /^alter (materialized view|view|sequence|index) .* rename /) { }
    # ---- DML descuidado
    else if (s ~ /^update / && s !~ / where /) viol(i, "update-sem-where", "UPDATE sem WHERE reescreve a tabela inteira numa transação só; faça backfill em lotes com WHERE e LIMIT")
    else if (s ~ /^delete from / && s !~ / where /) viol(i, "delete-sem-where", "DELETE sem WHERE apaga tudo numa transação só; delimite com WHERE e faça em lotes")
    # ---- roles, grants, políticas
    else if (s ~ /^(create|alter) (role|user) /) {
      if (s ~ / (superuser|createrole|createdb|bypassrls)( |$)/) viol(i, "role-privilegiada", "role com SUPERUSER/CREATEROLE/CREATEDB/BYPASSRLS fere o menor privilégio; conceda só o necessário")
      if (s ~ / password ''/) viol(i, "senha-literal", "senha literal em migration vai para git e para o log do servidor; provisione a credencial pelo cofre/secret, fora do SQL versionado")
    }
    if (s ~ /(^| )grant all( privileges)? /) viol(i, "grant-amplo", "GRANT ALL concede mais do que o papel precisa; liste os privilégios mínimos")
    if (s ~ /^grant .* to public( |$)/ || s ~ /^alter default privileges .* to public( |$)/) viol(i, "grant-publico", "GRANT a PUBLIC abre o objeto a qualquer role; conceda a roles nomeadas")
    if (s ~ /^create policy / && (s ~ / using \(true\)/ || s ~ / with check \(true\)/)) viol(i, "policy-permissiva", "policy com USING/WITH CHECK (true) libera todas as linhas; amarre ao tenant/dono (ex.: tenant_id = current_setting(...))")
    if (risco && !primeiro_risco) { primeiro_risco = i }
  }
  if (primeiro_risco && (!lt || lt > sl[primeiro_risco]))
    viol(primeiro_risco, "lock-timeout-ausente", "DDL sem SET lock_timeout antes dele: se a tabela estiver ocupada, a migration fica na fila de lock e trava todo mundo atrás; use SET lock_timeout = '3s' (e retry)")
  if (n == 0) exit 4
  exit (achados > 0 ? 1 : 0)
}
AWK
)"

falhou=0; verificados=0; ignorados=0
for f in "${arquivos[@]}"; do
  down=0
  case "$f" in *.down.sql|*_down.sql|*/down/*|*.rollback.sql|*_rollback.sql) down=1 ;; esac
  set +e
  awk -v DOWN="$down" "$AWK_PROG" "$f"
  rc=$?
  set -e
  case "$rc" in
    0) verificados=$((verificados+1)) ;;
    1) verificados=$((verificados+1)); falhou=1 ;;
    3|4) ignorados=$((ignorados+1)) ;;
    *) echo "check-pg-migration: erro interno ao ler $f (awk rc=$rc)" >&2; exit 2 ;;
  esac
done

if [ "$verificados" -eq 0 ]; then
  echo "check-pg-migration: nenhum comando SQL verificável (isto NÃO é aprovação)." >&2
  exit 2
fi
if [ "$falhou" -eq 1 ]; then
  echo "check-pg-migration: REPROVADO ($verificados arquivo(s) verificado(s))." >&2
  exit 1
fi
echo "check-pg-migration: ok ($verificados arquivo(s) verificado(s), $ignorados ignorado(s))."
