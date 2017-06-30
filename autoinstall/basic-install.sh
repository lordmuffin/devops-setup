#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Installs Pi-hole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.



# pi-hole.net/donate
#
# Install with this command (from your Pi):
#
# curl -L install.pi-hole.net | bash

set -e
######## VARIABLES #########
tmpLog=/tmp/pihole-install.log
instalLogLoc=/etc/pihole/install.log
setupVars=/etc/pihole/setupVars.conf
lighttpdConfig=/etc/lighttpd/lighttpd.conf

webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
PI_HOLE_LOCAL_REPO="/etc/.pihole"
PI_HOLE_FILES=(chronometer list piholeDebug piholeLogFlush setupLCD update version gravity uninstall webpage)
PI_HOLE_INSTALL_DIR="/opt/pihole"
useUpdateVars=false

IPV4_ADDRESS=""
IPV6_ADDRESS=""
QUERY_LOGGING=true
INSTALL_WEB=true


# Find the rows and columns will default to 80x24 is it can not be detected
screen_size=$(stty size 2>/dev/null || echo 24 80)
rows=$(echo "${screen_size}" | awk '{print $1}')
columns=$(echo "${screen_size}" | awk '{print $2}')

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))
# Unless the screen is tiny
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))

######## Undocumented Flags. Shhh ########
skipSpaceCheck=false
reconfigure=false
runUnattended=false

install_xcode() {
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress;
  PROD=$(softwareupdate -l) |
    grep "\*.*Command Line" |
    head -n 1 | awk -F"*" '{print $2}' |
    sed -e 's/^ *//' |
    tr -d '\n'
  softwareupdate -i "$PROD" --verbose
}

show_ascii_logo() {
  echo "
  \
  \\
  \\\
  Andrew's Script.
  ///
  //
  /
"
}


is_repo() {
  # Use git to check if directory is currently under VCS, return the value 128
  # if directory is not a repo. Return 1 if directory does not exist.
  local directory="${1}"
  local curdir
  local rc

  curdir="${PWD}"
  if [[ -d "${directory}" ]]; then
    # git -C is not used here to support git versions older than 1.8.4
    cd "${directory}"
    git status --short &> /dev/null || rc=$?
  else
    # non-zero return code if directory does not exist
    rc=1
  fi
  cd "${curdir}"
  return "${rc:-0}"
}

make_repo() {
  local directory="${1}"
  local remoteRepo="${2}"

  echo -n ":::    Cloning ${remoteRepo} into ${directory}..."
  # Clean out the directory if it exists for git to clone into
  if [[ -d "${directory}" ]]; then
    rm -rf "${directory}"
  fi
  git clone -q --depth 1 "${remoteRepo}" "${directory}" &> /dev/null || return $?
  echo " done!"
  return 0
}

update_repo() {
  local directory="${1}"
  local curdir

  curdir="${PWD}"
  cd "${directory}" &> /dev/null || return 1
  # Pull the latest commits
  echo -n ":::    Updating repo in ${1}..."
  git stash --all --quiet &> /dev/null || true # Okay for stash failure
  git clean --force -d || true # Okay for already clean directory
  git pull --quiet &> /dev/null || return $?
  echo " done!"
  cd "${curdir}" &> /dev/null || return 1
  return 0
}

getGitFiles() {
  # Setup git repos for directory and repository passed
  # as arguments 1 and 2
  local directory="${1}"
  local remoteRepo="${2}"
  echo ":::"
  echo "::: Checking for existing repository..."
  if is_repo "${directory}"; then
    update_repo "${directory}" || { echo "*** Error: Could not update local repository. Contact support."; exit 1; }
    echo " done!"
  else
    make_repo "${directory}" "${remoteRepo}" || { echo "Unable to clone repository, please contact support"; exit 1; }
    echo " done!"
  fi
  return 0
}

resetRepo() {
  local directory="${1}"

  cd "${directory}" &> /dev/null || return 1
  echo -n ":::    Resetting repo in ${1}..."
  git reset --hard &> /dev/null || return $?
  echo " done!"
  return 0
}

welcomeDialogs() {
  # Display the welcome dialog
  whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "\n\nThis installer will transform your device into a network-wide ad blocker!" ${r} ${c}

  # Support for a part-time dev
  whiptail --msgbox --backtitle "Plea" --title "Free and open source" "\n\nThe Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" ${r} ${c}

  # Explain the need for a static address
  whiptail --msgbox --backtitle "Initiating network interface" --title "Static IP Needed" "\n\nThe Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." ${r} ${c}
}


displayFinalMessage() {

  # Final completion message to user
  whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!"
}



main() {

  ######## FIRST CHECK ########
  # Must be root to install
  show_ascii_logo
  echo ":::"
  if [[ ${EUID} -eq 0 ]]; then
    echo "::: You are root."
  else
    echo "::: Script called with non-root privileges. The Pi-hole installs server packages and configures"
    echo "::: system networking, it requires elevated rights. Please check the contents of the script for"
    echo "::: any concerns with this requirement. Please be sure to download this script from a trusted source."
    echo ":::"
    echo "::: Detecting the presence of the sudo utility for continuation of this install..."

    if command -v sudo &> /dev/null; then
      echo "::: Utility sudo located."
      exec curl -sSL https://raw.githubusercontent.com/lordmuffin/devops-setup/master/automatedinstall/basic-install.sh | sudo bash "$@"
      exit $?
    else
      echo "::: sudo is needed for the Web interface to run pihole commands.  Please run this script as root and it will be automatically installed."
      exit 1
    fi
  fi

    # Clone/Update the repos
    clone_or_update_repos
    install_xcode | tee ${tmpLog}
    ansible-playbook main.yml -i inventory -K | tee ${tmpLog}


  echo "::: done."
  displayFinalMessage
}
main
