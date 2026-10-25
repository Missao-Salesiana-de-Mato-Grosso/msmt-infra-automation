#!/usr/bin/env bash
# Funções comuns dos scripts de provisionamento. Carregue com: source "$(dirname "$0")/lib/common.sh"
#
# Regras que todo script segue:
# - idempotente: confere se o recurso já existe (pelo nome) antes de criar;
# - pergunta antes de criar ou alterar (ASSUME_YES=1 pula a pergunta);
# - nunca imprime segredo: senhas, chaves e kubeconfig vão para secrets/ com permissão 600.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_DIR="$ROOT/secrets"
CONFIG_FILE="${CONFIG_FILE:-$ROOT/config/prod.env}"

# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [[ -t 1 ]]; then
  BOLD=$'\e[1m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' RESET=$'\e[0m'
else
  BOLD='' RED='' GREEN='' YELLOW='' RESET=''
fi

info() { printf '%s\n' "${BOLD}==>${RESET} $*"; }
ok() { printf '%s\n' "${GREEN}✔${RESET} $*"; }
warn() { printf '%s\n' "${YELLOW}⚠${RESET} $*" >&2; }
die() {
  printf '%s\n' "${RED}✘${RESET} $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando '$1' não encontrado. $2"
}

require_var() {
  local name="$1" hint="$2"
  [[ -n "${!name:-}" ]] || die "Defina $name em ${CONFIG_FILE#"$ROOT"/}. $hint"
}

# Pergunta antes de uma ação que cria ou altera recursos (com custo, em produção).
confirm() {
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  # Sem terminal (ex.: `!` do Claude Code, CI), o read falharia em silêncio: avisa em vez de sair calado.
  [[ -t 0 ]] || die "Confirmação necessária, mas não há terminal interativo: $*
  Rode este comando numa janela do Terminal (recomendado) ou repita com ASSUME_YES=1 se já revisou o que será feito."
  local answer
  read -r -p "${BOLD}$* [s/N]${RESET} " answer
  [[ "$answer" =~ ^[sS]$ ]] || die "Cancelado."
}

# mgc com saída JSON e sem cores. O aviso de versão desatualizada sai antes do JSON: é descartado.
mgc_json() {
  mgc "$@" --region "$MGC_REGION" --output json --raw 2>/dev/null | sed -n '/^[[:space:]]*[[{]/,$p'
}

# mgc para ações (criar/alterar): mostra a saída do CLI, sem confirmação dupla do próprio mgc.
mgc_run() {
  mgc "$@" --region "$MGC_REGION" --no-confirm
}

# Procura um objeto pelo nome em qualquer nível do JSON de uma listagem e devolve o id (ou vazio).
# A forma das listagens varia entre produtos (results, items, Buckets...): a busca é recursiva.
find_id_by_name() {
  local name="$1"
  jq -r --arg n "$name" '
    [.. | objects | select((.name? // .Name?) == $n)][0]
    | if . == null then empty else (.id // .uuid // .name // .Name) end'
}

# Primeiro valor encontrado para uma das chaves, em qualquer nível (ex.: status de um cluster).
first_value() {
  local keys="$1"
  jq -r --arg k "$keys" '
    ($k | split(",")) as $ks
    | [.. | objects | to_entries[] | select(.key as $key | $ks | index($key)) | .value
       | select(type == "string")][0] // empty'
}

# Espera até o comando devolver um dos estados esperados (ou estourar o tempo).
wait_for_state() {
  local description="$1" expected="$2" timeout_s="$3"
  shift 3
  local start state
  start=$(date +%s)
  while true; do
    state=$("$@" | tr '[:upper:]' '[:lower:]' || true)
    if [[ ",$expected," == *",$state,"* ]]; then
      ok "$description: $state"
      return 0
    fi
    (($(date +%s) - start > timeout_s)) && die "$description: tempo esgotado (último estado: ${state:-desconhecido})"
    printf '   %s: %s… aguardando\n' "$description" "${state:-desconhecido}"
    sleep 20
  done
}

ensure_secrets_dir() {
  mkdir -p "$SECRETS_DIR"
  chmod 700 "$SECRETS_DIR"
}

# Grava um segredo (chave=valor) em secrets/<arquivo>, com permissão 600. Não imprime o valor.
write_secret() {
  local file="$SECRETS_DIR/$1" key="$2" value="$3"
  ensure_secrets_dir
  touch "$file"
  chmod 600 "$file"
  grep -v "^${key}=" "$file" >"$file.tmp" || true
  printf '%s=%s\n' "$key" "$value" >>"$file.tmp"
  mv "$file.tmp" "$file"
  chmod 600 "$file"
}

read_secret() {
  local file="$SECRETS_DIR/$1" key="$2"
  [[ -f "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -1
}

random_password() {
  # 32 caracteres alfanuméricos (sem símbolos, para não quebrar URLs de conexão).
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
}

kubeconfig_path() {
  printf '%s\n' "$SECRETS_DIR/kubeconfig-$K8S_CLUSTER_NAME.yaml"
}

# kubectl/helm sempre com o kubeconfig do cluster de produção, nunca o contexto atual da máquina.
kctl() {
  local kc
  kc=$(kubeconfig_path)
  [[ -f "$kc" ]] || die "Kubeconfig não encontrado. Rode antes: make cluster"
  kubectl --kubeconfig "$kc" "$@"
}

hlm() {
  local kc
  kc=$(kubeconfig_path)
  [[ -f "$kc" ]] || die "Kubeconfig não encontrado. Rode antes: make cluster"
  helm --kubeconfig "$kc" "$@"
}

version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}
