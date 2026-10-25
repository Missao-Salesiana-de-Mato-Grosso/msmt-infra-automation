#!/usr/bin/env bash
# DBaaS PostgreSQL e os bancos/usuários `zitadel` e `helpdesk`. As senhas vão para secrets/database.env.
source "$(dirname "$0")/lib/common.sh"

require_var DB_INSTANCE_TYPE "Opções: mgc dbaas instance-types list"

instance_id() { mgc_json dbaas instances list | find_id_by_name "$DB_INSTANCE_NAME"; }

# A listagem padrão omite instâncias com falha. Uma instância com erro e o mesmo nome bloqueia a criação.
failed_instance() {
  local status
  for status in ERROR ERROR_DELETING ERROR_RESIZING ERROR_STARTING; do
    mgc_json dbaas instances list --status "$status" | find_id_by_name "$DB_INSTANCE_NAME"
  done | head -1
}
instance_state() { mgc_json dbaas instances get "$1" | first_value "status,state"; }

info "Instância DBaaS '$DB_INSTANCE_NAME'"
id=$(instance_id)
failed=$(failed_instance)
[[ -z "$id" && -n "$failed" ]] &&
  die "A instância '$DB_INSTANCE_NAME' existe com status de ERRO ($failed). Exclua pelo painel (ou: mgc dbaas instances delete $failed) e rode de novo."
if [[ -n "$id" ]]; then
  ok "Já existe ($id)"
else
  engine_id=$(mgc_json dbaas engines list --status ACTIVE | jq -r --arg n "$DB_ENGINE_NAME" --arg v "$DB_ENGINE_VERSION" \
    '[.results[]? | select((.name // "" | ascii_downcase) == $n and ((.version // "") | tostring) == $v)][0].id // empty')
  [[ -n "$engine_id" ]] || die "Engine $DB_ENGINE_NAME $DB_ENGINE_VERSION não encontrado. Opções: mgc dbaas engines list"
  # O mesmo rótulo (ex.: BV1-4-10) existe para cada engine e produto: filtra pelo engine e por instância única.
  type_id=$(mgc_json dbaas instance-types list --engine-id "$engine_id" --status ACTIVE --control.limit 200 |
    jq -r --arg n "$DB_INSTANCE_TYPE" \
      '[.results[]? | select(.compatible_product == "SINGLE_INSTANCE" and (.label == $n or .name == $n))][0].id // empty')
  [[ -n "$type_id" ]] || die "Tipo '$DB_INSTANCE_TYPE' não encontrado. Opções: mgc dbaas instance-types list"

  admin_password=$(read_secret database.env DB_ADMIN_PASSWORD)
  if [[ -z "$admin_password" ]]; then
    admin_password=$(random_password)
    write_secret database.env DB_ADMIN_PASSWORD "$admin_password"
  fi
  confirm "Criar a instância '$DB_INSTANCE_NAME' ($DB_ENGINE_NAME $DB_ENGINE_VERSION, $DB_INSTANCE_TYPE, ${DB_VOLUME_SIZE_GB} GB, backup $DB_BACKUP_RETENTION_DAYS dias, protegida contra exclusão)? Isso gera custo."
  mgc_run dbaas instances create --name "$DB_INSTANCE_NAME" --engine-id "$engine_id" \
    --instance-type-id "$type_id" --user "$DB_ADMIN_USER" --password "$admin_password" \
    --volume.size "$DB_VOLUME_SIZE_GB" --availability-zone "$DB_AVAILABILITY_ZONE" \
    --backup-retention-days "$DB_BACKUP_RETENTION_DAYS" --backup-start-at "$DB_BACKUP_START_AT" \
    --deletion-protected >/dev/null
  id=$(instance_id)
  [[ -n "$id" ]] || die "Instância criada, mas não apareceu na listagem. Confira: mgc dbaas instances list"
fi

wait_for_state "DBaaS" "active,running,available" 1800 instance_state "$id"

# Instância criada pelo painel: a senha do admin não foi gerada aqui. Pede uma vez, sem eco, e guarda em secrets/.
if [[ -z "$(read_secret database.env DB_ADMIN_PASSWORD)" ]]; then
  [[ -t 0 ]] || die "A senha do admin não está em secrets/database.env e não há terminal para pedi-la. Rode numa janela do Terminal."
  read -r -s -p "Senha do usuário '$DB_ADMIN_USER' da instância (não aparece na tela): " admin_password
  printf '\n'
  [[ -n "$admin_password" ]] || die "Senha vazia."
  write_secret database.env DB_ADMIN_PASSWORD "$admin_password"
  ok "Senha gravada em secrets/database.env"
fi

# Retenção de backup, horário e proteção contra exclusão: garante os valores do config mesmo se criada pelo painel.
current=$(mgc_json dbaas instances get "$id")
retention=$(printf '%s' "$current" | jq -r '[.. | objects | .backup_retention_days? // empty][0] // empty')
protected=$(printf '%s' "$current" | jq -r '[.. | objects | .deletion_protected? | select(. != null)][0] // empty')
if [[ "$retention" != "$DB_BACKUP_RETENTION_DAYS" || "$protected" != "true" ]]; then
  confirm "Ajustar a instância: backup por $DB_BACKUP_RETENTION_DAYS dias às $DB_BACKUP_START_AT UTC e proteção contra exclusão (hoje: retenção=${retention:-?}, protegida=${protected:-?})?"
  mgc_run dbaas instances update --instance-id "$id" --backup-retention-days "$DB_BACKUP_RETENTION_DAYS" \
    --backup-start-at "$DB_BACKUP_START_AT" --deletion-protected >/dev/null
  ok "Backup e proteção ajustados"
else
  ok "Backup ($retention dias) e proteção contra exclusão já ativos"
fi

details=$(mgc_json dbaas instances get "$id")
host=$(printf '%s' "$details" | jq -r '[.. | objects | select(.access? == "PRIVATE" or .type? == "private") | (.address // .ip // empty)][0] // empty')
[[ -n "$host" ]] || host=$(printf '%s' "$details" | first_value "address,host,ip")
[[ -n "$host" ]] || die "Não consegui ler o endereço da instância. Veja: mgc dbaas instances get $id"
write_secret database.env DB_HOST "$host"
ok "Endereço gravado em secrets/database.env"

# Bancos e usuários: o mgc não cria databases. Um pod psql temporário, de dentro do cluster (mesma rede
# privada do DBaaS), executa o SQL. Idempotente: só cria o que falta e redefine as senhas para as de secrets/.
info "Bancos 'zitadel' e 'helpdesk'"
for app in zitadel helpdesk; do
  key="DB_$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')_PASSWORD"
  [[ -n "$(read_secret database.env "$key")" ]] || write_secret database.env "$key" "$(random_password)"
done
confirm "Criar/atualizar os bancos e usuários 'zitadel' e 'helpdesk' na instância (via pod temporário no cluster)?"

sql=$(
  cat <<SQL
SELECT 'CREATE ROLE zitadel LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'zitadel')\gexec
SELECT 'CREATE ROLE helpdesk LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'helpdesk')\gexec
ALTER ROLE zitadel PASSWORD '$(read_secret database.env DB_ZITADEL_PASSWORD)';
ALTER ROLE helpdesk PASSWORD '$(read_secret database.env DB_HELPDESK_PASSWORD)';
GRANT zitadel TO CURRENT_USER;
GRANT helpdesk TO CURRENT_USER;
SELECT 'CREATE DATABASE zitadel OWNER zitadel' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'zitadel')\gexec
SELECT 'CREATE DATABASE helpdesk OWNER helpdesk' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'helpdesk')\gexec
\c helpdesk
CREATE EXTENSION IF NOT EXISTS citext;
SQL
)
pod="db-bootstrap-$(date +%s)"
# Senha do admin (1ª linha) e SQL vão pela entrada padrão: nada de segredo na especificação do pod, na linha
# de comando ou no log. sslmode=prefer: usa TLS se o DBaaS oferecer (rede privada de qualquer forma).
{
  read_secret database.env DB_ADMIN_PASSWORD
  printf '%s\n' "$sql"
} | kctl run "$pod" --rm -i --restart=Never --quiet --image=postgres:17-alpine -- \
  sh -c 'IFS= read -r PGPASSWORD; export PGPASSWORD; exec psql "host='"$host"' user='"$DB_ADMIN_USER"' dbname=postgres sslmode=prefer" -v ON_ERROR_STOP=1 -q' ||
  die "Falhou a criação dos bancos. Se for timeout de conexão, o cluster não alcança o DBaaS (P10)."
ok "Bancos e usuários prontos. Senhas em secrets/database.env (não impressas)"
