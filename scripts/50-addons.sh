#!/usr/bin/env bash
# Add-ons do cluster (ADR-007): Traefik (ingress, com h2c para o Zitadel) e cert-manager com Let's Encrypt.
source "$(dirname "$0")/lib/common.sh"

require_var TRAEFIK_CHART_VERSION "Versões: helm repo add traefik https://traefik.github.io/charts && helm search repo traefik/traefik --versions | head"
require_var CERT_MANAGER_VERSION "Versões: helm repo add jetstack https://charts.jetstack.io && helm search repo jetstack/cert-manager --versions | head"
require_var ACME_EMAIL "E-mail que recebe os avisos do Let's Encrypt."

confirm "Instalar/atualizar Traefik $TRAEFIK_CHART_VERSION e cert-manager $CERT_MANAGER_VERSION no cluster '$K8S_CLUSTER_NAME'?"

hlm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
hlm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
hlm repo update traefik jetstack >/dev/null

info "Validação local dos valores (sem tocar o cluster)"
helm template traefik traefik/traefik --version "$TRAEFIK_CHART_VERSION" -n traefik \
  -f "$ROOT/helm/traefik-values.yaml" >/dev/null || die "helm/traefik-values.yaml não passa no schema do chart $TRAEFIK_CHART_VERSION."
ok "Valores do Traefik válidos"

info "Traefik"
# Service LoadBalancer: a Magalu cria o balanceador e o IP público (vai para o DNS).
hlm upgrade --install traefik traefik/traefik --version "$TRAEFIK_CHART_VERSION" \
  --namespace traefik --create-namespace -f "$ROOT/helm/traefik-values.yaml" --wait --timeout 10m
ok "Traefik instalado"

info "cert-manager"
hlm upgrade --install cert-manager jetstack/cert-manager --version "$CERT_MANAGER_VERSION" \
  --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m
sed "s|__ACME_EMAIL__|$ACME_EMAIL|" "$ROOT/k8s/cluster-issuers.yaml" | kctl apply -f -
ok "cert-manager e ClusterIssuers (letsencrypt-staging, letsencrypt-prod) prontos"

info "IP público do Traefik"
for _ in $(seq 1 30); do
  ip=$(kctl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "$ip" ]] && break
  sleep 10
done
if [[ -n "${ip:-}" ]]; then
  ok "IP: $ip"
  cat <<MSG

Crie no DNS de msmt.org.br (registros A, TTL 300):
  suporte.msmt.org.br  →  $ip
  auth.msmt.org.br     →  $ip
MSG
else
  warn "O balanceador ainda não tem IP. Confira depois: kubectl -n traefik get svc traefik"
fi
