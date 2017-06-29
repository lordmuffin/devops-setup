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
    tr -d '\n')
  softwareupdate -i "$PROD" --verbose
}

show_ascii_logo() {
  echo "

                   uuuuuuu
               uu$$$$$$$$$$$uu
            uu$$$$$$$$$$$$$$$$$uu
           u$$$$$$$$$$$$$$$$$$$$$u
          u$$$$$$$$$$$$$$$$$$$$$$$u
         u$$$$$$$$$$$$$$$$$$$$$$$$$u
         u$$$$$$$$$$$$$$$$$$$$$$$$$u
         u$$$$$$"   "$$$"   "$$$$$$u
         "$$$$"      u$u       $$$$"
          $$$u       u$u       u$$$
          $$$u      u$$$u      u$$$
           "$$$$uu$$$   $$$uu$$$$"
            "$$$$$$$"   "$$$$$$$"
              u$$$$$$$u$$$$$$$u
               u$"$"$"$"$"$"$u
    uuu        $$u$ $ $ $ $u$$       uuu
   u$$$$        $$$$$u$u$u$$$       u$$$$
    $$$$$uu      "$$$$$$$$$"     uu$$$$$$
  u$$$$$$$$$$$uu    """""    uuuu$$$$$$$$$$
  $$$$"""$$$$$$$$$$uuu   uu$$$$$$$$$"""$$$"
   """      ""$$$$$$$$$$$uu ""$"""
             uuuu ""$$$$$$$$$$uuu
    u$$$uuu$$$$$$$$$uu ""$$$$$$$$$$$uuu$$$
    $$$$$$$$$$""""           ""$$$$$$$$$$$"
     "$$$$$"                      ""$$$$""
       $$$"                         $$$$"

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

verifyFreeDiskSpace() {

  # 50MB is the minimum space needed (45MB install (includes web admin bootstrap/jquery libraries etc) + 5MB one day of logs.)
  # - Fourdee: Local ensures the variable is only created, and accessible within this function/void. Generally considered a "good" coding practice for non-global variables.
  echo "::: Verifying free disk space..."
  local required_free_kilobytes=51200
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    echo "::: Unknown free disk space!"
    echo "::: We were unable to determine available free disk space on this system."
    echo "::: You may override this check and force the installation, however, it is not recommended"
    echo "::: To do so, pass the argument '--i_do_not_follow_recommendations' to the install script"
    echo "::: eg. curl -L https://install.pi-hole.net | bash /dev/stdin --i_do_not_follow_recommendations"
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    echo "::: Insufficient Disk Space!"
    echo "::: Your system appears to be low on disk space. Pi-hole recommends a minimum of $required_free_kilobytes KiloBytes."
    echo "::: You only have ${existing_free_kilobytes} KiloBytes free."
    echo "::: If this is a new install you may need to expand your disk."
    echo "::: Try running 'sudo raspi-config', and choose the 'expand file system option'"
    echo "::: After rebooting, run this installation again. (curl -L https://install.pi-hole.net | bash)"

    echo "Insufficient free space, exiting..."
    exit 1
  fi
}

displayFinalMessage() {

  if [[ ${#1} -gt 0 ]] ; then
    pwstring="$1"
  elif [[ $(grep 'WEBPASSWORD' -c /etc/pihole/setupVars.conf) -gt 0 ]]; then
    pwstring="unchanged"
  else
    pwstring="NOT SET"
  fi

   if [[ ${INSTALL_WEB} == true ]]; then
       additional="View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin

Your Admin Webpage login password is ${pwstring}"
   fi

  # Final completion message to user
  whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

IPv4:	${IPV4_ADDRESS%/*}
IPv6:	${IPV6_ADDRESS:-"Not Configured"}

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole.

${additional}" ${r} ${c}
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

  # Check for supported distribution
  distro_check

  # Check arguments for the undocumented flags
  for var in "$@"; do
    case "$var" in
      "--reconfigure"  ) reconfigure=true;;
      "--i_do_not_follow_recommendations"   ) skipSpaceCheck=false;;
      "--unattended"     ) runUnattended=true;;
    esac
  done

  if [[ -f ${setupVars} ]]; then
    if [[ "${runUnattended}" == true ]]; then
      echo "::: --unattended passed to install script, no whiptail dialogs will be displayed"
      useUpdateVars=true
    else
      update_dialogs
    fi
  fi

  # Start the installer
  # Verify there is enough disk space for the install
  if [[ "${skipSpaceCheck}" == true ]]; then
    echo "::: --i_do_not_follow_recommendations passed to script, skipping free disk space verification!"
  else
    verifyFreeDiskSpace
  fi

    # Clone/Update the repos
    clone_or_update_repos
    install_xcode | tee ${tmpLog}
    ansible-playbook main.yml -i inventory -K | tee ${tmpLog}


  echo "::: done."

  if [[ "${useUpdateVars}" == false ]]; then
      displayFinalMessage "${pw}"
  fi

  echo ":::"
  if [[ "${useUpdateVars}" == false ]]; then
    echo "::: Installation Complete! Configure your devices to use the Pi-hole as their DNS server using:"
    echo ":::     ${IPV4_ADDRESS%/*}"
    echo ":::     ${IPV6_ADDRESS}"
    echo ":::"
    echo "::: If you set a new IP address, you should restart the Pi."
    if [[ ${INSTALL_WEB} == true ]]; then
      echo "::: View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin"
    fi
  else
    echo "::: Update complete!"
  fi

  if [[ ${INSTALL_WEB} == true ]]; then
    if (( ${#pw} > 0 )) ; then
      echo ":::"
      echo "::: Note: As security measure a password has been installed for your web interface"
      echo "::: The currently set password is"
      echo ":::                                ${pw}"
      echo ":::"
      echo "::: You can always change it using"
      echo ":::                                pihole -a -p"
    fi
  fi

  echo ":::"
  echo "::: The install log is located at: /etc/pihole/install.log"
}

if [[ "${PH_TEST}" != true ]] ; then
  main "$@"
fi
