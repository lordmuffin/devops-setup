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

remoteRepo="https://github.com/lordmuffin/devops-setup.git"
webInterfaceDir="/var/www/html/admin"
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
  :::
  Andrew's Script.
  :::
"
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
      exec curl -sSL https://raw.githubusercontent.com/lordmuffin/devops-setup/master/autoinstall/basic-install.sh | sudo bash "$@"
      exit $?
    else
      echo "::: sudo is needed for the Web interface to run pihole commands.  Please run this script as root and it will be automatically installed."
      exit 1
    fi
  fi

    # Clone/Update the repos

    install_xcode | tee ${tmpLog}
    ansible-playbook main.yml -i inventory -K | tee ${tmpLog}


  echo "::: done."
}
main
