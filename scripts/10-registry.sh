#!/usr/bin/env bash
# Container Registry onde o `make deploy` do helpdesk publica as imagens (T17).
source "$(dirname "$0")/lib/common.sh"

info "Container Registry '$REGISTRY_NAME'"
id=$(mgc_json container-registry registries list | find_id_by_name "$REGISTRY_NAME")
if [[ -n "$id" ]]; then
  ok "Já existe ($id)"
else
  confirm "Criar o registry '$REGISTRY_NAME' em $MGC_REGION?"
  mgc_run container-registry registries create --name "$REGISTRY_NAME"
  ok "Criado"
fi

cat <<MSG

Login do Docker no registry (o usuário e a senha saem de 'mgc container-registry credentials list';
não os cole em chat nem em ticket):
  mgc container-registry credentials list
  docker login container-registry.$MGC_REGION.magalu.cloud   # ⚠️ conferir o host na saída do comando acima
MSG
