#!/usr/bin/env bash
# Buckets privados de anexos (T13) e de backups, e a credencial do app (vai para secrets/).
source "$(dirname "$0")/lib/common.sh"

ensure_bucket() {
  local bucket="$1"
  info "Bucket '$bucket'"
  if mgc_json object-storage buckets list | find_id_by_name "$bucket" | grep -q .; then
    ok "Já existe"
    return
  fi
  confirm "Criar o bucket PRIVADO '$bucket' (com versionamento) em $MGC_REGION?"
  mgc_run object-storage buckets create --bucket "$bucket" --bucket-is-prefix=false \
    --enable-versioning=true --private
  ok "Criado"
}

ensure_bucket "$BUCKET_ATTACHMENTS"
ensure_bucket "$BUCKET_BACKUPS"

info "Credencial do Object Storage para o app ('$OBJECT_STORAGE_KEY_NAME')"
if [[ -n "$(read_secret object-storage.env S3_ACCESS_KEY)" ]]; then
  ok "Já existe em secrets/object-storage.env"
else
  existing=$(mgc_json object-storage api-key list | find_id_by_name "$OBJECT_STORAGE_KEY_NAME")
  [[ -z "$existing" ]] ||
    die "Já existe uma chave '$OBJECT_STORAGE_KEY_NAME' na conta, mas não em secrets/. Revogue-a (mgc object-storage api-key revoke) ou copie os valores para secrets/object-storage.env à mão."
  warn "A chave do Object Storage da Magalu vale para todos os buckets da conta (não há escopo por bucket no CLI)."
  confirm "Criar a chave '$OBJECT_STORAGE_KEY_NAME'?"
  created=$(mgc_json object-storage api-key create --name "$OBJECT_STORAGE_KEY_NAME" \
    --description "helpdesk: anexos e backups")
  key_id=$(printf '%s' "$created" | first_value "uuid,id")
  [[ -n "$key_id" ]] || die "Não consegui ler o id da chave criada. Confira: mgc object-storage api-key list"
  details=$(mgc_json object-storage api-key get "$key_id")
  access=$(printf '%s' "$details" | first_value "key_pair_id,access_key,access_key_id")
  secret=$(printf '%s' "$details" | first_value "key_pair_secret,secret_key,secret_access_key")
  [[ -n "$access" && -n "$secret" ]] ||
    die "Chave criada ($key_id), mas não consegui ler o par de acesso. Veja com: mgc object-storage api-key get $key_id"
  write_secret object-storage.env S3_ACCESS_KEY "$access"
  write_secret object-storage.env S3_SECRET_KEY "$secret"
  ok "Credencial gravada em secrets/object-storage.env (não impressa)"
fi

cat <<MSG

Valores não secretos para o Secret do app (helpdesk/docs/ambientes.md §2.1):
  STORAGE_DRIVER=s3
  S3_ENDPOINT=https://$MGC_REGION.magaluobjects.com   # ⚠️ P4: confirmar no painel
  S3_REGION=$MGC_REGION
  S3_BUCKET=$BUCKET_ATTACHMENTS
MSG
