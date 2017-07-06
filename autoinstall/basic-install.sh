#!/bin/sh

# This script bootstraps a OSX laptop for development
# to a point where we can run Ansible on localhost. It:
#  1. Installs:
#    - xcode
#    - homebrew
#    - ansible (via brew)
#    - a few ansible galaxy playbooks (zsh, homebrew, cask etc)
#  2. Kicks off the ansible playbook:
#    - main.yml
#
# It begins by asking for your sudo password:

fancy_echo() {
  local fmt="$1"; shift

  # shellcheck disable=SC2059
  printf "\n$fmt\n" "$@"
}

fancy_echo "Boostrapping ..."

trap 'ret=$?; test $ret -ne 0 && printf "failed\n\n" >&2; exit $ret' EXIT

set -e

# Here we go.. ask for the administrator password upfront and run a
# keep-alive to update existing `sudo` time stamp until script has finished
# sudo -v
# while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Ensure Apple's command line tools are installed
if ! command -v cc >/dev/null; then
  fancy_echo "Installing xcode ..."
  xcode-select --install
else
  fancy_echo "Xcode already installed. Skipping."
fi

if ! command -v brew >/dev/null; then
  fancy_echo "Installing Homebrew..."
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" </dev/null
else
  fancy_echo "Updating Homebrew..."
  brew update
fi

# [Install Ansible](http://docs.ansible.com/intro_installation.html).
if ! command -v ansible >/dev/null; then
  fancy_echo "Installing Ansible ..."
  brew install ansible
else
  fancy_echo "Upgrade Ansible..."
  brew upgrade
fi

cd ~/
if [ -d "./.yadr" ]; then
  fancy_echo "YADR repo dir exists. Removing ..."
  rm -rf ./.yadr
fi
fancy_echo "YADR rake install..."
git clone https://github.com/skwp/dotfiles.git ~/.yadr
cd ~/.yadr
rake install

# Clone the repository to your local drive.
cd ~/
if [ -d "./Git" ]; then
  fancy_echo "Laptop repo dir exists. Removing ..."
  rm -rf ./Git
fi
git clone https://github.com/lordmuffin/devops-setup.git ~/Git/devops-setup
fancy_echo "Changing to laptop repo dir ..."
cd ~/Git/devops-setup

# # Run this from the same directory as this README file.
fancy_echo "Running ansible galaxy ..."
ansible-galaxy install -r requirements.yml

fancy_echo "Running ansible playbook ..."
ansible-playbook ~/Git/devops-setup/playbook.yml -i ~/Git/devops-setup/inventory --ask-sudo-pass

# Debug Command
# fancy_echo "DEBUG ::: Running ansible galaxy ..."
# ansible-galaxy install -r requirements.yml -vvvv
# fancy_echo "DEBUG ::: Running ansible playbook ..."
# ansible-playbook playbook.yml -i inventory --ask-sudo-pass -vvvv
