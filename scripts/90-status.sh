#!/usr/bin/env bash
# Só leitura: situação de todos os recursos.
source "$(dirname "$0")/lib/common.sh"

show() {
  local label="$1" name="$2"
  shift 2
  if mgc_json "$@" | find_id_by_name "$name" | grep -q .; then ok "$label '$name'"; else warn "$label '$name' não existe"; fi
}
show "Registry" "$REGISTRY_NAME" container-registry registries list
show "Bucket" "$BUCKET_ATTACHMENTS" object-storage buckets list
show "Bucket" "$BUCKET_BACKUPS" object-storage buckets list
show "Cluster" "$K8S_CLUSTER_NAME" kubernetes cluster list
show "DBaaS" "$DB_INSTANCE_NAME" dbaas instances list
if [[ -f "$(kubeconfig_path)" ]]; then
  kctl get nodes
  kctl -n traefik get svc traefik 2>/dev/null || warn "Traefik não instalado"
  kctl get clusterissuers 2>/dev/null || warn "cert-manager não instalado"
fi
