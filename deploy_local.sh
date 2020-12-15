#!/usr/bin/env bash
PIP_INSTALLED=$(which pip3)
if [ -z "$PIP_INSTALLED" ]; then
    echo
    echo
    read -p "pip3 is not installed. Do you wish to update and install pip? " ynp
    if [ "$ynp" != "${ynp#[Yy]}" ] ;then
        echo
        echo "Installing pip3"
    else
        echo
        echo "Abort."
        return
    fi
    sudo apt update
    sudo apt install -y python3 python3-pip
fi

OPERA_INSTALLED=$(pip3 show opera)

if [ -z "$OPERA_INSTALLED" ]; then
    echo
    echo
    read -p "xOpera is not installed. Do you wish to update and install xOpera and required packages? " yn
    if [ "$yn" != "${yn#[Yy]}" ] ;then
        echo
        echo "Installing xOpera"
    else
        echo
        echo "Abort."
        return
    fi
    sudo apt update
    sudo apt install -y python3-venv python3-wheel python-wheel-common
    sudo apt install -y ansible
    python3 -m venv --system-site-packages .venv && . .venv/bin/activate
    pip3 install "opera==0.5.7"
fi

echo
echo "Installing required Ansible roles"
ansible-galaxy install -r ./docker-local/requirements.yml --force

export CURRENT_USER=$(whoami)

echo
echo
echo "Running installation script as" $CURRENT_USER

echo
echo
echo "These are basic minimal inputs. If more advanced inputs are required please edit /docker-local/input.yaml file manually."
echo
echo "Please enter email for SODALITE certificate: "
read EMAIL_INPUT
export SODALITE_EMAIL=$EMAIL_INPUT

echo "Please enter username for SODALITE blueprint database: "
read USERNAME_INPUT
export SODALITE_DB_USERNAME=$USERNAME_INPUT

echo "Please enter password for SODALITE blueprint database: "
read PASSWORD_INPUT
export SODALITE_DB_PASSWORD=$PASSWORD_INPUT

echo "Please enter token for SODALITE Gitlab repository: "
read TOKEN_INPUT
export SODALITE_GIT_TOKEN=$TOKEN_INPUT

envsubst < ./docker-local/input.yaml.tmpl > ./docker-local/input.yaml

echo
echo "Cloning modules"
rm -r -f docker-local/modules/
git clone -b 2.0.0 https://github.com/SODALITE-EU/iac-modules.git docker-local/modules

echo
echo "Checking TLS key and certificate..."
FILE_KEY=docker-local/modules/docker/artifacts/ca.key
if [ -f "$FILE_KEY" ]; then
    echo "TLS key file already exists."
else 
    echo "TLS key does not exist. Generating..."
    openssl genrsa -out $FILE_KEY 4096
fi
FILE_CRT=docker-local/modules/docker/artifacts/ca.crt
if [ -f "$FILE_CRT" ]; then
    echo "TLS certificate file already exists."
else 
    echo "TLS certificate does not exist. Generating..."
    openssl req -new -x509 -key $FILE_KEY -out $FILE_CRT -subj "/C=SI/O=XLAB/CN=$SODALITE_EMAIL" 2>/dev/null
fi

unset SODALITE_GIT_TOKEN                                                                                                                                                                                                                                                                                                     unset SODALITE_EMAIL
unset SODALITE_DB_USERNAME
unset SODALITE_DB_PASSWORD
unset SODALITE_EMAIL

cd docker-local
opera deploy -i input.yaml service.yaml
