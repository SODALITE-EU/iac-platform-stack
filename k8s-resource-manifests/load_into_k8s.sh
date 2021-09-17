#! /bin/bash

KUBECTL=${KUBECTL:-kubectl}

uuid() {
    python3 -c 'import uuid; print(uuid.uuid4())'
}

set -xe

if [ ! -f .env ]
then
    export CLIENT_SECRET=$(uuid)
    export VAULT_TOKEN=$(uuid)

    envsubst < .env.tmpl > .env
fi

source .env

envsubst < keycloak-secret.yaml.tmpl > keycloak-secret.yaml
envsubst < vault.yaml.tmpl > vault.yaml

$KUBECTL apply -f namespace-sodalite-services.yaml

$KUBECTL apply -f keycloak-secret.yaml
$KUBECTL apply -f keycloak.yaml

$KUBECTL apply -f vault.yaml
