# msmt-infra-automation

Infraestrutura da Missão Salesiana de Mato Grosso na **Magalu Cloud**, criada pelo CLI `mgc` com scripts
idempotentes. Este repositório cria a plataforma; os apps (help desk e Zitadel) são publicados pelos
próprios repositórios (`helpdesk`: `make deploy`, manifestos em `deploy/k8s` e `deploy/zitadel`).

| Recurso | Script | Observação |
| --- | --- | --- |
| Container Registry | `10-registry.sh` | imagens do `make deploy` |
| Object Storage | `20-object-storage.sh` | buckets privados `helpdesk-anexos` e `helpdesk-backups`, chave do app |
| Kubernetes gerenciado | `30-kubernetes.sh` | 2 nós (ADR-007 do helpdesk), kubeconfig em `secrets/` |
| DBaaS PostgreSQL | `40-database.sh` | bancos e usuários `zitadel` e `helpdesk`, backup automático |
| Add-ons | `50-addons.sh` | Traefik (LoadBalancer), cert-manager, ClusterIssuers do Let's Encrypt |

## Uso

```bash
brew trust magalucloud/mgccli   # Homebrew recente recusa taps de terceiros sem isso (tap oficial da Magalu)
brew upgrade mgccli     # a fórmula é mgccli (o comando é mgc); mínimo v0.67
brew install jq helm    # kubectl e openssl já existem
mgc auth login          # abre o navegador; confira o tenant: mgc auth tenant current
make preflight          # não cria nada
make registry storage cluster database addons   # ou: make all
make status             # só leitura
```

- Cada script confere se o recurso já existe (pelo nome) e **pergunta antes de criar ou alterar**. Rodar de novo é seguro.
- Toda a configuração não secreta está em `config/prod.env`. Preencha os campos marcados com ⚠️ antes da etapa correspondente
  (`DB_INSTANCE_TYPE`, versões dos charts, `ACME_EMAIL`).
- **Segredos** (senhas do banco, chave do Object Storage, kubeconfig) são gerados pelos scripts em `secrets/`
  (permissão 600, no `.gitignore`) e nunca são impressos. Guarde uma cópia no cofre da equipe. Perder `secrets/` não apaga
  nada na nuvem, mas obriga a redefinir as senhas.
- `kubectl` e `helm` usam sempre `secrets/kubeconfig-<cluster>.yaml`, nunca o contexto atual da máquina.

## A conferir na 1ª execução

Os comandos e flags vêm do `mgc --help` (v0.48). Alguns formatos de saída só se confirmam contra a conta real:

- estados finais de cluster e DBaaS (`running`/`active`) e o campo do endereço privado do DBaaS;
- os campos da chave do Object Storage (`api-key get`) e o endpoint S3 (P4 em `helpdesk/docs/ambientes.md` §2.0);
- o host do Container Registry para o `docker login`;
- se o DBaaS fica acessível a partir dos nós do cluster (mesma VPC). O `40-database.sh` cria os bancos com um pod `psql`
  temporário de dentro do cluster.

Se algum script falhar por formato de saída, ajuste o helper em `scripts/lib/common.sh` e registre a armadilha aqui.
