#!/usr/bin/env bash
# Confere ferramentas, versão do mgc, login e região. Não cria nada.
source "$(dirname "$0")/lib/common.sh"

info "Ferramentas"
require_cmd mgc "Instale: brew trust magalucloud/mgccli && brew install magalucloud/mgccli/mgccli"
require_cmd jq "Instale: brew install jq"
require_cmd openssl "Vem com o macOS."
require_cmd kubectl "Instale: brew install kubectl"
require_cmd helm "Instale: brew install helm"

version=$(mgc --version 2>/dev/null | sed -n 's/.*version v\{0,1\}\([0-9][0-9.]*\).*/\1/p' | head -1)
[[ -n "$version" ]] || die "Não consegui ler a versão do mgc."
version_ge "$version" "$MGC_MIN_VERSION" ||
  die "mgc $version é antigo (mínimo $MGC_MIN_VERSION). Atualize: brew upgrade mgccli"
ok "mgc $version, $(kubectl version --client 2>/dev/null | head -1), helm $(helm version --short 2>/dev/null)"

info "Login na Magalu Cloud"
# Uma leitura simples: falha se não houver login válido.
if ! mgc_json kubernetes cluster list >/dev/null; then
  die "Sem login válido. Rode: mgc auth login (abre o navegador) e confira o tenant com: mgc auth tenant current"
fi
ok "Login válido (região $MGC_REGION)"

info "Configuração (${CONFIG_FILE#"$ROOT"/})"
for name in DB_INSTANCE_TYPE TRAEFIK_CHART_VERSION CERT_MANAGER_VERSION ACME_EMAIL; do
  if [[ -z "${!name:-}" ]]; then warn "$name ainda vazio (necessário antes da etapa correspondente)"; fi
done
[[ -n "$K8S_VERSION" ]] || warn "K8S_VERSION vazio: o cluster usará a versão mais recente. Opções: mgc kubernetes version list"
ok "Preflight concluído"
