#! /bin/bash

KUBECTL=${KUBECTL:-kubectl}

# Functions for generating secrets
# These functions are used to generate various deployment-specific secrets.

uuid() {
    python3 -c 'import uuid; print(uuid.uuid4())'
}

genpw() {
    openssl rand -base64 16
}

set -xe

if [ ! -f .env ]
then
    # Generate deployment-specific secrets here
    export KEYCLOAK_CLIENT_SECRET=$(uuid)
    export VAULT_ROOT_TOKEN=$(uuid)
    export KEYCLOAK_ADMIN_PASSWORD=$(genpw)
    export GRAFANA_ADMIN_PASSWORD=$(genpw)
    export XOPERA_POSTGRES_PASSWORD=$(genpw)
    
    # Generate keys for xopera
    XOPERA_KEY_FILE=$(mktemp -u)
    ssh-keygen -f $XOPERA_KEY_FILE -N ''
    export XOPERA_PRIVATE_KEY=$(cat ${XOPERA_KEY_FILE})
    export XOPERA_PUBLIC_KEY=$(cat ${XOPERA_KEY_FILE}.pub)
    rm ${XOPERA_KEY_FILE} ${XOPERA_KEY_FILE}.pub

    envsubst < .env.tmpl > .env
fi

source .env

for TMPL in $(find . -name '*.tmpl')
do
    envsubst < $TMPL > $(echo $TMPL | sed 's/.tmpl//' )
done

$KUBECTL apply -f namespace-sodalite-services.yaml

for CDIR in keycloak vault vault-secret-uploader platform-discovery-service xopera-postgres xopera-rest-api
do
for YAML in $(find $CDIR -name '*.yaml')
do
    if [ -z "$(grep "sodalite-services" $YAML)" ]
    then
        echo "$YAML is not deployed in the sodalite-services namespace! Refusing to deploy"
        exit 1
    fi
    $KUBECTL apply -f $YAML
done
done

# Wait for vault to come up
while [ -z "$($KUBECTL get pods -n sodalite-services | grep vault-0 | grep Running)" ]
do
    sleep 1
done

# Now some specific setup for services that must be done exactly once.
#First up, initalize vault
VAULT_UNSEAL=$($KUBECTL exec -it -n sodalite-services vault-0 -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator init")
echo "$VAULT_UNSEAL"

read -p "Pausing for you to record those vaules. Press enter when done."

echo "Auto-unlocking vault..."
echo "$VAULT_UNSEAL" | grep 'Unseal Key' | awk '{print $4}' | tr '\n' ' '
for KEY in $(echo "$VAULT_UNSEAL" | grep 'Unseal Key' | awk '{print $4}' | tr '\n' ' ')
do
    $KUBECTL exec -it -n sodalite-services vault-0 -- sh -c VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal "$KEY"
done