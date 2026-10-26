# Infraestrutura da MSMT na Magalu Cloud. Cada alvo é idempotente e pergunta antes de criar ou alterar.
# ASSUME_YES=1 make <alvo> pula as perguntas.
.PHONY: help preflight registry storage cluster database addons all status

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

preflight: ## Confere ferramentas, versão do mgc e login (não cria nada)
	@scripts/00-preflight.sh
registry: preflight ## Container Registry
	@scripts/10-registry.sh
storage: preflight ## Buckets de anexos e backups + credencial do app
	@scripts/20-object-storage.sh
cluster: preflight ## Cluster Kubernetes (2 nós) + kubeconfig em secrets/
	@scripts/30-kubernetes.sh
database: preflight ## DBaaS PostgreSQL + bancos zitadel e helpdesk (precisa do cluster)
	@scripts/40-database.sh
addons: preflight ## Traefik + cert-manager + ClusterIssuers (precisa do cluster)
	@scripts/50-addons.sh
all: registry storage cluster database addons ## Tudo, na ordem
status: ## Situação dos recursos (só leitura)
	@scripts/90-status.sh
