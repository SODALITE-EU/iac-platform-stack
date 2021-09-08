#!/usr/bin/env bash

######################
# Pinned versions

OPERA_VERSION="0.6.6"
IAC_MODULES_VERSION="3.4.1"

# UUID regex for validation of uuid inputs
UUID_pattern='^\{?[A-Z0-9a-z]{8}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{12}\}?$'

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
    . .venv/bin/activate || exit 1
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
    pip3 install --ignore-installed "openstacksdk==0.52.0" || exit 1
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

CURRENT_USER=$(whoami)
export CURRENT_USER

echo
echo
echo "Running installation script as" "$CURRENT_USER"

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
    echo "Openstack connection failed, check openrc_file on $OPENRC_PATH"
    exit 1
  else
    echo "Successfully connected to Openstack"
  fi

else
  echo "Missing openrc file on $OPENRC_PATH"
  exit 1
fi

# use openstack/input.yaml, if exists
INPUT_FILE=openstack/input.yaml
if [ -f "$INPUT_FILE" ]; then
  echo
  echo
  read -rp "Found existing file $INPUT_FILE, do you want to use it [Y/n] " yninput
  if [ "$yninput" != "${yninput#[Yy]}" ]; then

    echo "Using existing file with inputs"

    username=$(grep username "$INPUT_FILE" | cut -d ' ' -f2)
    email=$(grep email-address "$INPUT_FILE" | cut -d ' ' -f2)

    if [[ -z "$username" ]] || [[ -z "$email" ]]; then
      echo Input file $INPUT_FILE invalid.
      exit 1
    fi
    export OPERA_SSH_USER=$username
    export SODALITE_EMAIL=$email

    REUSE_INPUT_FILE=True
  fi
fi

if [[ -z "$REUSE_INPUT_FILE" ]]; then

  echo "Creating file with inputs..."

  echo
  echo
  echo "These are basic minimal inputs. If more advanced inputs are required please edit openstack/input.yaml file manually."

  # Openstack image selection
  echo
  mapfile -t images < <(openstack image list -f csv | grep active | cut -d ',' -f2 | tr -d \")
  echo "Select Openstack image for sodalite-demo VM:"

  select image in "${images[@]}"; do
    if [ -z "$image" ]; then
      echo "Invalid entry. Try again"
    else
      break
    fi
  done

  image_lower="${image,,}"
  if [[ "$image_lower" == *"ubuntu"* ]]; then
    username="ubuntu"
  elif [[ "$image_lower" == *"centos"* ]]; then
    username="centos"
  else
    read -rp "Please enter username for sodalite-demo VM ($image): " username
  fi

  # Openstack flavor selection
  echo
  mapfile -t flavors < <(openstack flavor list -f csv | tail -n +2 | cut -d ',' -f2 | tr -d \")
  echo "Select Openstack Flavor for sodalite-demo VM (m1.large recommended):"

  select flavor in "${flavors[@]}"; do
    if [ -z "$flavor" ]; then
      echo "Invalid entry. Try again"
    else
      break
    fi
  done

  # Openstack network selection
  echo
  mapfile -t networks < <(openstack network list -f csv | tail -n +2 | cut -d ',' -f2 | tr -d \")

  # if more then one network available
  if [ "${#networks[@]}" -gt 1 ]; then
    echo "Select Openstack Network to attach sodalite-demo VM to:"

    select network in "${networks[@]}"; do
      if [ -z "$network" ]; then
        echo "Invalid entry. Try again"
      else
        break
      fi
    done
  else
    network="${networks[0]}"
    echo "Openstack Network to attach sodalite-demo VM to: $network"
  fi

  # Openstack keypair selection
  echo
  mapfile -t keypairs < <(openstack keypair list -f csv | tail -n +2 | cut -d ',' -f1 | tr -d \")

  # if more then one keypair available
  if [ "${#keypairs[@]}" -gt 1 ]; then
    echo "Select Keypair to be used when creating sodalite-demo VM:"

    select keypair in "${keypairs[@]}"; do
      if [ -z "$keypair" ]; then
        echo "Invalid entry. Try again"
      else
        break
      fi
    done
  else
    keypair="${keypairs[0]}"
    echo "Keypair to be used when creating sodalite-demo VM: $keypair"
  fi

  echo
  echo "######## sodalite-demo VM ########"
  echo Image: \""$image"\"
  echo Username: "$username"
  echo Flavor: "$flavor"
  echo Network: "$network"
  echo Keypair: "$keypair"
  echo "##################################"

  export VM_IMAGE_NAME=$image
  export VM_USERNAME=$username
  export VM_FLAVOR=$flavor
  export OS_NETWORK=$network
  export VM_SSH_KEY_NAME=$keypair

  # for xOpera
  export OPERA_SSH_USER=$username

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


  # prepare inputs
  envsubst <./openstack/input.yaml.tmpl >./openstack/input.yaml || exit 1

  unset CURRENT_USER
  unset SODALITE_GIT_TOKEN
  unset SODALITE_DB_USERNAME
  unset SODALITE_DB_PASSWORD
  unset KEYCLOAK_ADMIN_PASSWORD
  unset VAULT_TOKEN
  unset KEYCLOAK_CLIENT_SECRET
  unset KB_PASSWORD
  unset VM_IMAGE_NAME
  unset VM_USERNAME
  unset VM_FLAVOR
  unset OS_NETWORK
  unset VM_SSH_KEY_NAME
  unset XOPERA_AUTH_API_KEY

fi


echo
echo "Checking TLS key and certificate..."
FILE_KEY=openstack/modules/docker/artifacts/ca.key
FILE_KEY2=openstack/modules/misc/tls/artifacts/ca.key
if [ -f "$FILE_KEY" ] && [ -f "$FILE_KEY2" ]; then
  echo "TLS key file already exists."
else
  echo "TLS key does not exist. Generating..."
  openssl genrsa -out $FILE_KEY 4096 || exit 1
  cp $FILE_KEY $FILE_KEY2 || exit 1
fi
FILE_CRT=openstack/modules/docker/artifacts/ca.crt
FILE_CRT2=openstack/modules/misc/tls/artifacts/ca.crt
if [ -f "$FILE_CRT" ] && [ -f "$FILE_CRT2" ]; then
  echo "TLS certificate file already exists."
else
  echo "TLS certificate does not exist. Generating..."
  openssl req -new -x509 -key $FILE_KEY -out $FILE_CRT -subj "/C=SI/O=XLAB/CN=$SODALITE_EMAIL" 2>/dev/null
  cp $FILE_CRT $FILE_CRT2 || exit 1
fi

unset SODALITE_EMAIL

echo
echo

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
