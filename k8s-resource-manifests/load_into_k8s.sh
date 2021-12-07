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

$KUBECTL apply -f namespace-sodalite-services.yaml

# We need to do vault first, because it generates teh root token later used by pretty
# much everything else.
for YAML in $(find vault -name '*.yaml')
do
    if [ -z "$(grep "sodalite-services" $YAML)" ]
    then
        echo "$YAML is not deployed in the sodalite-services namespace! Refusing to deploy"
        exit 1
    fi
    $KUBECTL apply -f $YAML
done

# Wait for vault to come up
while [ -z "$($KUBECTL get pods -n sodalite-services | grep vault-0 | grep Running)" ]
do
    sleep 1
done

# No .env will mean this is a first initialization/clean state. So nothing is
# saved.
if [ ! -f .env ]
then
    # Now some specific setup for services that must be done exactly once.
    #First up, initalize vault
    VAULT_UNSEAL=$($KUBECTL exec -it -n sodalite-services vault-0 -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator init")
    echo "$VAULT_UNSEAL"

    #read -p "Pausing for you to record those vaules. Press enter when done."

    echo "Auto-unlocking vault..."
    echo "$VAULT_UNSEAL" | grep 'Unseal Key' | awk '{print $4}' | tr '\n' ' '
    vault_keys=""
    for KEY in $(echo "$VAULT_UNSEAL" | grep 'Unseal Key' | awk '{print $4}')
    do
        PARSED_KEY=$( echo $KEY | tr -d '[[:cntrl:]]' | sed 's/0m$//' )
        $KUBECTL exec -it -n sodalite-services vault-0 -- vault operator unseal -address="http://127.0.0.1:8200" "$PARSED_KEY"
        vault_keys=${vault_keys}\n${PARSED_KEY}
    done
    export VAULT_KEYS=$vault_keys

    export VAULT_ROOT_TOKEN=$(echo "$VAULT_UNSEAL" | grep 'Initial Root Token:' | awk '{print $4}' | tr -d "[[:cntrl:]]" | sed 's/0m$//' )

    # Generate deployment-specific secrets here
    export KEYCLOAK_CLIENT_SECRET=$(uuid)
    export KEYCLOAK_ADMIN_PASSWORD=$(genpw)
    export KEYCLOAK_DB_PASSWORD=$(genpw)
    export GRAFANA_ADMIN_PASSWORD=$(genpw)
    export XOPERA_POSTGRES_PASSWORD=$(genpw)
    export KB_PASSWORD=$(genpw)
    
    # Generate keys for xopera
    XOPERA_KEY_FILE=$(mktemp -u)
    ssh-keygen -f $XOPERA_KEY_FILE -N ''
    export XOPERA_PRIVATE_KEY=$(cat ${XOPERA_KEY_FILE})
    export XOPERA_PUBLIC_KEY=$(cat ${XOPERA_KEY_FILE}.pub)
    rm ${XOPERA_KEY_FILE} ${XOPERA_KEY_FILE}.pub

    # Dump generated secrets into .env so we can use them elsewhere.
    envsubst < .env.tmpl > .env
fi

source .env

# Now that (One way or another) we have a .env, use values from that to fill out
# all our templates
for TMPL in $(find . -name '*.tmpl')
do
    if [ "$TMPL" == "./keycloak/secret-realm.yaml.tmpl" ]
    then
        envsubst '${KEYCLOAK_REALM}${KEYCLOAK_CLIENT_ID}${KEYCLOAK_CLIENT_SECRET}' < $TMPL > $(echo $TMPL | sed 's/.tmpl//' )
    else
        envsubst < $TMPL > $(echo $TMPL | sed 's/.tmpl//' )
    fi
done

$KUBECTL apply -f vault/secret-token.yaml

# Set up lets encrypt per https://www.scaleway.com/en/docs/tutorials/traefik-v2-cert-manager/
$KUBECTL apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
echo "Waiting for cert-manager to be ready..."
date
RES=1
while [ $RES != 0 ]
do
    sleep 10
    set +x
    $KUBECTL apply -f cert-issuer.yaml 2>/dev/null
    RES=$?
    set -x
done
date
$KUBECTL apply -f cert-issuer-test.yaml

# Apply our changes to the Scaleway instance of traefik2.
$KUBECTL apply -f scaleway-traefik-daemonSet.yaml
$KUBECTL apply -f scaleway-traefik-loadBalancer.yaml

# We also want to delete all traefik pods to force them to restart with the right config
kubectl -n kube-system delete pod -l app.kubernetes.io/name=traefik

# And start applying other services. k8s will take care of anything that
# isn't quite up/in the wrong order, so we can just batch apply things
for CDIR in keycloak keycloak-postgres vault-secret-uploader xopera-postgres xopera-rest-api iac-builder knowledge-db semantic-web tosca-smells consul alertmanager prometheus ruleserver prometheus-skydive-connector skydive-analyzer registry
do
for YAML in $(find $CDIR -name '*.yaml')
do
    if [ -z "$(grep -i "namespace: sodalite-services" $YAML)" ]
    then
        echo "$YAML is not deployed in the sodalite-services namespace! Refusing to deploy"
        exit 1
    fi
    $KUBECTL apply -f $YAML
done
done
