#!/usr/bin/env bash

######################
# Pinned versions

OPERA_VERSION="0.6.6"
IAC_MODULES_VERSION="3.6.0"

# UUID regex for validation of uuid inputs
UUID_pattern='^\{?[A-Z0-9a-z]{8}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{12}\}?$'

########################

# Usage: ./deploy_local.sh deploy [--resume]
# Usage: ./deploy_local.sh undeploy

# argument parser
if [ $# -gt 2 ] || [ $# -lt 1 ] ||
  [[ "$1" != "deploy" && "$1" != "undeploy" ]] ||
  [[ "$1" == "deploy" && "$2" != "--resume" && "$2" != "--clean-state" && $# -eq 2 ]] ||
  [[ "$1" == "undeploy" && $# -gt 1 ]]; then
  echo "Usage: $0 deploy [--resume]"
  echo "Usage: $0 undeploy"
  exit 1
fi

MODE=$1
RESUME=${2:-"--clean-state"}
# remove prefix --
RESUME=${RESUME#"--"}

# use .venv, if exists
if [ -f .venv/bin/activate ]; then
  echo
  echo
  read -rp "Python virtual environment found in .venv dir. Do you want to activate it? [Y/n] " ynvenv
  if [ "$ynvenv" != "${ynvenv#[Yy]}" ]; then

    echo "Activating .venv"
    . .venv/bin/activate || exit 1
  else
    echo "Abort."
  fi

  echo "Switched to python interpreter from $(command -v python3)"

fi

# check current opera and modules version
OPERA_CURRENT_VERSION=$(pip3 show opera 2>/dev/null | grep Version | awk '{print $2}')
IAC_MODULES_CURRENT_VERSION=$(cd docker-local/modules 2>/dev/null && git tag --points-at HEAD)

# check prerequisites
APT_PKG_MISSING=$(if python3 apt_pkg_test.py 2>/dev/null; then echo false; else echo true; fi)
OPERA_NOT_INSTALLED=$(if [ -z "$(pip3 show opera 2>/dev/null)" ]; then echo true; else echo false; fi)
OPERA_WRONG_VERSION=$(if [ "$OPERA_CURRENT_VERSION" != "$OPERA_VERSION" ]; then echo true; else echo false; fi)

# ansible version
ANSIBLE_VERSION=$(ansible --version 2>/dev/null | head -n 1 | awk '{print $2}')
ANSIBLE_WRONG_VERSION=$(if [[ $ANSIBLE_VERSION == 2.10* ]] || [[ -z $ANSIBLE_VERSION ]]; then echo false; else echo true; fi)

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
    sudo apt install -y python3 python3-pip || exit 1

  else
    echo
    echo "Abort."
  fi
fi

# check if new venv must be created
if $APT_PKG_MISSING || $OPERA_NOT_INSTALLED || $OPERA_WRONG_VERSION || $ANSIBLE_WRONG_VERSION; then
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
    sudo apt install -y python3-venv python3-wheel python-wheel-common python3-apt || exit 1

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
    python3 -m venv --system-site-packages .venv && . .venv/bin/activate || exit 1
    pip3 install --upgrade pip || exit 1
    echo
    echo "Installing xOpera"
    pip3 install --ignore-installed "opera==$OPERA_VERSION" || exit 1

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
    sudo apt install -y git || exit 1

  else
    echo
    echo "Abort."
  fi
fi

# Install SODALITE iac modules
if [[ "$IAC_MODULES_CURRENT_VERSION" != *"$IAC_MODULES_VERSION"* ]]; then
  echo
  echo "Installing SODALITE iac modules (Version $IAC_MODULES_VERSION)"

  rm -r -f docker-local/modules/
  git config --global advice.detachedHead "false" &&
    git clone -b "$IAC_MODULES_VERSION" https://github.com/SODALITE-EU/iac-modules.git docker-local/modules &&
    git config --global advice.detachedHead "true"
fi

# copy library
echo
echo "Copying iac-platform-stack library"
rm -rf docker-local/library/
cp -r library/ docker-local/library/

echo
echo "Installing required Ansible roles"

mapfile -t existing_roles < <(ansible-galaxy role list 2>/dev/null)
version_exist() {
  desired_role=$1
  desired_version=$2
  for existin_role in "${existing_roles[@]}"; do
    if [[ "$existin_role" == *"$desired_role"* ]]; then
      if [[ "$existin_role" == *"$desired_version"* ]]; then
        return 0
      else
        return 1
      fi

    fi
  done
  return 1
}

mapfile -t requirements < <(grep src requirements.yml -A1 | paste -d" |" - -)

for requirement in "${requirements[@]}"; do
  # shellcheck disable=SC2086
  package="$(echo $requirement | cut -d ' ' -f3)"
  # shellcheck disable=SC2086
  version="$(echo $requirement | cut -d ' ' -f5)"
  if version_exist "$package" "$version"; then
    echo "Ansible role $package,$version already installed"
  else
    ansible-galaxy install "$package,$version" --force
  fi
done

# use docker-local/input.yaml, if exists
INPUT_FILE=docker-local/input.yaml
if [ -f "$INPUT_FILE" ]; then
  echo
  echo
  read -rp "Found existing file $INPUT_FILE, do you want to use it [Y/n] " yninput
  if [ "$yninput" != "${yninput#[Yy]}" ]; then

    echo "Using existing file with inputs"

    email=$(grep email-address "$INPUT_FILE" | cut -d ' ' -f2)

    if [[ -z "$email" ]]; then
      echo Input file $INPUT_FILE invalid.
      exit 1
    fi
    export SODALITE_EMAIL=$email

    REUSE_INPUT_FILE=True
  fi
fi

if [[ -z "$REUSE_INPUT_FILE" ]]; then

  CURRENT_USER=$(whoami)
  export CURRENT_USER

  echo
  echo
  echo "Running installation script as" "$CURRENT_USER"

  IP_ADDRESS=$(ip route get 1 | awk '{print $(NF-2);exit}')
  export IP_ADDRESS

  echo
  echo
  echo "Running installation script on ip address:" "$IP_ADDRESS"

  echo
  echo
  echo "These are basic minimal inputs. If more advanced inputs are required please edit /docker-local/input.yaml file manually."
  echo
  read -rp "Please enter email for SODALITE certificate: " EMAIL_INPUT
  export SODALITE_EMAIL=$EMAIL_INPUT

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
  read -rp "Please enter token (UUID) for Vault: " VAULT_TOKEN_INPUT
  while [[ ! "$VAULT_TOKEN_INPUT" =~ $UUID_pattern ]]; do
    read -rp "\"$VAULT_TOKEN_INPUT\" is not UUID. Please enter a valid UUID: " VAULT_TOKEN_INPUT
  done
  export VAULT_TOKEN=$VAULT_TOKEN_INPUT

  echo
  read -rp "Please enter admin password for Keycloak: " KEYCLOAK_ADMIN_PASSWORD_INPUT
  export KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD_INPUT

  echo
  read -rp "Please enter client secret (UUID) for Keycloak: " KEYCLOAK_CLIENT_SECRET_INPUT
  while [[ ! "$KEYCLOAK_CLIENT_SECRET_INPUT" =~ $UUID_pattern ]]; do
    read -rp "\"$KEYCLOAK_CLIENT_SECRET_INPUT\" is not UUID. Please enter a valid UUID: " KEYCLOAK_CLIENT_SECRET_INPUT
  done
  export KEYCLOAK_CLIENT_SECRET=$KEYCLOAK_CLIENT_SECRET_INPUT

  echo
  read -rp "Please enter arbitrary key to override xOpera's authorization: " XOPERA_AUTH_API_KEY_INPUT
  export XOPERA_AUTH_API_KEY=$XOPERA_AUTH_API_KEY_INPUT

  echo
  read -rp "Please enter admin password for Knowledge Base: " KB_PASSWORD_INPUT
  export KB_PASSWORD=$KB_PASSWORD_INPUT

  echo
  read -rp "Please enter admin password for Grafana: " GF_ADMIN_PW_INPUT
  export GF_ADMIN_PW=$GF_ADMIN_PW_INPUT

  echo
  read -rp "Please enter OIDC username that will be used as the admin for NiFi: " NIFI_OIDC_ADMIN_INPUT
  export NIFI_OIDC_ADMIN=$NIFI_OIDC_ADMIN_INPUT

  echo
  read -rp "[Optonal] Please enter the directory of GridFTP trusted certificates: " NIFI_GRIDFTP_CERTIFICATES_LOCATION_INPUT
  DEFAULT_GRIDFTP_CERTDIR=$(pwd)/docker-local/modules/gridftp-certdir/
  [ -z "$NIFI_GRIDFTP_CERTIFICATES_LOCATION_INPUT" ] && mkdir -p "$DEFAULT_GRIDFTP_CERTDIR"
  export NIFI_GRIDFTP_CERTIFICATES_LOCATION=${NIFI_GRIDFTP_CERTIFICATES_LOCATION_INPUT:-$DEFAULT_GRIDFTP_CERTDIR}

  export NIFI_CA_TOKEN=$(openssl rand -hex 20)
  export NIFI_SENSITIVE_PROPS_KEY=$(openssl rand -hex 20)

  # prepare inputs
  envsubst <./docker-local/input.yaml.tmpl >./docker-local/input.yaml || exit 1

  unset CURRENT_USER
  unset SODALITE_GIT_TOKEN
  unset SODALITE_DB_USERNAME
  unset SODALITE_DB_PASSWORD
  unset KEYCLOAK_ADMIN_PASSWORD
  unset VAULT_TOKEN
  unset KEYCLOAK_CLIENT_SECRET
  unset IP_ADDRESS
  unset KB_PASSWORD
  unset XOPERA_AUTH_API_KEY

  unset NIFI_OIDC_ADMIN
  unset NIFI_GRIDFTP_CERTIFICATES_LOCATION
  unset NIFI_CA_TOKEN
  unset NIFI_SENSITIVE_PROPS_KEY

fi

echo
echo "Checking TLS key and certificate..."
FILE_KEY=docker-local/modules/docker/artifacts/ca.key
FILE_KEY2=docker-local/modules/misc/tls/artifacts/ca.key
if [ -f "$FILE_KEY" ] && [ -f "$FILE_KEY2" ]; then
  echo "TLS key file already exists."
else
  echo "TLS key does not exist. Generating..."
  openssl genrsa -out $FILE_KEY 4096 || exit 1
  cp $FILE_KEY $FILE_KEY2 || exit 1
fi
FILE_CRT=docker-local/modules/docker/artifacts/ca.crt
FILE_CRT2=docker-local/modules/misc/tls/artifacts/ca.crt
if [ -f "$FILE_CRT" ] && [ -f "$FILE_CRT2" ]; then
  echo "TLS certificate file already exists."
else
  echo "TLS certificate does not exist. Generating..."
  openssl req -new -x509 -key $FILE_KEY -out $FILE_CRT -subj "/C=SI/O=XLAB/CN=$SODALITE_EMAIL" 2>/dev/null
  cp $FILE_CRT $FILE_CRT2 || exit 1
fi

unset SODALITE_EMAIL

# sudo is needed to ensure ansible will get user's password
echo
sudo echo "MODE: $MODE"

if [[ $MODE == "deploy" ]]; then
  echo "Deploying with opera..."

  if [[ $RESUME == "resume" ]]; then

    cd docker-local || exit 1
    opera deploy -i input.yaml service.yaml --resume

  else

    cd docker-local || exit 1
    rm -rf .opera
    opera deploy -i input.yaml service.yaml

  fi

elif [[ $MODE == "undeploy" ]]; then
  echo "Undeploying with opera..."

  cd docker-local || exit 1
  opera undeploy

else
  echo "Wrong mode"

fi
