#!/usr/bin/env bash
# Cluster Kubernetes gerenciado (ADR-007: 2 nós) e o kubeconfig em secrets/.
source "$(dirname "$0")/lib/common.sh"

cluster_id() { mgc_json kubernetes cluster list | find_id_by_name "$K8S_CLUSTER_NAME"; }
cluster_state() { mgc_json kubernetes cluster get --cluster-id "$1" | first_value "state,status"; }

info "Cluster '$K8S_CLUSTER_NAME'"
id=$(cluster_id)
if [[ -n "$id" ]]; then
  ok "Já existe ($id)"
else
  node_pools=$(jq -cn --arg name "$K8S_NODEPOOL_NAME" --arg flavor "$K8S_NODE_FLAVOR" \
    --argjson n "$K8S_NODE_COUNT" \
    '[{name: $name, flavor: $flavor, replicas: $n, auto_scale: {min_replicas: $n, max_replicas: $n}}]')
  args=(--name "$K8S_CLUSTER_NAME" --description "MSMT produção (help desk e Zitadel)"
    --node-pools "$node_pools")
  [[ -n "$K8S_VERSION" ]] && args+=(--version "$K8S_VERSION")
  if [[ -n "$K8S_ALLOWED_CIDRS" ]]; then
    args+=(--allowed-cidrs "$(jq -cn --arg c "$K8S_ALLOWED_CIDRS" '$c | split(",")')")
  fi
  confirm "Criar o cluster '$K8S_CLUSTER_NAME' com $K8S_NODE_COUNT × $K8S_NODE_FLAVOR (versão ${K8S_VERSION:-mais recente}) em $MGC_REGION? Isso gera custo."
  mgc_run kubernetes cluster create "${args[@]}"
  id=$(cluster_id)
  [[ -n "$id" ]] || die "Cluster criado, mas não apareceu na listagem. Confira: mgc kubernetes cluster list"
fi

# A criação leva vários minutos. Estados terminais conhecidos: running / provisioned. ⚠️ conferir na 1ª execução.
wait_for_state "Cluster" "running,provisioned,active" 1800 cluster_state "$id"

info "Kubeconfig"
kc=$(kubeconfig_path)
ensure_secrets_dir
mgc kubernetes cluster kubeconfig --cluster-id "$id" --region "$MGC_REGION" --raw 2>/dev/null |
  sed -n '/^apiVersion:/,$p' >"$kc.tmp"
grep -q '^apiVersion:' "$kc.tmp" || {
  rm -f "$kc.tmp"
  die "Não consegui baixar o kubeconfig. Tente: mgc kubernetes cluster kubeconfig --cluster-id $id"
}
mv "$kc.tmp" "$kc"
chmod 600 "$kc"
ok "Gravado em ${kc#"$ROOT"/} (não versionado)"

info "Nós"
kctl get nodes -o wide
