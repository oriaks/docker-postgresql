#!/bin/sh
#
#  Copyright (C) 2015 Michael Richard <michael.richard@oriaks.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#set -x

export DEBIAN_FRONTEND='noninteractive'
export TERM='linux'

_VERSION=`ls /usr/lib/postgresql/`
_POSTGRES="/usr/lib/postgresql/${_VERSION}/bin/postgres"
_INITDB="/usr/lib/postgresql/${_VERSION}/bin/initdb"

_install () {
  [ -f /usr/share/postgresql-common/pg_wrapper ] && return 1

  apt-get update -q
  apt-get install -y postgresql pwgen

#  _VERSION=`ls /usr/lib/postgresql/`

#  sed -ir -f- "/etc/postgresql/${_VERSION}/main/postgresql.conf" <<- EOF
#	s|^[[:space:]#]*\(listen_addresses[[:space:]]*\)=.*$|\1= '*'|;
#EOF

#  sed -ir -f- "/etc/postgresql/${_VERSION}/main/pg_hba.conf" <<- EOF
#	s|^[[:space:]]*#*[[:space:]]*\(local[[:space:]]*all[[:space:]]*all[[:space:]]*\)peer|\1md5|;
#	s|127.0.0.1/32|0.0.0.0/0|;
#EOF

  rm -rf /var/lib/postgresql/*

  return 0
}

_init () {
  if [ ! -f /var/lib/postgresql/PG_VERSION ]; then
    install -o postgres -g postgres -m 755 -d /var/lib/postgresql
    su -c "${_INITDB} /var/lib/postgresql" postgres

    sed -ir -f- "/var/lib/postgresql/postgresql.conf" <<- EOF
	s|^[[:space:]#]*\(listen_addresses[[:space:]]*\)=.*$|\1= '*'|;
EOF

    sed -ir -f- "/var/lib/postgresql/pg_hba.conf" <<- EOF
	s|^[[:space:]]*#*[[:space:]]*\(local[[:space:]]*all[[:space:]]*all[[:space:]]*\)peer|\1md5|;
	s|127.0.0.1/32|0.0.0.0/0|;
EOF

    [ -z "${POSTGRES_PASSWORD}" ] && POSTGRES_PASSWORD=`pwgen 32 1`
  fi

  if [ -n "${POSTGRES_PASSWORD}" ]; then
#    install -o root -p root -m 600 /dev/null /root/.pgpass
    cat > /root/.pgpass <<- EOF
	localhost:5432:*:root:${POSTGRES_PASSWORD}
EOF
    chmod 600 /root/.pgpass

    _post_init &
  fi

  su -c "exec ${_POSTGRES} -D /var/lib/postgresql" postgres

  return 0
}

_manage () {
  _CMD="$1"
  [ -n "${_CMD}" ] && shift

  case "${_CMD}" in
    "db")
      _manage_db $*
      ;;
    *)
      _usage
      ;;
  esac

  return 0
}

_manage_db () {
  _CMD="$1"
  [ -n "${_CMD}" ] && shift

  case "${_CMD}" in
    "create")
      _manage_db_create $*
      ;;
    "edit")
      _manage_db_edit $*
      ;;
    *)
      _usage
      ;;
  esac

  return 0
}

_manage_db_create () {
  _DB="$1"
  [ -z "${_DB}" ] && return 1 || shift
  [ `psql -At -c "SELECT COUNT(*) FROM pg_database WHERE datname='${_DB}';"` -ge 1 ] && return 1

  _USER="$1"
  [ -z "${_USER}" ] && _USER="${_DB}" || shift
  [ `psql -At -c "SELECT COUNT(*) FROM pg_roles WHERE rolname='${_USER}';"` -ge 1 ] && return 1

  _PASSWORD="$1"
  [ -z "${_PASSWORD}" ] && _PASSWORD=`pwgen 12 1` || shift

  psql -q <<- EOF
	CREATE ROLE "${_USER}" WITH LOGIN ENCRYPTED PASSWORD '${_PASSWORD}' NOCREATEDB NOCREATEROLE NOSUPERUSER;
	CREATE DATABASE "${_DB}" WITH OWNER "${_USER}";
	GRANT ALL PRIVILEGES ON DATABASE "${_DB}" TO "${_USER}";
	REVOKE ALL PRIVILEGES ON DATABASE "${_DB}" FROM PUBLIC;
EOF

  echo "db: ${_DB}, user: ${_USER}, password: ${_PASSWORD}"

  return 0
}

_manage_db_edit () {
  _DB="$1"
  [ -z "${_DB}" ] && return 1 || shift
  [ `psql -At -c "SELECT COUNT(*) FROM pg_database WHERE datname='${_DB}';"` -ge 1 ] || return 1


  psql "${_DB}"

  return 0
}

_post_init () {
    until echo 'SELECT 1' | psql -q -U postgres > /dev/null 2>&1; do
      sleep 1
    done

    psql -q -U postgres <<- EOF
	CREATE ROLE "root" WITH SUPERUSER CREATEDB CREATEROLE LOGIN ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}';
	CREATE DATABASE "root" WITH OWNER "root";
	GRANT ALL PRIVILEGES ON DATABASE "root" TO "root";
	REVOKE ALL PRIVILEGES ON DATABASE "root" FROM PUBLIC;
EOF

  return 0
}

_shell () {
  exec /bin/bash

  return 0
}

_usage () {
  cat <<- EOF
	Usage: $0 install
	       $0 init
	       $0 manage db create <database_name> [ <user_name> [ <password> ]]
	       $0 manage db edit <database_name>
	       $0 shell
EOF

  return 0
}

_CMD="$1"
[ -n "${_CMD}" ] && shift

case "${_CMD}" in
  "install")
    _install $*
    ;;
  "init")
    _init $*
    ;;
  "manage")
    _manage $*
    ;;
  "shell")
    _shell $*
    ;;
  *)
    _usage
    ;;
esac
