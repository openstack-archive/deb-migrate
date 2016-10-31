#!/bin/sh

set -e
set -x

MYTEMP_DIR=`mktemp -d`
ME=`whoami`

MYSQL_VERSION=`/usr/sbin/mysqld --version 2>/dev/null | grep Ver | awk '{print $3}' | cut -d- -f1`
MYSQL_VERSION_MAJ=`echo $MYSQL_VERSION | cut -d. -f1`
MYSQL_VERSION_MID=`echo $MYSQL_VERSION | cut -d. -f2`
MYSQL_VERSION_MIN=`echo $MYSQL_VERSION | cut -d. -f3`

if [ "${MYSQL_VERSION_MAJ}" -le 5 ] && [ "${MYSQL_VERSION_MID}" -lt 7 ] ; then
	MYSQL_INSTALL_DB_OPT="--force --skip-name-resolve" 
else
	MYSQL_INSTALL_DB_OPT="--basedir=/usr"
fi

# --force is needed because buildd's can't resolve their own hostnames to ips
echo "===> Preparing MySQL temp folder"
mysql_install_db --no-defaults --datadir=${MYTEMP_DIR} ${MYSQL_INSTALL_DB_OPT} --user=${ME}
chown -R ${ME} ${MYTEMP_DIR}
echo "===> Starting MySQL"
/usr/sbin/mysqld --no-defaults --skip-grant-tables --user=${ME} --socket=${MYTEMP_DIR}/mysql.sock --datadir=${MYTEMP_DIR} --skip-networking &

echo "===> Sleeping 3 seconds after starting MySQL"
sleep 3

# This sets the path of the MySQL socket for any libmysql-client users
export MYSQL_UNIX_PORT=${MYTEMP_DIR}/mysql.sock

echo "===> Attempting to connect"
echo -n "pinging mysqld: "
attempts=0
while ! /usr/bin/mysqladmin --socket=${MYTEMP_DIR}/mysql.sock ping ; do
	sleep 3
	attempts=$((attempts+1))
	if [ ${attempts} -gt 10 ] ; then
		exit 1
	fi
done

echo "===> Creating the db"
/usr/bin/mysql --socket=${MYTEMP_DIR}/mysql.sock --execute="CREATE DATABASE openstack_citest"

echo "===> Doing the unit tests"
# We set `pwd`/debian/bin in the path to have
# our "migrate" binary accessible
rm -rf .testrepository
testr init
TEMP_REZ=`mktemp -t`
PATH=$PATH:`pwd`/debian/bin PYTHONPATH=. testr run --subunit | tee $TEMP_REZ | subunit2pyunit || true
cat $TEMP_REZ | subunit-filter -s --no-passthrough | subunit-stats || true
rm -f $TEMP_REZ
testr slowest

echo "===> Shutting down MySQL"
/usr/bin/mysqladmin --socket=${MYTEMP_DIR}/mysql.sock shutdown
echo "===> Removing temp folder"
rm -rf ${MYTEMP_DIR} 

exit 0
