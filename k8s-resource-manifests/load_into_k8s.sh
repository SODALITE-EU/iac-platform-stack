#! /bin/bash

KUBECTL=${KUBECTL:-kubectl}

uuid() {
    python3 -c 'import uuid; print(uuid.uuid4())'
}

genpw() {
    openssl rand -base64 16
}

set -xe

if [ ! -f .env ]
then
    export KEYCLOAK_CLIENT_SECRET=$(uuid)
    export VAULT_ROOT_TOKEN=$(uuid)
    export KEYCLOAK_ADMIN_PASSWORD=$(genpw)
    
    envsubst < .env.tmpl > .env
fi

source .env

for TMPL in $(find . -name '*.tmpl')
do
    envsubst < $TMPL > $(echo $TMPL | sed 's/.tmpl//' )
done

$KUBECTL apply -f namespace-sodalite-services.yaml

for YAML in $(find . -name '*.yaml')
do
    $KUBECTL apply -f $YAML
done