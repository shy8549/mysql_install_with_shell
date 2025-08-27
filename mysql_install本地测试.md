# 一、MySQL 双主热备搭建

## 1. 基础环境

*   **OS**

    ```
    NAME="BigCloud Enterprise Linux"
    VERSION="21.10 (LTS-SP2)"
    ID="bclinux"
    VERSION_ID="21.10"
    PRETTY_NAME="BigCloud Enterprise Linux For Euler 21.10 LTS"
    ANSI_COLOR="0;31"

    ```
*   **MySQL**

    *   建议版本：`8.0.4`（现网安装推荐，避免安全漏洞）
    *   测试版本：`mysql-8.0.35-linux-glibc2.28-x86_64.tar.xz`
*   **IP**

    *   `10.10.84.249`
    *   `10.10.84.254`

***

## 2. 脚本安装 MySQL 环境

### 2.1 脚本目录结构

```
mysql_install
├── conf
│   ├── my.cnf.sample
│   └── mysql_install.conf
├── package
│   └── mysql-8.0.42-linux-glibc2.28-x86_64.tar
└── scripts
    └── install_mysql.sh

```

### 2.2 配置文件示例

#### `my.cnf.sample`

（配置了 socket、pid、bind-address、port、user、datadir、字符集、日志、binlog、GTID、连接数、缓存、InnoDB 参数等）

```shell
[root@centos76-01 conf]# cat my.cnf.sample 
# 基本设置
[mysqld]
## MySQL套接字文件位置，用于本地连接
socket=${MYSQL_CONF_DIR}/mysql.sock 
## MySQL进程ID文件，用于管理MySQL进程 
pid-file=${MYSQL_CONF_DIR}/mysqld.pid 
## MySQL绑定的IP地址，0.0.0.0表示监听所有IP地址 
bind-address=0.0.0.0  
## MySQL监听的端口，默认是3306，这里设置为15800
port=${MYSQL_PORT}
## 运行MySQL的用户，通常为mysql
user=${MYSQL_USER}
## MySQL数据目录，存储数据库文件
datadir=${MYSQL_DATA_DIR}
## 设置MySQL字符集为UTF-8MB4，支持更广泛的字符集
character-set-server=UTF8MB4  
## 设置默认时区为东八区
default-time-zone='+08:00'  
## 大小写不敏感
lower_case_table_names=1   
## 设置 client 连接 mysql 时的字符集, 防止乱码
init_connect='SET NAMES utf8mb4'   

# 日志设置
## 开启慢查询日志，记录执行时间超过long_query_time的查询  
slow_query_log=ON
## 设置查询超时为5秒，超过此时间的查询会被记录为慢查询
long_query_time=5 
## 慢查询日志文件位置 
slow_query_log_file=${MYSQL_LOG_DIR}/errorlog/${hostname}-slow-query-${current_date}.log 
## 记录未使用索引的查询，有助于优化查询性能 
log_queries_not_using_indexes=1
## 记录慢的管理语句，如OPTIMIZE TABLE、ANALYZE TABLE等  
log_slow_admin_statements=1  
## 错误日志文件位置
log_error=${MYSQL_LOG_DIR}/errorlog/${hostname}-error-${current_date}.log  

# binlog设置
## 开启binlog,8.0版本默认开启
log_bin=on
## 设置二进制日志文件，用于主从复制和恢复
log_bin=${MYSQL_LOG_DIR}/binlog/${hostname}-binlog
## 设置二进制日志索引文件  
log_bin_index=${MYSQL_LOG_DIR}/binlog/${hostname}-binlog.index  
## 开启记录行级日志事件，有助于调试和审计
binlog_rows_query_log_events=on
## 设置二进制日志缓存大小，建议根据事务大小调整  
binlog_cache_size=2M
## 设置单个二进制日志的最大大小为1GB，避免日志文件过大  
max_binlog_size=1024M
## 设置二进制日志保留7天（604800秒），避免日志文件过多  
binlog_expire_logs_seconds=604800


# 复制相关配置
## MySQL服务器ID，用于主从复制，通常取IP的末位或其他唯一标识，如果不同网段需要手动调整
server_id=${MYSQL_SERVER_ID}
## 设置中继日志文件位置  
relay_log=${MYSQL_LOG_DIR}/relaylog/${hostname}-relaylog-bin
## 设置中继日志索引文件位置  
relay_log_index=${MYSQL_LOG_DIR}/relaylog/${hostname}-relaylog-bin.index
## 启用中继日志自动清理，避免日志文件过多  
relay_log_purge=1
## 主从数据同步的线程数，建议根据CPU核心数设置,8.0.27前默认是0，之后默认是4
replica_parallel_workers=4

## 开启GTID（全局事务标识符）模式，简化主从复制管理  
gtid_mode=on
## 强制GTID一致性，确保事务在复制时的一致性  
enforce_gtid_consistency=on
## 开启GTID简单恢复模式，简化崩溃恢复过程  
binlog_gtid_simple_recovery=1
## 设置自增列的递增步长，通常用于主从复制  
auto_increment_increment=2
## 设置自增列的起始值偏移量，通常用于主从复制  
auto_increment_offset=1  

# 连接和缓存配置
## 设置最大连接错误次数，超过此值会阻止连接
max_connect_errors=10000
## 设置最大连接数为1000，建议根据应用需求调整  
max_connections=1000
## 设置连接缓冲区大小为8MB，建议根据查询复杂度调整  
join_buffer_size=8M
## 设置MyISAM索引缓冲区大小为256MB，建议根据MyISAM表大小调整  
key_buffer_size=256M
## 设置批量插入缓冲区大小为96MB，建议根据批量插入数据量调整  
bulk_insert_buffer_size=96M
## 设置临时表大小为96MB，建议根据查询复杂度调整  
tmp_table_size=96M
## 设置读缓冲区大小为8MB，建议根据查询复杂度调整  
read_buffer_size=8M
## 设置排序缓冲区大小为2MB，建议根据排序数据量调整  
sort_buffer_size=2M
## 设置最大允许的数据包大小为64MB，建议根据应用需求调整  
max_allowed_packet=64M
## 设置随机读缓冲区大小为32MB，建议根据查询复杂度调整  
read_rnd_buffer_size=32M  

# InnoDB配置
## 设置InnoDB日志提交方式，2表示每次事务提交时将日志缓冲区的数据写入文件系统缓存，每秒由操作系统调度刷盘一次。
innodb_flush_log_at_trx_commit=2
## 用于控制Binlog的更新策略。取值范围 0、1 或 N（正整数），100表示每100次事务提交后将Binlog写入磁盘。如果设置为1，IO开销非常大
sync_binlog=100
## 设置InnoDB数据文件路径及大小，自动扩展至最大500G  
innodb_data_file_path=ibdata1:2G:autoextend:max:500G
## 设置InnoDB缓冲池大小为系统内存的一半
innodb_buffer_pool_size=64G
## 设置InnoDB缓冲池实例数为8，建议根据CPU核心数设置  
innodb_buffer_pool_instances=8
## 设置InnoDB页面清理线程数为8，建议根据CPU核心数设置  
innodb_page_cleaners=8
## 设置InnoDB重做日志容量为5GB，建议根据事务量调整  
innodb_redo_log_capacity=5368709120
## 启用每个表使用独立表空间，便于管理和备份  
innodb_file_per_table=1
## 设置InnoDB刷新日志的方式为O_DSYNC，确保数据安全  
innodb_flush_method=O_DSYNC
## 禁用InnoDB邻接页面的刷新优化，适用于SSD  
innodb_flush_neighbors=0
## 设置InnoDB日志缓冲区大小为64MB，建议根据事务量调整  
innodb_log_buffer_size=64M
## 设置InnoDB I/O容量，推荐值为500，SSD或高性能存储建议为1400或更高  
innodb_io_capacity=500
## 设置InnoDB最大I/O容量为2000，建议根据存储性能调整  
innodb_io_capacity_max=2000
## 设置InnoDB读I/O线程数为16，建议根据CPU核心数设置  
innodb_read_io_threads=16
## 设置InnoDB写I/O线程数为16，建议根据CPU核心数设置  
innodb_write_io_threads=16
## 设置InnoDB线程并发控制为128，建议根据CPU核心数调整  
innodb_thread_concurrency=128
## 设置InnoDB锁等待超时时间为900秒，避免长时间锁等待  
innodb_lock_wait_timeout=900
## 设置InnoDB最大脏页百分比为95%，建议根据内存大小调整  
innodb_max_dirty_pages_pct=95
## 设置InnoDB允许打开的最大文件数为50000，建议根据表数量调整  
innodb_open_files=50000

```

#### `mysql_install.conf`

```
[root@centos76-01 conf]#  cat mysql_install.conf 
# mysql_install.conf
# MySQL 安装相关配置

INSTALL_HOME_DIR="/data/mysql"
INSTALL_DIR="/data/mysql/base"
MYSQL_LOG_DIR="/data/mysql/logs"
MYSQL_TAR="../package/mysql-8.0.35-linux-glibc2.28-x86_64.tar.xz"
MYSQL_PORT="15800"
MYSQL_SERVER_ID=$(hostname -I | awk '{split($1, a, "."); print a[4]}')

# MySQL 用户相关
MYSQL_USER="tongtech"
MYSQL_GROUP="tongtech"

# MySQL 数据目录
MYSQL_DATA_DIR="/data/mysql/data"

# MySQL 配置文件路径
MYSQL_CONF_DIR="/data/mysql/conf"
MYSQL_CNF="${MYSQL_CONF_DIR}/my.cnf"

# # MySQL root 账户密码（请务必修改为安全密码）
MYSQL_ROOT_PASSWORD="MySecurePass@123"

```

***

### 2.3 安装脚本 `install_mysql.sh`

主要流程：

1.  检查系统环境
2.  安装依赖（libaio）
3.  创建用户与目录
4.  解压 MySQL 包
5.  生成 `my.cnf`
6.  初始化 MySQL
7.  启动 MySQL 并修改 root 密码
8.  创建同步用户 `repuser`
9.  生成 systemd 服务

&#x20;\<details> \<summary>点击展开脚本内容\</summary>

```
[root@centos76-01 scripts]# cat install_mysql.sh 
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

```

&#x20;\</details>

***

## 3. 安装过程示例

运行安装脚本：

```
[root@database-84-249 scripts]# sh install_mysql.sh

```

日志输出（节选）：

```
[root@database-84-249 scripts]# sh install_mysql.sh 
2025-08-26 16:14:37 INFO: Starting MySQL Installation...
2025-08-26 16:14:37 INFO: Checking system environment...
2025-08-26 16:14:37 INFO: System Architecture: x86_64
2025-08-26 16:14:37 INFO: glibc Version: 2.28
2025-08-26 16:14:37 INFO: System environment matches MySQL package.
2025-08-26 16:14:37 INFO: Installing required dependencies...
2025-08-26 16:14:37 INFO: check and install libaio!
Last metadata expiration check: 0:13:37 ago on Tue 26 Aug 2025 04:01:01 PM CST.
Dependencies resolved.
=============================================================================================================================================================================================================
 Package                                        Architecture                                   Version                                                  Repository                                      Size
=============================================================================================================================================================================================================
Installing:
 libaio                                         x86_64                                         0.3.112-1.oe1                                            baseos                                          22 k

Transaction Summary
=============================================================================================================================================================================================================
Install  1 Package

Total download size: 22 k
Installed size: 54 k
Downloading Packages:
libaio-0.3.112-1.oe1.x86_64.rpm                                                                                                                                              1.2 MB/s |  22 kB     00:00    
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Total                                                                                                                                                                        1.1 MB/s |  22 kB     00:00     
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
  Preparing        :                                                                                                                                                                                     1/1 
  Installing       : libaio-0.3.112-1.oe1.x86_64                                                                                                                                                         1/1 
  Running scriptlet: libaio-0.3.112-1.oe1.x86_64                                                                                                                                                         1/1 
  Verifying        : libaio-0.3.112-1.oe1.x86_64                                                                                                                                                         1/1 

Installed:
  libaio-0.3.112-1.oe1.x86_64                                                                                                                                                                                

Complete!
2025-08-26 16:14:40 INFO: Creating MySQL user: tongtech
2025-08-26 16:14:40 WARN: MySQL user tongtech already exists.
2025-08-26 16:14:40 INFO: Preparing MySQL directories...
2025-08-26 16:14:40 INFO: check directory : /data/mysql .
2025-08-26 16:14:40 INFO: check directory : /data/mysql/base .
2025-08-26 16:14:40 INFO: Created directory: /data/mysql/base
2025-08-26 16:14:40 INFO: check directory : /data/mysql/data .
2025-08-26 16:14:40 INFO: Created directory: /data/mysql/data
2025-08-26 16:14:40 INFO: check directory : /data/mysql/conf .
2025-08-26 16:14:40 INFO: Created directory: /data/mysql/conf
2025-08-26 16:14:40 INFO: check directory : /data/mysql/logs .
2025-08-26 16:14:40 INFO: check directory : /data/mysql/logs/errorlog .
2025-08-26 16:14:40 INFO: Created directory: /data/mysql/logs/errorlog
2025-08-26 16:14:40 INFO: check directory : /data/mysql/logs/binlog .
2025-08-26 16:14:40 INFO: Created directory: /data/mysql/logs/binlog
2025-08-26 16:14:40 INFO: check directory : /data/mysql/logs/relaylog .
2025-08-26 16:14:40 INFO: Created directory: /data/mysql/logs/relaylog
2025-08-26 16:14:40 INFO: change owner tongtech:tongtech for directory /data/mysql! 
2025-08-26 16:14:40 INFO: MySQL directories prepared successfully.
2025-08-26 16:14:40 INFO: Extracting MySQL package...
2025-08-26 16:15:06 INFO: MySQL extracted successfully to /data/mysql/base
2025-08-26 16:15:06 INFO: Generating MySQL configuration file...
2025-08-26 16:15:06 INFO: Chanage owner of file /data/mysql/conf/my.cnf to tongtech ! 
2025-08-26 16:15:06 INFO: MySQL configuration file created: /data/mysql/conf/my.cnf
2025-08-26 16:15:06 INFO: Initializing MySQL...
2025-08-26 16:15:06 INFO: exec cmd : /data/mysql/base/bin/mysqld --defaults-file=/data/mysql/conf/my.cnf --initialize --user=tongtech
2025-08-26 16:15:46 INFO: MySQL initialized successfully.
2025-08-26 16:15:46 INFO: Starting mysql server with cmd : /data/mysql/base/bin/mysqld --defaults-file=/data/mysql/conf/my.cnf --daemonize
mysqld will log errors to /data/mysql/logs/errorlog/database-84-249.datashare.com-error-20250826.log
mysqld is running as pid 1607029
2025-08-26 16:16:10 INFO: MySQL socket file detected: /data/mysql/conf/mysql.sock
2025-08-26 16:16:10 INFO: Fetching MySQL initial root password...
2025-08-26 16:16:10 INFO: MySQL initial root password retrieved: e_5SFRxah-yi
2025-08-26 16:16:10 INFO: Changing MySQL root password with mysqladmin...
2025-08-26 16:16:10 INFO: exec cmd : export MYSQL_PWD=e_5SFRxah-yi
2025-08-26 16:16:10 INFO: exec cmd : /data/mysql/base/bin/mysqladmin -uroot --socket=/data/mysql/conf/mysql.sock -pe_5SFRxah-yi password MySecurePass@123
mysqladmin: [Warning] Using a password on the command line interface can be insecure.
Warning: Since password will be sent to server in plain text, use ssl connection to ensure password safety.
2025-08-26 16:16:11 INFO: MySQL root password changed successfully.
2025-08-26 16:16:11 INFO: Set user root connection from remote .
2025-08-26 16:16:11 INFO: Try to checking mysql new password !
--------------
/data/mysql/base/bin/mysql  Ver 8.0.35 for Linux on x86_64 (MySQL Community Server - GPL)

Connection id:          10
Current database:
Current user:           root@localhost
SSL:                    Not in use
Current pager:          stdout
Using outfile:          ''
Using delimiter:        ;
Server version:         8.0.35 MySQL Community Server - GPL
Protocol version:       10
Connection:             Localhost via UNIX socket
Server characterset:    utf8mb4
Db     characterset:    utf8mb4
Client characterset:    utf8mb4
Conn.  characterset:    utf8mb4
UNIX socket:            /data/mysql/conf/mysql.sock
Binary data as:         Hexadecimal
Uptime:                 25 sec

Threads: 2  Questions: 11  Slow queries: 1  Opens: 131  Flush tables: 3  Open tables: 47  Queries per second avg: 0.440
--------------

2025-08-26 16:16:11 INFO: Password validation successful.
2025-08-26 16:16:11 INFO: Starting create mysql replica user repuser .
2025-08-26 16:16:11 INFO: Create mysql replica user repuser complete .
2025-08-26 16:16:11 INFO: Stopping MySQL service...
mysqladmin: [Warning] Using a password on the command line interface can be insecure.
2025-08-26 16:16:15 INFO: MySQL stopped successfully.
2025-08-26 16:16:15 INFO: Generating MySQL service startup script...
2025-08-26 16:16:15 INFO: MySQL startup script generated at: /usr/local/bin/mysql.server
Created symlink /etc/systemd/system/multi-user.target.wants/mysqld.service → /etc/systemd/system/mysqld.service.
2025-08-26 16:16:26 INFO: Systemd service mysqld.service has been created and started.
2025-08-26 16:16:26 INFO: MySQL installation completed successfully.
2025-08-26 16:16:26 INFO: MySQL Installation Finished!

```

***

## 4. 登录测试

配置环境变量

```shell
[tongtech@database-84-249 bin]$ echo 'export PATH=/data/mysql/base/bin:$PATH' >> ~/.bashrc
[tongtech@database-84-249 bin]$ source ~/.bashrc

```

测试用户：

```shell
[tongtech@database-84-249 bin]$ mysql -h 10.10.84.249 -u root -P 15810 -p
Enter password: 
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 9
Server version: 8.0.35 MySQL Community Server - GPL

Copyright (c) 2000, 2023, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> 
mysql> SELECT user, host FROM mysql.user;
+------------------+-----------+
| user             | host      |
+------------------+-----------+
| repuser          | %         |
| root             | %         |
| mysql.infoschema | localhost |
| mysql.session    | localhost |
| mysql.sys        | localhost |
+------------------+-----------+
5 rows in set (0.01 sec)

```

***

## 5. 配置双主热备

### 5.1 复制定位机制对比

#### 1)  文件 + 位点（传统方式）

*   **原理**：记录 `binlog` 文件名 + 位置
*   **优点**：直观、兼容性好、可控
*   **缺点**：需要人工介入、容易错位、切换困难

```sql
CHANGE MASTER TO
  MASTER_LOG_FILE='mysql-bin.000123',
  MASTER_LOG_POS=456;
START SLAVE;

```

#### 2)  GTID（推荐）

*   **原理**：每个事务有全局唯一 `GTID`，自动定位缺失事务
*   **优点**：自动定位、容错高、切换方便、一致性好
*   **缺点**：需要配置 `gtid_mode=ON` 和 `enforce_gtid_consistency=ON`

```sql
CHANGE MASTER TO
  MASTER_AUTO_POSITION=1;
START SLAVE;

```

#### 3)  场景选择

*   单主从/小规模：文件+位点或 GTID
*   大规模/双主/容灾：GTID
*   老版本 (≤5.5)：只能用文件+位点
*   跨机房高可用：GTID 必须

***

### 5.2 双主配置步骤

#### 1) 检查配置项

```
SHOW VARIABLES LIKE 'server_id';                -- 必须不同
SHOW VARIABLES LIKE 'log_bin';                  -- ON
SHOW VARIABLES LIKE 'binlog_format';            -- ROW
SHOW VARIABLES LIKE 'gtid_mode';                -- ON
SHOW VARIABLES LIKE 'enforce_gtid_consistency'; -- ON
SHOW VARIABLES LIKE 'log_slave_updates';        -- 双主建议 ON

```

#### 2) 节点 `10.10.84.249`

1.  查看 master 状态

    ```sql
    SHOW MASTER STATUS\G

    ```
2.  重置复制配置并设置 GTID

    ```sql
    STOP SLAVE;
    RESET SLAVE ALL;
    RESET MASTER;
    -- 254上执行 SELECT @@GLOBAL.gtid_executed; 获取下面需要的值
    SET GLOBAL gtid_purged='58433404-8261-11f0-b156-fa163e7d56a6:1-4';

    ```
3.  配置对端主库

    ```sql
    CHANGE MASTER TO
      MASTER_HOST='10.10.84.254',
      MASTER_PORT=15810,
      MASTER_USER='repuser',
      MASTER_PASSWORD='MySecurePass@123',
      MASTER_AUTO_POSITION=1,
      GET_MASTER_PUBLIC_KEY=1;
    START SLAVE;

    ```

```shell
mysql> show master status\G
*************************** 1. row ***************************
             File: database-84-249.datashare
         Position: 197
     Binlog_Do_DB: 
 Binlog_Ignore_DB: 
Executed_Gtid_Set: 52b05e3e-8261-11f0-ab15-fa163e2e29fb:1-4
1 row in set (0.00 sec)

mysql> SHOW MASTER STATUS;
+---------------------------+----------+--------------+------------------+------------------------------------------+
| File                      | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set                        |
+---------------------------+----------+--------------+------------------+------------------------------------------+
| database-84-249.datashare |      197 |              |                  | 52b05e3e-8261-11f0-ab15-fa163e2e29fb:1-4 |
+---------------------------+----------+--------------+------------------+------------------------------------------+
1 row in set (0.00 sec)

mysql> SHOW VARIABLES LIKE 'server_id';                 -- 两台必须不一样
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| server_id     | 249   |
+---------------+-------+
1 row in set (0.03 sec)

mysql> SHOW VARIABLES LIKE 'log_bin';                   -- ON
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| log_bin       | ON    |
+---------------+-------+
1 row in set (0.00 sec)

mysql> SHOW VARIABLES LIKE 'binlog_format';             -- 建议 ROW
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| binlog_format | ROW   |
+---------------+-------+
1 row in set (0.00 sec)

mysql> SHOW VARIABLES LIKE 'gtid_mode';                 -- ON
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| gtid_mode     | ON    |
+---------------+-------+
1 row in set (0.00 sec)

mysql> SHOW VARIABLES LIKE 'enforce_gtid_consistency';  -- ON
+--------------------------+-------+
| Variable_name            | Value |
+--------------------------+-------+
| enforce_gtid_consistency | ON    |
+--------------------------+-------+
1 row in set (0.00 sec)

mysql> SHOW VARIABLES LIKE 'log_slave_updates';         -- 双主建议 ON
+-------------------+-------+
| Variable_name     | Value |
+-------------------+-------+
| log_slave_updates | ON    |
+-------------------+-------+
1 row in set (0.01 sec)

mysql> 
mysql> STOP SLAVE;
Query OK, 0 rows affected, 2 warnings (0.00 sec)

mysql> RESET SLAVE ALL;
Query OK, 0 rows affected, 1 warning (0.01 sec)

mysql> RESET MASTER;
Query OK, 0 rows affected, 4 warnings (0.02 sec)

-- 254上执行 SELECT @@GLOBAL.gtid_executed; 获取下面需要的值
mysql> SET GLOBAL gtid_purged='58433404-8261-11f0-b156-fa163e7d56a6:1-4';
Query OK, 0 rows affected (0.00 sec)

mysql> CHANGE MASTER TO
    ->   MASTER_HOST='10.10.84.254',
    ->   MASTER_PORT=15810,
    ->   MASTER_USER='repuser',
    ->   MASTER_PASSWORD='MySecurePass@123',
    ->   MASTER_AUTO_POSITION=1,
    ->   GET_MASTER_PUBLIC_KEY=1;
Query OK, 0 rows affected, 8 warnings (0.04 sec)

mysql> 
mysql> START SLAVE;
Query OK, 0 rows affected, 1 warning (0.03 sec)

mysql> SHOW SLAVE STATUS\G
*************************** 1. row ***************************
               Slave_IO_State: Connecting to source
                  Master_Host: 10.10.84.254
                  Master_User: repuser
                  Master_Port: 15810
                Connect_Retry: 60
              Master_Log_File: 
          Read_Master_Log_Pos: 4
               Relay_Log_File: database-84-249.datashare
                Relay_Log_Pos: 4
        Relay_Master_Log_File: 
             Slave_IO_Running: Connecting
            Slave_SQL_Running: Yes
              Replicate_Do_DB: 
          Replicate_Ignore_DB: 
           Replicate_Do_Table: 
       Replicate_Ignore_Table: 
      Replicate_Wild_Do_Table: 
  Replicate_Wild_Ignore_Table: 
                   Last_Errno: 0
                   Last_Error: 
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 0
              Relay_Log_Space: 157
              Until_Condition: None
               Until_Log_File: 
                Until_Log_Pos: 0
           Master_SSL_Allowed: No
           Master_SSL_CA_File: 
           Master_SSL_CA_Path: 
              Master_SSL_Cert: 
            Master_SSL_Cipher: 
               Master_SSL_Key: 
        Seconds_Behind_Master: 0
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 0
                Last_IO_Error: 
               Last_SQL_Errno: 0
               Last_SQL_Error: 
  Replicate_Ignore_Server_Ids: 
             Master_Server_Id: 0
                  Master_UUID: 
             Master_Info_File: mysql.slave_master_info
                    SQL_Delay: 0
          SQL_Remaining_Delay: NULL
      Slave_SQL_Running_State: Replica has read all relay log; waiting for more updates
           Master_Retry_Count: 86400
                  Master_Bind: 
      Last_IO_Error_Timestamp: 
     Last_SQL_Error_Timestamp: 
               Master_SSL_Crl: 
           Master_SSL_Crlpath: 
           Retrieved_Gtid_Set: 
            Executed_Gtid_Set: 58433404-8261-11f0-b156-fa163e7d56a6:1-4
                Auto_Position: 1
         Replicate_Rewrite_DB: 
                 Channel_Name: 
           Master_TLS_Version: 
       Master_public_key_path: 
        Get_master_public_key: 1
            Network_Namespace: 
1 row in set, 1 warning (0.00 sec)
```

#### 3) 节点 `10.10.84.254`

同样步骤，只是 `MASTER_HOST` 改为 `10.10.84.249`。

***

## 6. 验证双主状态

执行：

```
SHOW SLAVE STATUS\G

```

关键检查项：

*   `Slave_IO_Running: Yes`
*   `Slave_SQL_Running: Yes`
*   `Auto_Position: 1`
*   `Retrieved_Gtid_Set` 与对端保持一致

***

✅ 至此，MySQL **双主热备环境搭建完成**。

***

***

## 7. 架构图

```shell
        +---------------------+                         +---------------------+
        |   MySQL 主库 A      |                         |   MySQL 主库 B      |
        |  (10.10.84.249)     |                         |  (10.10.84.254)     |
        |                     |                         |                     |
        |  server_id = 249    |                         |  server_id = 254    |
        |  log_bin = ON       |                         |  log_bin = ON       |
        |  gtid_mode = ON     |                         |  gtid_mode = ON     |
        |  enforce_gtid=ON    |                         |  enforce_gtid=ON    |
        |                     |                         |                     |
        |   binlog  ----------- (复制通道) ----------->  relay log            |
        |                     |                         |                     |
        |   relay log  <------- (复制通道) -----------  binlog                |
        |                     |                         |                     |
        +---------------------+                         +---------------------+

                     <========= 双向复制同步 (GTID 自动定位) =========>

```

***

### 7.1 图示说明

1.  **节点信息**

    *   **A (10.10.84.249)**：`server_id=249`
    *   **B (10.10.84.254)**：`server_id=254`
2.  **复制机制**

    *   两端都开启了 `binlog` 和 `relay log`
    *   双方都启用 `GTID`，复制定位自动完成
    *   `repuser` 负责复制数据
3.  **双向同步**

    *   A 的事务写入 binlog 后，通过复制通道传递到 B 的 relay log 并执行
    *   B 的事务写入 binlog 后，通过复制通道传递到 A 的 relay log 并执行
    *   保证两端数据一致，实现 **双主热备**

### 7.2 双主+负载均衡

*   图 A：双主 + 负载均衡（HAProxy/Nginx/LVS，前置 VIP）
*   图 B：双主 + Keepalived 漂移 VIP（主备/故障切换）

#### 图 A：双主 + 负载均衡（读写同入口，后端双主）

```shell
                +-------------------------------------+
                |           Clients / App             |
                |  (JDBC/Pool, RW or RW-split logic)  |
                +-------------------+-----------------+
                                    |
                                    v
                           +-----------------+
                           |   Load Balancer |
                           | (VIP:10.10.84.1 |
                           |  Port: 15810)   |
                           +----+-------+----+
                                |       |
                ---------------/         \---------------
               /                                      \
+-------------------------+                 +-------------------------+
|     MySQL Master A      |                 |     MySQL Master B      |
|       10.10.84.249      |                 |       10.10.84.254      |
|  port:15810             |                 |  port:15810             |
|  server_id=249          |                 |  server_id=254          |
|  log_bin=ON             |                 |  log_bin=ON             |
|  gtid_mode=ON           |   <-------->    |  gtid_mode=ON           |
|  log_slave_updates=ON   |   GTID repl.    |  log_slave_updates=ON   |
+-----------+-------------+                 +-------------+-----------+
            ^                                                 |
            |---------------------<---------------------------|
                     Replication Channel (binlog <-> relaylog)

Notes:
1) LB 做健康检查：/tcp 15810；失败剔除，恢复加入。
2) 适合应用内有读写分离或幂等写的场景；避免双写冲突（建议按库/表/主键做写入分区）。
3) 复制基于 GTID，Auto_Position=1，便于切换。

```

***

#### 图 B：双主 + Keepalived 漂移 VIP（主活从备，故障自动漂移）

```shell
               +-------------------------------------+
               |           Clients / App             |
               |   JDBC -> 10.10.84.10:15810 (VIP)   |
               +-------------------------+-----------+
                                         |
                                         v
                              +---------------------+
                              |  VIP: 10.10.84.10   |
                              |  Port: 15810        |
                              +----+----------------+
                                   |
                +------------------+------------------+
                |                                     |
                v                                     v
+-------------------------+                 +-------------------------+
|  MySQL Master A (MAIN)  |                 | MySQL Master B (BACKUP) |
|      10.10.84.249       |                 |      10.10.84.254       |
|  holds VIP normally     |                 |  takes VIP on failover  |
|  server_id=249          |   <-------->    |  server_id=254          |
|  log_bin=ON             |   GTID repl.    |  log_bin=ON             |
|  gtid_mode=ON           |                 |  gtid_mode=ON           |
|  log_slave_updates=ON   |                 |  log_slave_updates=ON   |
+-------------------------+                 +-------------------------+

Failover Flow:
1) A 故障 -> Keepalived 检测失败 -> VIP 漂移到 B
2) App 无需改连，仍指向 VIP:10.10.84.10:15810
3) 恢复后可将 VIP 漂回 A（可配置优先级/抢占）

```

#### 建议与要点（与两种拓扑配套）

1.  复制与参数

*   两端：`gtid_mode=ON`，`enforce_gtid_consistency=ON`，`log_bin=ON`，`log_slave_updates=ON`
*   只用 `CHANGE MASTER TO ... MASTER_AUTO_POSITION=1`（GTID 自动定位）

1.  冲突与写入策略

*   双主是**拓扑**，但写入需**逻辑单主**或**按维度分区写**（例如：A 负责奇数用户，B 负责偶数用户；或按库分配）
*   强一致写场景更建议：图 B（主活从备）

1.  健康检查

*   LB/Keepalived 健检命令可用：`mysqladmin ping -h 127.0.0.1 -P 15810` 成功返回 `mysqld is alive`
*   也可执行 SQL 探测：`SELECT 1;`

1.  端口与账号

*   统一监听：`15810`
*   复制用户：`repuser@'%'`（只授复制权限更安全：`REPLICATION SLAVE, REPLICATION CLIENT`）

***

# 二、Keepalived 自定义安装 (tar.gz 源码编译)

## 1. 前置条件

### 1.1 系统环境

*   OS: BigCloud Enterprise Linux 21.10 (LTS-SP2)
*   角色：`10.10.84.249`、`10.10.84.254`
*   权限：root

### 1.2 依赖安装

```shell
yum install -y gcc gcc-c++ make autoconf automake libtool \
               openssl openssl-devel libnl3 libnl3-devel \
               libnfnetlink-devel ipvsadm psmisc

```

> *   `openssl-devel`：支持加密认证
> *   `libnl3-devel`：支持 netlink 通信
> *   `libnfnetlink-devel`：部分防火墙交互功能
> *   `ipvsadm`：如需 LVS 功能

***

## 2. 获取源码包

### 2.1 下载

```shell
wget https://www.keepalived.org/software/keepalived-2.2.8.tar.gz 

```

（版本号可替换为最新稳定版）

### 2.2 解压

```shell
cd /data/keepalived
tar -xzf keepalived-2.2.8.tar.gz
cd keepalived-2.2.8

```

***

## 3. 编译与安装

### 3.1 配置编译参数

```shell
./configure --prefix=$HOME/keepalived --disable-libnl --without-systemd --sysconf=/etc

```

*   `--prefix`：安装目录
*   `--disable-libnl`：如果缺少 netlink 开发包，可以禁用
*   `--without-systemd`：不使用 systemd
*   `--sysconf`：配置文件路径（默认 `/etc/keepalived/keepalived.conf`）
*   `--with-init=systemd`：生成 systemd service 文件

### 3.2 编译

```shell
make -j$(nproc)

```

### 3.3 安装

```shell
make install

```

***

## 4. 配置文件

### 4.1 目录结构

```
$HOME/keepalived/
├── etc/
│   └── keepalived/
│       └── keepalived.conf
├── sbin/
│   └── keepalived

```

### 4.2 创建配置目录

```
mkdir -p $HOME/keepalived/etc/keepalived

```

### 4.3 示例配置 `keepalived.conf`

    vrrp_instance VI_1 {
        state MASTER
        interface ens192              # 修改为实际网卡
        virtual_router_id 51
        priority 120
        advert_int 1
        authentication {
            auth_type PASS
            auth_pass 123456
        }
        virtual_ipaddress {
            10.10.84.10/24
        }
    }

### 4.4 配置文件详解

以广西vip为例

```shell
dftdb1:/root# cat /usr/local/etc/keepalived/keepalived.conf
! Configuration File for keepalived

global_defs {
    router_id mysql_ha
}

vrrp_script chk_mysql {
    script "/data/cdphadoop/mysql/mysql_scripts/check_mysql.sh"
    interval 10
}

vrrp_sync_group VG1 {
    group {
        VI_1
    }
}

vrrp_instance VI_1 {
    state BACKUP
    interface bond0
    virtual_router_id 51
    priority 100
    advert_int 1
    nopreempt
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    unicast_src_ip 当前机器ip
    unicast_peer { 
        要切换的机器ip
    }
    virtual_ipaddress {
        172.20.187.41
    }
    track_script {
        chk_mysql
    }
    notify_master /data/cdphadoop/mysql/mysql_scripts/master.sh
    notify_stop /data/cdphadoop/mysql/mysql_scripts/stop.sh
}
```

#### 1) `global_defs`

```shell
global_defs {
    router_id mysql_ha
}

```

*   **router\_id**：本机的 Keepalived 标识（仅用于日志与区分节点），同一台机器内唯一即可，不要求与对端一致。
*   与 VRRP 协议不直接相关，不影响选主，但有助于日志定位。

***

#### 2) `vrrp_script` 与 `track_script`

```shell
vrrp_script chk_mysql {
    script "/data/cdphadoop/mysql/mysql_scripts/check_mysql.sh"
    interval 10
}
...
track_script {
    chk_mysql
}

```

*   **作用**：定义一段**健康检查脚本**（这里用于检测 MySQL 健康），并在实例里跟踪它的结果。
*   **script**：脚本路径；要求**返回码 0 表示健康**，非 0 表示失败。
*   **interval 10**：每 10 秒执行一次健康检查。
*   **行为**：当 `track_script` 引用的脚本返回失败时，实例会被判定为**不健康**，通常会触发降级或进入 FAULT，从而**释放 VIP** 并执行 `notify_stop`（具体行为也取决于是否配置了 `weight`、`rise/fall` 等项；此处未配置权重，常见做法是失败即触发降级/切换）。
*   **常见做法**：`check_mysql.sh` 里用 `mysqladmin ping`、`SELECT 1`、或检查复制延迟等；脚本尽量**快速**、**稳定**，避免误判。

> 小贴士：如果你希望“失败只减优先级、不立刻切换”，可在 `vrrp_script` 里加 `weight -20`、`rise`/`fall`；本文配置是**失败即触发切换**的典型风格。

***

#### 3) `vrrp_sync_group`（组同步）

```shell
vrrp_sync_group VG1 {
    group {
        VI_1
    }
}

```

*   **作用**：把多个 `vrrp_instance` 组成一个**同步组**，组内任一实例切换，其他实例一起联动（保持同起同落）。
*   **当前配置**：只有一个实例 `VI_1`，因此**功能等同无组**，但保留此块便于未来扩展（例如增加第二个 VIP、第二个实例时可同步切换）。

***

#### 4) `vrrp_instance VI_1`（核心）

##### 4.1 基本身份与接口

```shell
state BACKUP
interface bond0
virtual_router_id 51
priority 100
advert_int 1
nopreempt

```

*   **state BACKUP**：本机**以备机身份启动**（不是强制最终状态）。

    *   启动后，如果检测不到 MASTER 广播，备机会参与选举并可能成为 MASTER。
    *   对端通常配 `state MASTER`（或也是 BACKUP 但更高优先级）。
*   **interface bond0**：VRRP 绑定的**物理/逻辑网卡**（这里是聚合口 bond0）。VIP 将挂在这个接口上。
*   **virtual\_router\_id 51**：VRID（虚拟路由器 ID），**集群内必须一致**。

    *   同一二层广播域内，VRID 冲突会导致混乱。
*   **priority 100**：本实例的**优先级**，数值越大越容易当选 MASTER。

    *   在有 `nopreempt` 时，优先级主要影响**首次选举**；一旦产生 MASTER，后续恢复的更高优先级备机**不会抢回**。
*   **advert\_int 1**：MASTER 广播周期（秒）。备机以此间隔监听广告包；

    *   典型故障检测时间约为 **3× advert\_int** 左右（VRRP 规范的 Master\_Down\_Interval 计算还会考虑优先级等因素，实际约 \~3 秒级别）。
*   **nopreempt**：**不抢占**。一旦本机成为 BACKUP，则即使本机优先级更高、对端（MASTER）恢复，也**不会主动抢回 VIP**。

    *   作用：避免频繁“回切”，提升稳定性。
    *   如果你希望 MASTER 恢复后 VIP 回到 MASTER，需要去掉 `nopreempt`（或在对端配置 `nopreempt` 由其保持不回切）。

##### 4.2 认证与单播

```shell
authentication {
    auth_type PASS
    auth_pass 1111
}
unicast_src_ip 当前机器ip
unicast_peer {
    要切换的机器ip
}

```

*   **authentication PASS**：VRRP 的**简单口令**认证（明文），必须与对端一致；只起到“避免误配”的作用，**非加密安全手段**。
*   **unicast\_src\_ip / unicast\_peer**：VRRP 的**单播模式**（常用于不支持组播的网络）。

    *   `unicast_src_ip`：本机发送 VRRP 报文的源 IP（填“当前机器 ip”）。
    *   `unicast_peer`：对端的 IP 列表（这里只有一个“要切换的机器 ip”）。
    *   两端必须**对称配置**：A 的 peer 写 B；B 的 peer 写 A；VRID、auth 等也需一致。

> 若网络支持组播，可不写这两项，使用默认组播（需要网络设备放通组播协议 112）。

##### 4.3 虚拟 IP（VIP）

```shell
virtual_ipaddress {
    172.20.187.41
}

```

*   **VIP 列表**：本实例要管理的虚拟 IP。
*   **绑定接口**：会挂载到 `interface bond0` 指定的接口上。
*   **掩码**：未写掩码时，Keepalived 通常**继承主接口的掩码**；为了明确，实际生产建议写成 `172.20.187.41/24 dev bond0`（但当前写法也能工作）。

> 建议：为减少 ARP 缓存陈旧带来的“短暂不可达”，可以在实例里增加 GARP 参数（见文末“优化建议”）。

##### 4.4 通知脚本（状态回调）

```shell
notify_master /data/cdphadoop/mysql/mysql_scripts/master.sh
notify_stop   /data/cdphadoop/mysql/mysql_scripts/stop.sh

```

*   **notify\_master**：当本机**成为 MASTER**时调用的脚本。

    *   典型用途：

        *   设置 MySQL 为可写：`SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;`
        *   开启对外服务、发布节点为主等。
*   **notify\_stop**：当本机实例**停止/故障/放弃**时调用。

    *   典型用途：

        *   设置 MySQL 为只读：`SET GLOBAL super_read_only=ON; SET GLOBAL read_only=ON;`
        *   释放资源、关闭对外服务等。

> 结合前面的 `track_script`，当 MySQL 健康检查失败时，实例会放弃 VIP 并触发 `notify_stop`，从而把数据库置为只读，避免“故障节点仍对外可写”的风险。

***

#### 5) 运行机制：从“启动”到“切换”

1.  **启动阶段**

    *   本机以 `BACKUP` 启动，监听 VRRP 广播（单播模式下接收来自 `unicast_peer` 的报文）。
    *   如对端（MASTER）在发广告，本机保持 `BACKUP`；如对端不可达，备机按优先级参与选举并可能升为 `MASTER`。
2.  **正常巡检**

    *   每 `advert_int=1s` 接收一次对端广告。
    *   每 `interval=10s` 执行一次 `check_mysql.sh` 健康检查。
3.  **成为 MASTER 时**

    *   在 `VI_1` 中：

        *   绑定 VIP `172.20.187.41` 到 `bond0`；
        *   发送 GARP（默认会发，数量与间隔可调）；
        *   调用 `notify_master`（通常把 MySQL 改为可写）。
4.  **发生故障/退出时**

    *   检测不到广告包（对端宕机/网络断开），或本机 `check_mysql.sh` 失败导致放弃主；
    *   释放 VIP，触发 `notify_stop`（通常把 MySQL 改为只读）。
    *   对端接管 VIP，成为 MASTER。
5.  **nopreempt 的影响**

    *   当原 MASTER 恢复时，如果**当前本机已是 MASTER**，则继续持有 VIP，**不回切**；
    *   只有当当前 MASTER 故障/停止时，VIP 才会转移给对端。

***

#### 6) 对端（配套）要点

为了让两边成功配对运行，请确保对端配置与本机**一致/对称**：

*   `virtual_router_id`、`auth_type`、`auth_pass`、`advert_int` 必须一致；
*   `unicast_src_ip` 写本机 IP，`unicast_peer` 写对端 IP（**双向对称**）；
*   优先级（`priority`）可略高于另一侧，作为主从偏好；
*   一侧可写 `state MASTER`，另一侧 `state BACKUP`；
*   双方都建议保留 `nopreempt`，避免频繁回切（或只在你希望“主机恢复必回切”时关闭）。

***

## 5. 启停方式（非 root 用户）

### 5.1 添加环境变量到PATH

```shell

echo 'export PATH=$HOME/keepalived/sbin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### 5.2 启动

```shell
$HOME/keepalived/sbin/keepalived \
  --use-file=$HOME/keepalived/etc/keepalived/keepalived.conf \
  --pid=$HOME/keepalived/keepalived.pid \
  --vrrp

```

参数说明：

*   `--use-file`：指定配置文件路径
*   `--pid`：保存 PID 文件到用户目录
*   `--vrrp`：只启用 VRRP 功能（如不需要 LVS）

### 5.3 后台运行

```shell
nohup $HOME/keepalived/sbin/keepalived \
  --use-file=$HOME/keepalived/etc/keepalived/keepalived.conf \
  --pid=$HOME/keepalived/keepalived.pid \
  --vrrp > $HOME/keepalived/keepalived.log 2>&1 &

```

### 5.4 停止

```shell
kill $(cat $HOME/keepalived/keepalived.pid)

```

### 5.5 常用命令

```shell
# 查看版本
$HOME/keepalived/sbin/keepalived --version

# 启动前台
$HOME/keepalived/sbin/keepalived --use-file=$HOME/keepalived/etc/keepalived/keepalived.conf --vrrp

# 启动后台
nohup $HOME/keepalived/sbin/keepalived --use-file=$HOME/keepalived/etc/keepalived/keepalived.conf --pid=$HOME/keepalived/keepalived.pid --vrrp > keepalived.log 2>&1 &

# 停止
kill $(cat $HOME/keepalived/keepalived.pid)

# systemctl方式启停
systemctl start keepalived
systemctl enable keepalived
systemctl status keepalived

# 查看日志
tail -f keepalived.log
```

***

## 6. 配置文件中的脚本

### 6.1 mysql健康检查脚本

建议先为 `tongtech` (安装mysql的用户) 配置 `~/.my.cnf`（避免脚本中明文密码）：

```shell
[client]
user=root
password=MySecurePass@123
socket=/data/mysql/conf/mysql.sock
```

脚本内容

```shell
#!/usr/bin/env bash
# 文件: /home/tongtech/scripts/check_mysql.sh
# 作用: 给 keepalived 的 vrrp_script 调用进行 MySQL 健康检查
# 返回码: 0=健康；1=mysqld不通；2=复制线程异常；3=复制延迟过大；4=SQL探活失败；9=其他异常
# 依赖: 建议配置 ~/.my.cnf；或设置 MYSQL_AUTH

set -Eeuo pipefail

#########################
# 可调参数
#########################
MYSQL_BASE="/data/mysql/base/bin"
MYSQL_SOCK="/data/mysql/conf/mysql.sock"
MYSQL_ADMIN="${MYSQL_BASE}/mysqladmin"
MYSQL_CLI="${MYSQL_BASE}/mysql"

# 若已配置 ~/.my.cnf 则保持为空即可；否则设置成登录参数或 login-path
# MYSQL_AUTH="-uroot -p'MySecurePass@123'"
# MYSQL_AUTH="--login-path=local"
MYSQL_AUTH=""

# 是否检查复制健康（双主/主从可选）
CHECK_REPLICATION=true
# 允许的复制最大延迟（秒）
MAX_REPLAG=60

# 日志
LOG_DIR="/home/tongtech/scripts/mysql_scripts/logs"
LOG_FILE="${LOG_DIR}/check_mysql.log"
mkdir -p "${LOG_DIR}" || true

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) [INFO] $*"  >> "${LOG_FILE}"; }
warn(){ echo "$(ts) [WARN] $*"  >> "${LOG_FILE}"; }
err() { echo "$(ts) [ERROR] $*" >> "${LOG_FILE}"; }

#########################
# 1) 基础存活探测
#########################
if ! "${MYSQL_ADMIN}" ${MYSQL_AUTH} --socket="${MYSQL_SOCK}" --connect-timeout=2 ping >/dev/null 2>&1; then
  err "mysqladmin ping failed"
  exit 1
fi
log "mysqladmin ping ok"

#########################
# 2) 轻量 SQL 探测
#########################
if ! "${MYSQL_CLI}" ${MYSQL_AUTH} --socket="${MYSQL_SOCK}" -Nse "SELECT 1" >/dev/null 2>&1; then
  err "SQL probe (SELECT 1) failed"
  exit 4
fi
log "SQL probe ok"

#########################
# 3) 复制健康检查（可选）
#########################
if [ "${CHECK_REPLICATION}" = true ]; then
  TMP="/tmp/SLAVE_STATUS.$$"
  if "${MYSQL_CLI}" ${MYSQL_AUTH} --socket="${MYSQL_SOCK}" -e "SHOW SLAVE STATUS\G" > "${TMP}" 2>/dev/null; then
    # 仅当存在 Slave_* 字段时才解析
    if grep -qE '^ *Slave_IO_Running:' "${TMP}"; then
      SIO=$(awk -F': ' '/^ *Slave_IO_Running:/{gsub(/\r/,""); print $2}' "${TMP}" | tr -d ' ')
      SSQ=$(awk -F': ' '/^ *Slave_SQL_Running:/{gsub(/\r/,""); print $2}' "${TMP}" | tr -d ' ')
      SB=$(awk -F': ' '/^ *Seconds_Behind_Master:/{gsub(/\r/,""); print $2}' "${TMP}" | tr -d ' ')
      rm -f "${TMP}"

      if [ "${SIO}" != "Yes" ] || [ "${SSQ}" != "Yes" ]; then
        err "Replication threads abnormal: Slave_IO_Running=${SIO}, Slave_SQL_Running=${SSQ}"
        exit 2
      fi

      if [ "${SB}" = "NULL" ] || [ -z "${SB}" ]; then
        warn "Seconds_Behind_Master is NULL/empty (transient during catch-up?)"
      elif echo "${SB}" | grep -Eq '^[0-9]+$'; then
        if [ "${SB}" -gt "${MAX_REPLAG}" ]; then
          err "Replication lag too high: ${SB}s > ${MAX_REPLAG}s"
          exit 3
        fi
        log "Replication ok, lag=${SB}s"
      else
        warn "Seconds_Behind_Master not numeric: ${SB}"
      fi
    else
      rm -f "${TMP}"
      log "No Slave_* fields found; skipping replication checks (treat as pass)."
    fi
  fi
fi

log "mysql health check passed"
exit 0

```

### 6.2 vip切换时执行的脚本

说明：可选

建议先为 `tongtech` (安装mysql的用户)配置 `~/.my.cnf`（避免脚本中明文密码）：

```shell
[client]
user=root
password=MySecurePass@123
socket=/data/mysql/conf/mysql.sock
```

```shell
#!/usr/bin/env bash
# 文件: /home/tongtech/scripts/master.sh
# 触发: keepalived notify_master
# 行为: 获得 VIP 时切为可写 (super_read_only=OFF, read_only=OFF)

set -Eeuo pipefail

MYSQL_BASE="/data/mysql/base/bin"
MYSQL_SOCK="/data/mysql/conf/mysql.sock"
MYSQL_CLI="${MYSQL_BASE}/mysql"

# MYSQL_AUTH="-uroot -p'MySecurePass@123'"
# MYSQL_AUTH="--login-path=local"
MYSQL_AUTH=""

LOG_DIR="/home/tongtech/scripts/mysql_scripts/logs"
LOG_FILE="${LOG_DIR}/transition.log"
mkdir -p "${LOG_DIR}" || true

RETRIES=3
SLEEP=2

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) [MASTER] $*" | tee -a "${LOG_FILE}"; }

try_set_rw() {
  "${MYSQL_CLI}" ${MYSQL_AUTH} --socket="${MYSQL_SOCK}" -e "SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;"
}

log "VIP gained, switching MySQL to RW..."
for i in $(seq 1 "${RETRIES}"); do
  if try_set_rw; then
    log "Set super_read_only=OFF, read_only=OFF success (attempt ${i})"
    exit 0
  fi
  log "Attempt ${i} failed, retrying after ${SLEEP}s..."
  sleep "${SLEEP}"
done

log "Failed to switch MySQL to RW after ${RETRIES} attempts"
exit 1

```

### 6.3 vip故障时执行的脚本

说明：此脚本可选

建议先为 `tongtech` (安装mysql的用户)配置 `~/.my.cnf`（避免脚本中明文密码）：

```shell
[client]
user=root
password=MySecurePass@123
socket=/data/mysql/conf/mysql.sock
```

```shell
#!/usr/bin/env bash
# 文件: /home/tongtech/scripts/stop.sh
# 触发: keepalived notify_stop
# 行为: 释放 VIP / 故障时切为只读 (super_read_only=ON, read_only=ON)
# 说明: 若 mysqld 已停，则直接退出 0（避免干扰 keepalived 停止流程）

set -Eeuo pipefail

MYSQL_BASE="/data/mysql/base/bin"
MYSQL_SOCK="/data/mysql/conf/mysql.sock"
MYSQL_CLI="${MYSQL_BASE}/mysql"
MYSQL_ADMIN="${MYSQL_BASE}/mysqladmin"

# MYSQL_AUTH="-uroot -p'MySecurePass@123'"
# MYSQL_AUTH="--login-path=local"
MYSQL_AUTH=""

LOG_DIR="/home/tongtech/scripts/mysql_scripts/logs"
LOG_FILE="${LOG_DIR}/transition.log"
mkdir -p "${LOG_DIR}" || true

RETRIES=3
SLEEP=2

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) [STOP] $*" | tee -a "${LOG_FILE}"; }

# mysqld 若不在，直接成功退出
if ! "${MYSQL_ADMIN}" ${MYSQL_AUTH} --socket="${MYSQL_SOCK}" --connect-timeout=2 ping >/dev/null 2>&1; then
  log "mysqld not running, nothing to do."
  exit 0
fi

try_set_ro() {
  "${MYSQL_CLI}" ${MYSQL_AUTH} --socket="${MYSQL_SOCK}" -e "SET GLOBAL super_read_only=ON; SET GLOBAL read_only=ON;"
}

log "Releasing VIP / entering STOP, switching MySQL to RO..."
for i in $(seq 1 "${RETRIES}"); do
  if try_set_ro; then
    log "Set super_read_only=ON, read_only=ON success (attempt ${i})"
    exit 0
  fi
  log "Attempt ${i} failed, retrying after ${SLEEP}s..."
  sleep "${SLEEP}"
done

log "Failed to switch MySQL to RO after ${RETRIES} attempts"
exit 1

```

