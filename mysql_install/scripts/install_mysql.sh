#!/bin/bash

SCRIPT_DIR=$(dirname "$0")         
SCRIPT_NAME=$(basename "$0" .sh)  

# 加载 MySQL 安装配置文件
CONFIG_FILE="${SCRIPT_DIR}/../conf/mysql_install.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "Configuration file $CONFIG_FILE not found!"; exit 1; }
source "$CONFIG_FILE"

# 日志文件路径
LOG_FILE="${MYSQL_LOG_DIR}/install_mysql.log"
mkdir -p "$(dirname "$LOG_FILE")"

# 日志函数
log_info() { echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $1" | tee -a "$LOG_FILE"; }
log_warn() { echo "$(date '+%Y-%m-%d %H:%M:%S') WARN: $1" | tee -a "$LOG_FILE"; }
log_error() { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1" | tee -a "$LOG_FILE"; exit 1; }

# 确保目录存在
ensure_directory_exists() {
    local dir="$1"
    log_info "check directory : $dir ."
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

# 获取系统信息并检查兼容性
check_system_requirements() {
    log_info "Checking system environment..."
    ARCH=$(uname -m)
    GLIBC_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
    MYSQL_GLIBC_VERSION=$(echo "$MYSQL_TAR" | grep -oP 'glibc\d+\.\d+' | grep -oP '\d+\.\d+')
    MYSQL_ARCH=$(echo "$MYSQL_TAR" | grep -oP 'x86_64|aarch64')
    log_info "System Architecture: $ARCH"
    log_info "glibc Version: $GLIBC_VERSION"

    if [[ $(echo "$GLIBC_VERSION $MYSQL_GLIBC_VERSION" | awk '{print ($1 < $2)}') -eq 1 ]]; then
        log_error "glibc version ($GLIBC_VERSION) is too low. Required: $MYSQL_GLIBC_VERSION."
    fi
    [[ "$ARCH" == "$MYSQL_ARCH" ]] || log_error "System architecture ($ARCH) does not match MySQL package ($MYSQL_ARCH)."
    log_info "System environment matches MySQL package."
}

# 安装 MySQL 依赖库（libaio）
install_dependencies() {
    log_info "Installing required dependencies..."
    log_info "check and install libaio!"
    rpm -q libaio &>/dev/null || yum install -y libaio || log_error "Failed to install libaio."
}

# 准备 MySQL 目录并设置权限
prepare_mysql_directories() {
    log_info "Preparing MySQL directories..."
    ensure_directory_exists "$INSTALL_HOME_DIR"
    ensure_directory_exists "$INSTALL_DIR"
    ensure_directory_exists "$MYSQL_DATA_DIR"
    ensure_directory_exists "$MYSQL_CONF_DIR"
    ensure_directory_exists "$MYSQL_LOG_DIR"
    ensure_directory_exists "$MYSQL_LOG_DIR/errorlog"
    ensure_directory_exists "$MYSQL_LOG_DIR/binlog"
    ensure_directory_exists "$MYSQL_LOG_DIR/relaylog"

    log_info "change owner "$MYSQL_USER:$MYSQL_GROUP" for directory $INSTALL_HOME_DIR! "
    chown -R "$MYSQL_USER:$MYSQL_GROUP" "$INSTALL_HOME_DIR"
    chmod -R 750 "$INSTALL_HOME_DIR"
    log_info "MySQL directories prepared successfully."
}

# 解压 MySQL 安装包
extract_mysql_package() {
    log_info "Extracting MySQL package..."
    rm -rf "$INSTALL_DIR"/*
    tar -xJf "$MYSQL_TAR" -C "$INSTALL_DIR" --strip-components=1
    log_info "MySQL extracted successfully to $INSTALL_DIR"
}

# 创建 MySQL 用户
create_mysql_user() {
    log_info "Creating MySQL user: $MYSQL_USER"
    if ! id "$MYSQL_USER" &>/dev/null; then
        groupadd "$MYSQL_GROUP"
        useradd -r -g "$MYSQL_GROUP" -d /home/${MYSQL_USER} -s /bin/false "$MYSQL_USER"
        log_info "Created MySQL user and group."
    else
        log_warn "MySQL user $MYSQL_USER already exists."
    fi
}

# 生成 MySQL 配置文件
generate_mysql_cnf() {
    log_info "Generating MySQL configuration file..."

    hostname=$(hostname | tr -d ' ')
    total_memory_mb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    innodb_buffer_pool_size_mb=$(( total_memory_mb / 2 / 1024 ))
    [[ $innodb_buffer_pool_size_mb -lt 1 ]] && innodb_buffer_pool_size_mb=1
    innodb_buffer_pool_size="${innodb_buffer_pool_size_mb}G"
    current_date=$(date +"%Y%m%d")

    # 确保 MYSQL_SERVER_ID 不为空
    if [[ -z "$MYSQL_SERVER_ID" ]]; then
        log_warn "MYSQL_SERVER_ID is empty, setting default server_id=1"
        MYSQL_SERVER_ID=1
    fi

    sed -e "s|\${MYSQL_CONF_DIR}|$MYSQL_CONF_DIR|g" \
        -e "s|\${MYSQL_DATA_DIR}|$MYSQL_DATA_DIR|g" \
        -e "s|\${MYSQL_LOG_DIR}|$MYSQL_LOG_DIR|g" \
        -e "s|\${MYSQL_PORT}|$MYSQL_PORT|g" \
        -e "s|\${MYSQL_USER}|$MYSQL_USER|g" \
        -e "s|\${hostname}|$hostname|g" \
        -e "s|\${current_date}|$current_date|g" \
        -e "s|\${innodb_buffer_pool_size}|$innodb_buffer_pool_size|g" \
        -e "s|\${MYSQL_SERVER_ID}|$MYSQL_SERVER_ID|g" \
        ${SCRIPT_DIR}/../conf/my.cnf.sample > "$MYSQL_CNF"
    log_info "Chanage owner of file $MYSQL_CNF to $MYSQL_USER ! "
    chown $MYSQL_USER:$MYSQL_GROUP $MYSQL_CNF

    log_info "MySQL configuration file created: $MYSQL_CNF"
}

# 初始化 MySQL
initialize_mysql() {
    log_info "Initializing MySQL..."
    log_info "exec cmd : "$INSTALL_DIR/bin/mysqld" --defaults-file="$MYSQL_CNF" --initialize --user="$MYSQL_USER""
    "$INSTALL_DIR/bin/mysqld" --defaults-file="$MYSQL_CNF" --initialize --user="$MYSQL_USER"
    log_info "MySQL initialized successfully."
}

# 获取 MySQL 初始密码
get_mysql_init_password() {
    log_info "Fetching MySQL initial root password..."
    MYSQL_ERROR_LOG=$(grep "^log_error" "$MYSQL_CNF" | cut -d '=' -f2 | tr -d ' ')
    MYSQL_ROOT_TEMP_PASSWORD=$(grep "temporary password" "$MYSQL_ERROR_LOG" | awk '{print $NF}' | tail -n1)

    if [[ -z "$MYSQL_ROOT_TEMP_PASSWORD" ]]; then
      log_error "Failed to retrieve MySQL temporary root password."
    fi
    log_info "MySQL initial root password retrieved: $MYSQL_ROOT_TEMP_PASSWORD"
}

# 启动mysql服务
start_mysql_service(){
    log_info "Starting mysql server with cmd : "$INSTALL_DIR/bin/mysqld" --defaults-file="$MYSQL_CNF" --daemonize"
    "$INSTALL_DIR/bin/mysqld" --defaults-file="$MYSQL_CNF" --daemonize
    sleep 15
    MYSQL_SOCKET=$(grep "^socket" "$MYSQL_CNF" | cut -d '=' -f2 | tr -d ' ')

    for i in {1..10}; do
        if [[ -S "$MYSQL_SOCKET" ]]; then
            log_info "MySQL socket file detected: $MYSQL_SOCKET"
            break
        fi
        sleep 2
    done

}

# 停止mysql服务
stop_mysql_service(){
    log_info "Stopping MySQL service..."
    "$INSTALL_DIR/bin/mysqladmin" -uroot -p"$MYSQL_ROOT_PASSWORD" --socket="$MYSQL_SOCKET" shutdown \
    && log_info "MySQL stopped successfully." \
    || log_error "MySQL shutdown failed."
}

# 修改 MySQL root 密码
change_mysql_root_password() {
    log_info "Changing MySQL root password with mysqladmin..." 
    # 明确导出密码
    export MYSQL_PWD="${MYSQL_ROOT_TEMP_PASSWORD}"
    log_info "exec cmd : export MYSQL_PWD="${MYSQL_ROOT_TEMP_PASSWORD}""
    log_info "exec cmd : "$INSTALL_DIR/bin/mysqladmin" -uroot --socket=${MYSQL_SOCKET} -p${MYSQL_ROOT_TEMP_PASSWORD} password ${MYSQL_ROOT_PASSWORD}"
    "$INSTALL_DIR/bin/mysqladmin" -uroot --socket=${MYSQL_SOCKET} -p${MYSQL_ROOT_TEMP_PASSWORD} password ${MYSQL_ROOT_PASSWORD} \
    && log_info "MySQL root password changed successfully." \
    || log_error "Failed to change MySQL root password."
    unset MYSQL_PWD
    export MYSQL_PWD="${MYSQL_ROOT_PASSWORD}"
    log_info "Set user root connection from remote ."
    "$INSTALL_DIR/bin/mysql" -uroot --socket="$MYSQL_SOCKET" -e "update mysql.user set host = '%' where user = 'root';"
    unset MYSQL_PWD
}

# 验证新密码是否有效
check_mysql_password() {
    log_info "Try to checking mysql new password !"
    export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
    "$INSTALL_DIR/bin/mysql" -uroot --socket="$MYSQL_SOCKET" -e "status" \
    && log_info "Password validation successful." \
    || log_error "New root password verification failed."
    unset MYSQL_PWD
}

# 创建mysql 备份用户
create_mysql_replica_user() {
    log_info "Starting create mysql replica user repuser ."
    export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
    "$INSTALL_DIR/bin/mysql" -uroot --socket="$MYSQL_SOCKET" -e "create user 'repuser'@'%' identified with mysql_native_password by '$MYSQL_ROOT_PASSWORD';" 
    "$INSTALL_DIR/bin/mysql" -uroot --socket="$MYSQL_SOCKET" -e "grant all privileges on *.* to 'repuser'@'%' with grant option;"
    log_info "Create mysql replica user repuser complete ."
    unset MYSQL_PWD
}

# 生成启动脚本
generate_mysql_service_script() {
    log_info "Generating MySQL service startup script..."

    local source_script="${INSTALL_DIR}/support-files/mysql.server"
    local target_script="/usr/local/bin/mysql.server"
    local systemd_unit_file="/etc/systemd/system/mysqld.service"

    # 检查模板脚本是否存在
    if [[ ! -f "$source_script" ]]; then
        log_error "MySQL source service script not found: $source_script"
    fi

    # 获取配置参数
    local basedir="$INSTALL_DIR"
    local datadir=$(grep "^datadir" "$MYSQL_CNF" | cut -d '=' -f2 | tr -d ' ')
    local socket=$(grep "^socket" "$MYSQL_CNF" | cut -d '=' -f2 | tr -d ' ')
    local pidfile=$(grep "^pid-file" "$MYSQL_CNF" | cut -d '=' -f2 | tr -d ' ')
    local mysqld_bin="$INSTALL_DIR/bin/mysqld_safe"

    # 复制并修改 mysql.server 启动脚本
    cp "$source_script" "$target_script"

    # 替换默认路径参数
    sed -i '0,/^basedir=.*/s|^basedir=.*|basedir='"$basedir"'|' "$target_script"
    sed -i '0,/^datadir=.*/s|^datadir=.*|datadir='"$datadir"'|' "$target_script"
    sed -i '0,/mysqld_pid_file_path=.*/s|mysqld_pid_file_path=.*|mysqld_pid_file_path='"$pidfile"'|' "$target_script"
    # sed -i "s|^basedir=.*|basedir=$basedir|g" "$target_script"
    # sed -i "s|^datadir=.*|datadir=$datadir|g" "$target_script"
    # sed -i "s|mysqld_pid_file_path=.*|mysqld_pid_file_path=$pidfile|g" "$target_script"
    # sed -i "s|^mysqld_safe=.*|mysqld_safe=$mysqld_bin|g" "$target_script"

    # 替换 mysqld_safe 启动行为，加上 --defaults-file 参数
    sed -i 's|\$bindir/mysqld_safe --datadir="\$datadir" --pid-file="\$mysqld_pid_file_path" \$other_args >/dev/null &|\
      $bindir/mysqld_safe --defaults-file='"$MYSQL_CNF"' --datadir="$datadir" --pid-file="$mysqld_pid_file_path" $other_args >/dev/null \&|' "$target_script"

    chown $MYSQL_USER:$MYSQL_GROUP $target_script
    chmod +x "$target_script"
    log_info "MySQL startup script generated at: $target_script"

    # 生成 systemd 服务单元文件
    cat > "$systemd_unit_file" <<EOF
[Unit]
Description=MySQL Server
After=network.target

[Service]
Type=forking
ExecStart=$target_script start
ExecStop=$target_script  stop
ExecReload=$target_script restart
PIDFile=$pidfile
User=$MYSQL_USER
Group=$MYSQL_GROUP

# 重启策略
Restart=on-failure
RestartSec=5

# 限制5分钟内只能重启2次
StartLimitIntervalSec=300
StartLimitBurst=2

# 启动/关闭超时设置
TimeoutStartSec=30
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载并启用服务
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable mysqld
    systemctl start mysqld

    log_info "Systemd service mysqld.service has been created and started."
}

# 运行 MySQL 安装流程
run_mysql_installation() {
    check_system_requirements
    install_dependencies
    create_mysql_user
    prepare_mysql_directories
    extract_mysql_package
    generate_mysql_cnf
    initialize_mysql
    start_mysql_service
    get_mysql_init_password
    change_mysql_root_password
    check_mysql_password
    create_mysql_replica_user
    stop_mysql_service
    generate_mysql_service_script
    log_info "MySQL installation completed successfully."
}

main() {
    log_info "Starting MySQL Installation..."
    run_mysql_installation
    log_info "MySQL Installation Finished!"
}

main