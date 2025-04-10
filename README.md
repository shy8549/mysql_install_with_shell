# mysql_install_with_shell

# MySQL 自动化安装脚本

## 📖 说明

本项目使用 Shell 脚本的方式实现自动化安装 `mysql-xxx.tar.xz` 安装包，支持以下参数的自定义配置：

- 安装用户
- MySQL 端口
- 数据目录（`data`）
- 安装目录（`base`）

脚本内已提供了 `my.cnf` 模板，基于 **MySQL 8.0.35** 版本配置，并会根据实际部署环境自动拼接生成最终配置文件。

---

## 🚀 使用方式

> ⚠️ 注意：请在执行脚本前确保已配置好必要项！

### 1. 配置文件

请提前编辑以下配置文件：

mysql_install/conf/mysql_install.conf

### 2. 准备安装包

将你下载的 mysql-xxx.tar.xz 安装包（如 mysql-8.0.35-linux-glibc2.28-x86_64.tar.xz）放入 mysql_install/package/ 目录

### 3. 执行安装脚本

cd mysql_install/scripts
sh install_mysql.sh
