#!/bin/bash
set -Eeuo pipefail

############################################
# Trap
############################################
trap 'echo "$(date "+%F %T") ERROR: failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

############################################
# Paths & Config
############################################
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CONF_DIR="${SCRIPT_DIR}/../conf"
CONF_FILE="${CONF_DIR}/mysql_install.conf"

[[ -f "$CONF_FILE" ]] || { echo "ERROR: config not found: $CONF_FILE" >&2; exit 1; }
source "$CONF_FILE"

############################################
# Validate required vars
############################################
require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || { echo "ERROR: required var $name unset" >&2; exit 1; }
}

require_var MYSQL_TAR
require_var MYSQL_USER
require_var MYSQL_GROUP
require_var INSTALL_HOME_DIR
require_var INSTALL_DIR
require_var MYSQL_DATA_DIR
require_var MYSQL_CONF_DIR
require_var MYSQL_LOG_DIR
require_var MYSQL_PORT
require_var MYSQL_SERVER_ID
require_var MYSQL_ROOT_PASSWORD
require_var MYSQL_REPL_USER
require_var MYSQL_REPL_PASSWORD

MYSQL_CNF="${MYSQL_CONF_DIR}/my.cnf"
MYSQL_SOCKET="${MYSQL_CONF_DIR}/mysql.sock"
MYSQL_PIDFILE="${MYSQL_CONF_DIR}/mysqld.pid"
MYSQL_SERVER_SCRIPT="${INSTALL_HOME_DIR}/bin/mysql.server"
MYSQL_SERVER_SRC="${SCRIPT_DIR}/mysql.server"
TMP_DIR="${MYSQL_CONF_DIR}/tmp"

############################################
# Logging
############################################
LOG_FILE="${MYSQL_LOG_DIR}/install_mysql.log"
mkdir -p "$MYSQL_LOG_DIR"

log() {
  local level="$1"; shift
  local ts
  ts="$(date '+%F %T')"
  echo "$ts $level: $*"
  echo "$ts $level: $*" >>"$LOG_FILE" 2>/dev/null || true
}

############################################
# Check system
############################################
check_system() {
  log INFO "===== MySQL 8.4 Install Start ====="
  log INFO "Checking system environment..."
  uname -m || true
  ldd --version | head -1 || true
}

############################################
# User & Group
############################################
ensure_user() {
  log INFO "Ensuring MySQL user and group..."
  getent group "$MYSQL_GROUP" >/dev/null 2>&1 || groupadd "$MYSQL_GROUP"
  id "$MYSQL_USER" >/dev/null 2>&1 || useradd -g "$MYSQL_GROUP" -s /bin/bash "$MYSQL_USER"
}

############################################
# Directories
############################################
prepare_dirs() {
  log INFO "Preparing directories..."

  mkdir -p \
    "$INSTALL_HOME_DIR"/{bin,conf,data,logs} \
    "$MYSQL_CONF_DIR"/{lock,tmp} \
    "$MYSQL_LOG_DIR"/{errorlog,binlog,relaylog} \
    "$MYSQL_DATA_DIR"

  chown -R "$MYSQL_USER:$MYSQL_GROUP" "$INSTALL_HOME_DIR"
  chmod -R 755 "$INSTALL_HOME_DIR"
}

############################################
# Extract MySQL base (upgrade-safe)
############################################
install_mysql_base() {
  log INFO "Extracting MySQL tarball..."

  [[ -f "$MYSQL_TAR" ]] || { log ERROR "MySQL tar not found: $MYSQL_TAR"; exit 1; }

  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  tar -xf "$MYSQL_TAR" -C "$INSTALL_DIR" --strip-components=1

  [[ -x "$INSTALL_DIR/bin/mysqld" ]] || {
    log ERROR "mysqld not found after extract"
    exit 1
  }

  chown -R "$MYSQL_USER:$MYSQL_GROUP" "$INSTALL_DIR"
}

############################################
# Generate my.cnf
############################################
generate_mycnf() {
  log INFO "Generating my.cnf..."

  local hostname current_date
  hostname="$(hostname)"
  current_date="$(date +%Y%m%d)"

  sed \
    -e "s|\${MYSQL_USER}|$MYSQL_USER|g" \
    -e "s|\${MYSQL_PORT}|$MYSQL_PORT|g" \
    -e "s|\${MYSQL_SERVER_ID}|$MYSQL_SERVER_ID|g" \
    -e "s|\${MYSQL_DATA_DIR}|$MYSQL_DATA_DIR|g" \
    -e "s|\${MYSQL_CONF_DIR}|$MYSQL_CONF_DIR|g" \
    -e "s|\${MYSQL_LOG_DIR}|$MYSQL_LOG_DIR|g" \
    -e "s|\${hostname}|$hostname|g" \
    -e "s|\${current_date}|$current_date|g" \
    "${CONF_DIR}/my.cnf.sample" > "$MYSQL_CNF"

  chown "$MYSQL_USER:$MYSQL_GROUP" "$MYSQL_CNF"
  chmod 640 "$MYSQL_CNF"
}

############################################
# Initialize MySQL (only first time)
############################################
initialize_mysql() {
  log INFO "Initializing MySQL data directory..."

  if [[ -d "$MYSQL_DATA_DIR/mysql" ]]; then
    log INFO "Data directory already initialized, skip"
    return
  fi

  chown -R "$MYSQL_USER:$MYSQL_GROUP" "$MYSQL_DATA_DIR"

  su - "$MYSQL_USER" -c \
    "$INSTALL_DIR/bin/mysqld --defaults-file=$MYSQL_CNF --initialize" >>"$LOG_FILE" 2>&1
}

############################################
# Install mysql.server (copy only)
############################################
install_mysql_server() {
  log INFO "Installing mysql.server..."

  [[ -f "$MYSQL_SERVER_SRC" ]] || {
    log ERROR "mysql.server not found in script dir"
    exit 1
  }

  cp "$MYSQL_SERVER_SRC" "$MYSQL_SERVER_SCRIPT"
  chmod 755 "$MYSQL_SERVER_SCRIPT"
  chown root:root "$MYSQL_SERVER_SCRIPT"
}

############################################
# Start MySQL
############################################
start_mysql() {
  log INFO "Starting MySQL..."
  "$MYSQL_SERVER_SCRIPT" start >>"$LOG_FILE" 2>&1
}

############################################
# Secure MySQL
############################################
secure_mysql() {
  log INFO "Configuring root and replication user..."

  mkdir -p "$TMP_DIR"
  local sql_file errlog init_pwd
  sql_file="$(mktemp "$TMP_DIR/secure.XXXX.sql")"

  cat > "$sql_file" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS '${MYSQL_REPL_USER}'@'%' IDENTIFIED BY '${MYSQL_REPL_PASSWORD}';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${MYSQL_REPL_USER}'@'%';
FLUSH PRIVILEGES;
SQL

  errlog="$(ls -1t "$MYSQL_LOG_DIR/errorlog/"*error*.log 2>/dev/null | head -1 || true)"
  init_pwd="$(grep -m1 'temporary password' "$errlog" | awk '{print $NF}' || true)"

  if [[ -n "$init_pwd" ]]; then
    log INFO "Detected temporary root password"
    "$INSTALL_DIR/bin/mysql" --connect-expired-password \
      -uroot -p"$init_pwd" -S "$MYSQL_SOCKET" < "$sql_file" >>"$LOG_FILE" 2>&1
  else
    log INFO "Root password already set"
    "$INSTALL_DIR/bin/mysql" -uroot -p"$MYSQL_ROOT_PASSWORD" \
      -S "$MYSQL_SOCKET" < "$sql_file" >>"$LOG_FILE" 2>&1 || true
  fi

  rm -f "$sql_file"
}

############################################
# Main
############################################
check_system
ensure_user
prepare_dirs
install_mysql_base
generate_mycnf
initialize_mysql
install_mysql_server
start_mysql
secure_mysql

log INFO "===== MySQL 8.4 Install Finished ====="
