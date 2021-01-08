#!/usr/bin/env bash

######################
# Pinned versions

OPERA_VERSION="0.6.2"
IAC_MODULES_VERSION="3.0.2"

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
    . .venv/bin/activate
  else
    echo "Abort."
  fi

  echo "Using python interpreter from $(command -v python3)"

fi

# check current opera and modules version
OPERA_CURRENT_VERSION=$(pip3 show opera 2>/dev/null | grep Version | awk '{print $2}')
IAC_MODULES_CURRENT_VERSION=$(cd docker-local/modules 2>/dev/null && git tag --points-at HEAD)

# check prerequisites
APT_PKG_MISSING=$(if python3 apt_pkg_test.py 2>/dev/null; then echo false; else echo true; fi)
OPERA_NOT_INSTALLED=$(if [ -z "$(pip3 show opera 2>/dev/null)" ]; then echo true; else echo false; fi)
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
    sudo apt install -y python3 python3-pip

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
    sudo apt install -y python3-venv python3-wheel python-wheel-common python3-apt


    if $ANSIBLE_WRONG_VERSION; then
      echo
      echo "Removing ansible from apt and installing it with pip3"
      sudo apt remove -y ansible
      deactivate 2>/dev/null
      pip3 install --upgrade ansible

      # shellcheck disable=SC1090
      # reload path to ansible
      if [ -f ~/.bash_profile ]; then . ~/.bash_profile; else . ~/.profile; fi
      echo "Before using Ansible CLI for the first time, please reload path:"
      echo "source ~/.profile"
    fi

    echo
    echo "Creating new venv"
    sudo rm -rf .venv
    python3 -m venv --system-site-packages .venv && . .venv/bin/activate
    echo
    echo "Installing xOpera"
    pip3 install --ignore-installed "opera==$OPERA_VERSION"


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
  read -rp "git is not installed. Do you wish to update and install git? [Y/n] " yngp
  if [ "$yngp" != "${yngp#[Yy]}" ]; then
    echo
    echo "Installing git"

    sudo apt update
    sudo apt install -y git

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

echo
echo "Installing required Ansible roles"
ansible-galaxy install -r ./docker-local/requirements.yml --force

CURRENT_USER=$(whoami)
export CURRENT_USER

echo
echo
echo "Running installation script as" "$CURRENT_USER"

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

# prepare inputs
envsubst <./docker-local/input.yaml.tmpl >./docker-local/input.yaml

echo
echo "Checking TLS key and certificate..."
FILE_KEY=docker-local/modules/docker/artifacts/ca.key
FILE_KEY2=docker-local/modules/misc/tls/artifacts/ca.key
if [ -f "$FILE_KEY" ] && [ -f "$FILE_KEY2" ]; then
  echo "TLS key file already exists."
else
  echo "TLS key does not exist. Generating..."
  openssl genrsa -out $FILE_KEY 4096
  cp $FILE_KEY $FILE_KEY2
fi
FILE_CRT=docker-local/modules/docker/artifacts/ca.crt
FILE_CRT2=docker-local/modules/misc/tls/artifacts/ca.crt
if [ -f "$FILE_CRT" ] && [ -f "$FILE_CRT2" ]; then
  echo "TLS certificate file already exists."
else
  echo "TLS certificate does not exist. Generating..."
  openssl req -new -x509 -key $FILE_KEY -out $FILE_CRT -subj "/C=SI/O=XLAB/CN=$SODALITE_EMAIL" 2>/dev/null
  cp $FILE_CRT $FILE_CRT2
fi

unset CURRENT_USER
unset SODALITE_GIT_TOKEN
unset SODALITE_DB_USERNAME
unset SODALITE_DB_PASSWORD
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
