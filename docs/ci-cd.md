# Relação com o CI/CD do Help Desk

Este repositório **provisiona** a infraestrutura (registry, cluster, banco, add-ons) de forma
manual e interativa — cada alvo do `Makefile` pergunta antes de criar ou alterar algo, porque
cria recursos com custo na Magalu Cloud. Por isso ele não tem (e não deve ter) uma pipeline de
CI/CD que rode automaticamente a cada push: isso arriscaria recriar ou alterar infraestrutura de
produção sem revisão humana.

Quem roda em CI/CD automaticamente é a aplicação: veja `docs/ci-cd.md` no repositório
[`helpdesk`](https://github.com/Missao-Salesiana-de-Mato-Grosso/helpdesk). A pipeline do
`helpdesk` consome recursos **criados por este repositório**:

- Container Registry `cr-msmt-prd` (criado por `make registry`, script `10-registry.sh`)
- Cluster Kubernetes `k8s-msmt-prd` (criado por `make cluster`, script `30-kubernetes.sh`)
- DBaaS PostgreSQL `pg-msmt-prd-web` com os bancos `zitadel` e `helpdesk` (`make database`)

## O que a pipeline do helpdesk precisa deste repositório

A pipeline do `helpdesk` autentica no `mgc` CLI com uma API Key própria (secret `MGC_API_KEY`
no GitHub do `helpdesk`, não aqui) e usa, a partir daqui:

- O kubeconfig gerado em `secrets/kubeconfig-k8s-msmt-prd.yaml` (por `make cluster`) — copiado
  para o secret `KUBECONFIG_PROD` do `helpdesk`. Se o cluster for recriado, o kubeconfig muda e
  o secret precisa ser atualizado.
- As credenciais de banco (`secrets/database.env`) e de object storage
  (`secrets/object-storage.env`) geradas por `make database` e `make storage` — copiadas para os
  secrets correspondentes do `helpdesk`.

Nenhum arquivo de `secrets/` deste repositório é lido diretamente pela pipeline (ela não tem
acesso a esta máquina); os valores são copiados manualmente, uma vez, para os secrets do GitHub
do `helpdesk`, e atualizados ali sempre que forem rotacionados aqui.
