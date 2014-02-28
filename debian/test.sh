#!/bin/sh

set -e

MYTEMP_DIR=`mktemp -d`
ME=`whoami`

# --force is needed because buildd's can't resolve their own hostnames to ips
echo "===> Preparing MySQL temp folder"
mysql_install_db --no-defaults --datadir=${MYTEMP_DIR} --force --skip-name-resolve --user=${ME}
echo "===> Starting MySQL"
/usr/sbin/mysqld --no-defaults --skip-grant --user=openstack_citest --socket=${MYTEMP_DIR}/mysql.sock --datadir=${MYTEMP_DIR} --skip-networking &

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

PYTHONPATH=. python setup.py testr --slowest || true

echo "===> Shutting down MySQL"
/usr/bin/mysqladmin --socket=${MYTEMP_DIR}/mysql.sock shutdown
echo "===> Removing temp folder"
rm -rf ${MYTEMP_DIR} 

exit 0
