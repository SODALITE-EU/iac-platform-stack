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
    pip3 install opera
fi

echo
echo "Installing required Ansible roles"
ansible-galaxy install -r ./docker-local/requirements.yml

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

unset SODALITE_GIT_TOKEN                                                                                                                                                                                                                                                                                                     unset SODALITE_EMAIL
unset SODALITE_DB_USERNAME
unset SODALITE_DB_PASSWORD

cd docker-local
opera deploy -i input.yaml service.yaml
