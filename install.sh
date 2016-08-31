#!/bin/bash
set -e

BREWPI_WEB=/var/www/html
BREWPI_SCRIPT=/home/brewpi
BREWPI_USER=brewpi
BREWPI_WEB_USER=www-data
TILT_REPO=https://github.com/supercow/brewpi-brewometer
TILT_BRANCH=legacy

function fail {
  >&2 echo Error: $1
  exit 1
}

if [ `id -u` != '0' ]; then
  fail "Script must be run as root.\nTry doing: sudo $0"
fi

# Update apt repos
apt-get update || fail "Failed to update apt repos"

# Install Brewometer dependencies
apt-get install -y bluez python-bluez python-scipy python-numpy libcap2-bin || fail "Failed to install dependencies"

# Enable Python access to bluetooth without root
setcap cap_net_raw+eip $(eval readlink -f `which python`) || fail "Failed to grant bluetooth access to python"

# Clone brewometer files into temp directory
cd /tmp
rm -f ${TILT_BRANCH}.zip
/usr/bin/wget ${TILT_REPO}/archive/${TILT_BRANCH}.zip || fail "Failed to download brewometer modifications"
/usr/bin/unzip -o ${TILT_BRANCH}.zip || fail "Failed to extract brewometer modifications (zip checksum: $(/usr/bin/md5sum ${TILT_BRANCH})"

# Create backups for brewpi
BACKUP_TIMESTAMP=$(/bin/date +%Y%m%d-%H%M)
/bin/tar -czvf ${HOME}/brewpi-web.${BACKUP_TIMESTAMP}.tgz ${BREWPI_WEB} || fail "Failed to backup web directory"
/bin/tar -czvf ${HOME}/brewpi-script.${BACKUP_TIMESTAMP}.tgz ${BREWPI_SCRIPT} || fail "Failed to backup script directory"

echo Backups created in ${HOME}

# Update brewpi script
{
  # kill all instances of the brewpi script
  for pid in $(ps -ef |grep 'python.*brewpi.py$' |awk '{print $2}'); do
    kill -9 $pid
  done

  #copy files and fix ownership
  /bin/cp -Rf brewpi-brewometer-${TILT_BRANCH}/brewpi-script/* ${BREWPI_SCRIPT}/

  #restart script
  sudo -u brewpi /usr/bin/python ${BREWPI_SCRIPT}/brewpi.py --checkstartuponly --dontrunfile ${BREWPI_SCRIPT}/brewpi.py 1>/dev/null 2>>${BREWPI_SCRIPT}/logs/stderr.txt; [ $? != 0 ] && python -u ${BREWPI_SCRIPT}/brewpi.py 1>${BREWPI_SCRIPT}/logs/stdout.txt 2>>${BREWPI_SCRIPT}/logs/stderr.txt &

} || {
  fail "Failure updating brewpi script"
}

# Update brewpi web
{
  /bin/cp -Rf brewpi-brewometer-${TILT_BRANCH}/brewpi-web/* ${BREWPI_WEB}/
  /usr/sbin/service apache2 restart
} || {
  fail "Failure updating brewpi web"
}

# Fix permissions
${BREWPI_SCRIPT}/utils/fixPermissions.sh || fail "Could not fix permissions. Your shit is broken."

echo "Succesfully (I think) installed Brewometer modifications. Please start a new beer in BrewPi, refresh your browser, and wait a few minutes."

