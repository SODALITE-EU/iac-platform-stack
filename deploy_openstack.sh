#!/usr/bin/env bash

######################
# Pinned versions

OPERA_VERSION="0.6.4"
IAC_MODULES_VERSION="3.1.1"

########################

# Usage: ./deploy_openstack.sh deploy OPENRC_PATH [--resume]
# Usage: ./deploy_openstack.sh undeploy OPENRC_PATH

# argument parser
if [ $# -gt 3 ] || [ $# -lt 2 ] ||
  [[ "$1" != "deploy" && "$1" != "undeploy" ]] ||
  [[ "$1" == "deploy" && "$3" != "--resume" && "$3" != "--clean-state" && $# -eq 3 ]] ||
  [[ "$1" == "undeploy" && $# -gt 2 ]]; then
  echo "Usage: $0 deploy OPENRC_PATH [--resume]"
  echo "Usage: $0 undeploy OPENRC_PATH"
  exit 1
fi

MODE=$1
OPENRC_PATH=$2
RESUME=${3:-"--clean-state"}
# remove prefix --
RESUME=${RESUME#"--"}

# use .venv, if exists
if [ -f .venv/bin/activate ]; then
  echo
  echo
  read -rp "Python virtual environment found in .venv dir. Do you want to activate it? [Y/n] " ynvenv
  if [ "$ynvenv" != "${ynvenv#[Yy]}" ]; then

    echo "Activating .venv"
    . .venv/bin/activate  || exit 1
  else
    echo "Abort."
  fi

  echo "Switched to python interpreter from $(command -v python3)"

fi

# check current opera and modules version
OPERA_CURRENT_VERSION=$(pip3 show opera 2>/dev/null | grep Version | awk '{print $2}')
IAC_MODULES_CURRENT_VERSION=$(cd openstack/modules 2>/dev/null && git tag --points-at HEAD)

# check prerequisites
APT_PKG_MISSING=$(if python3 apt_pkg_test.py 2>/dev/null; then echo false; else echo true; fi)
OPERA_NOT_INSTALLED=$(if [ -z "$(pip3 show opera 2>/dev/null)" ]; then echo true; else echo false; fi)
OPENSTACKSDK_NOT_INSTALLED=$(if [ -z "$(pip3 show openstacksdk 2>/dev/null)" ]; then echo true; else echo false; fi)
OPERA_WRONG_VERSION=$(if [ "$OPERA_CURRENT_VERSION" != "$OPERA_VERSION" ]; then echo true; else echo false; fi)

# ansible version
ANSIBLE_VERSION=$(ansible --version 2>/dev/null | head -n 1| awk '{print $2}')
ANSIBLE_WRONG_VERSION=$(if [[ $ANSIBLE_VERSION == 2.10*  ]] || [[ -z $ANSIBLE_VERSION ]]; then echo false; else echo true; fi)

# check python3 and pip3
PIP_INSTALLED=$(command -v pip3)
if [ -z "$PIP_INSTALLED" ]; then
  echo
  echo
  read -rp "pip3 is not installed. Do you wish to update and install pip? [Y/n] " ynp
  if [ "$ynp" != "${ynp#[Yy]}" ]; then
    echo
    echo "Installing pip3"

    sudo apt update
    sudo apt install -y python3 python3-pip  || exit 1

  else
    echo
    echo "Abort."
  fi
fi

# check if new venv must be created
if $APT_PKG_MISSING || $OPERA_NOT_INSTALLED || $OPERA_WRONG_VERSION || $OPENSTACKSDK_NOT_INSTALLED || $ANSIBLE_WRONG_VERSION; then
  echo "Missing prerequisites: "

  if $APT_PKG_MISSING; then
    echo "    - Python package apt_get not available with current interpreter from $(command -v python3)"
  fi
  if $OPERA_NOT_INSTALLED; then
    echo "    - xOpera is not installed."
  fi
  if $OPERA_WRONG_VERSION && ! $OPERA_NOT_INSTALLED; then
    echo "    - xOpera is on version $OPERA_CURRENT_VERSION, but version $OPERA_VERSION is needed."
  fi
  if $OPENSTACKSDK_NOT_INSTALLED; then
    echo "    - OpenstackSDK is not installed."
  fi
  if $ANSIBLE_WRONG_VERSION; then
    echo "    - Ansible is on version $ANSIBLE_VERSION, but version 2.10 or greater is required."
  fi

  echo

  read -rp "Do you wish to install/upgrade required system packages and create new venv in .venv dir with xOpera==$OPERA_VERSION? [Y/n] " yn
  if [ "$yn" != "${yn#[Yy]}" ]; then
    echo
    echo

    echo "Installing system packages"
    sudo apt update
    sudo apt install -y python3-venv python3-wheel python-wheel-common python3-apt  || exit 1


    if $ANSIBLE_WRONG_VERSION; then
      echo
      echo "Removing ansible from apt and installing it with pip3"
      sudo apt remove -y ansible
      deactivate 2>/dev/null
      pip3 install --upgrade ansible || exit 1

      # shellcheck disable=SC1090
      # reload path to ansible
      if [ -f ~/.bash_profile ]; then . ~/.bash_profile; else . ~/.profile; fi
      echo "Before using Ansible CLI for the first time, please reload path:"
      echo "source ~/.profile"
    fi

    echo
    echo "Creating new venv"
    sudo rm -rf .venv
    python3 -m venv --system-site-packages .venv && . .venv/bin/activate  || exit 1
    pip3 install --upgrade pip  || exit 1
    echo
    echo "Installing xOpera"
    pip3 install --ignore-installed "opera[openstack]==$OPERA_VERSION" || exit 1

    echo
    echo "Switched to python interpreter from $(command -v python3)"

  else
    echo
    echo "Abort."
  fi

fi
echo
echo "Using python interpreter from $(command -v python3)"

# check git
GIT_INSTALLED=$(command -v git)
if [ -z "$GIT_INSTALLED" ]; then
  echo
  echo
  read -rp "Git is not installed. Do you wish to update and install git? [Y/n] " yngp
  if [ "$yngp" != "${yngp#[Yy]}" ]; then
    echo
    echo "Installing git"

    sudo apt update
    sudo apt install -y git  || exit 1

  else
    echo
    echo "Abort."
  fi
fi

# Install SODALITE iac modules
if [[ "$IAC_MODULES_CURRENT_VERSION" != *"$IAC_MODULES_VERSION"* ]]; then
  echo
  echo "Installing SODALITE iac modules (Version $IAC_MODULES_VERSION)"

  rm -r -f openstack/modules/
  git config --global advice.detachedHead "false" &&
  git clone -b "$IAC_MODULES_VERSION" https://github.com/SODALITE-EU/iac-modules.git openstack/modules &&
  git config --global advice.detachedHead "true"
fi

# copy library
echo
echo "Copying iac-platform-stack library"
rm -rf openstack/library/
cp -r library/ openstack/library/

echo
echo "Installing required Ansible roles"
ansible-galaxy install -r requirements.yml --force

CURRENT_USER=$(whoami)
export CURRENT_USER

echo
echo
echo "Running installation script as" "$CURRENT_USER"

echo
echo
echo "These are basic minimal inputs. If more advanced inputs are required please edit /openstack/input.yaml file manually."
echo
read -rp "Please enter email for SODALITE certificate: " EMAIL_INPUT
export SODALITE_EMAIL=$EMAIL_INPUT

echo
read -rp "Please enter Key pair name, to be assigned to sodalite-demo VM: " KEY_NAME_INPUT
export ssh_key_name=$KEY_NAME_INPUT

echo
read -rp "Please enter username for SODALITE blueprint database: " USERNAME_INPUT
export SODALITE_DB_USERNAME=$USERNAME_INPUT

echo
read -rp "Please enter password for SODALITE blueprint database: " PASSWORD_INPUT
export SODALITE_DB_PASSWORD=$PASSWORD_INPUT

echo
read -rp "Please enter token for SODALITE Gitlab repository: " TOKEN_INPUT
export SODALITE_GIT_TOKEN=$TOKEN_INPUT

echo
read -rp "Please enter token for Vault: " VAULT_TOKEN_INPUT
export VAULT_TOKEN=$VAULT_TOKEN_INPUT

echo
read -rp "Please enter admin password for Keycloak: " KEYCLOAK_ADMIN_PASSWORD_INPUT
export KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD_INPUT

echo
read -rp "Please enter client secret for Keycloak: " KEYCLOAK_CLIENT_SECRET_INPUT
export KEYCLOAK_CLIENT_SECRET=$KEYCLOAK_CLIENT_SECRET_INPUT

echo
read -rp "Please enter admin password for Knowledge Base: " KB_PASSWORD_INPUT
export KB_PASSWORD=$KB_PASSWORD_INPUT
# prepare inputs
envsubst <./openstack/input.yaml.tmpl >./openstack/input.yaml || exit 1

echo
echo "Checking TLS key and certificate..."
FILE_KEY=openstack/modules/docker/artifacts/ca.key
FILE_KEY2=openstack/modules/misc/tls/artifacts/ca.key
if [ -f "$FILE_KEY" ] && [ -f "$FILE_KEY2" ]; then
  echo "TLS key file already exists."
else
  echo "TLS key does not exist. Generating..."
  openssl genrsa -out $FILE_KEY 4096  || exit 1
  cp $FILE_KEY $FILE_KEY2  || exit 1
fi
FILE_CRT=openstack/modules/docker/artifacts/ca.crt
FILE_CRT2=openstack/modules/misc/tls/artifacts/ca.crt
if [ -f "$FILE_CRT" ] && [ -f "$FILE_CRT2" ]; then
  echo "TLS certificate file already exists."
else
  echo "TLS certificate does not exist. Generating..."
  openssl req -new -x509 -key $FILE_KEY -out $FILE_CRT -subj "/C=SI/O=XLAB/CN=$SODALITE_EMAIL" 2>/dev/null
  cp $FILE_CRT $FILE_CRT2  || exit 1
fi

unset CURRENT_USER
unset SODALITE_GIT_TOKEN
unset SODALITE_DB_USERNAME
unset SODALITE_DB_PASSWORD
unset SODALITE_EMAIL
unset KEYCLOAK_ADMIN_PASSWORD
unset VAULT_TOKEN
unset KEYCLOAK_CLIENT_SECRET
unset KB_PASSWORD
unset ssh_key_name

echo
echo

# shellcheck disable=SC1090
# source openrcfile
if [ -f "$OPENRC_PATH" ]; then
  echo "Exporting openstack environment variables..."
  . "$OPENRC_PATH"
  echo
  echo "Testing Openstack connection..."
  if [ -z "$(openstack server list)" ]; then
    exit 1
  else
    echo "Successfully connected to Openstack"
  fi

else
  echo "Missing openrc file on $OPENRC_PATH"
  exit 1
fi

# sudo is needed to ensure ansible will get user's password
echo
sudo echo "MODE: $MODE"


if [[ $MODE == "deploy" ]]; then
  echo "Deploying with opera..."

  if [[ $RESUME == "resume" ]]; then

    cd openstack || exit 1
    opera deploy -i input.yaml service.yaml --resume

  else

    cd openstack || exit 1
    rm -rf .opera
    opera deploy -i input.yaml service.yaml

  fi

elif [[ $MODE == "undeploy" ]]; then
  echo "Undeploying with opera..."

  cd openstack || exit 1
  opera undeploy

else
  echo "Wrong mode"

fi
