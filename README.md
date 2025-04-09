# mysql_install_with_shell

说明：
使用shell脚本方式自动化安装mysql-xxx.tar.xz包
可自定义安装用户，mysql的端口，data目录，base目录等参数
脚本中提供了my.cnf模板，会根据环境自动拼接

使用：
注意：需要提前配置好必须项， mysql_install/conf/mysql_install.conf ,将mysql的tar包放于 mysql_install/package
cd mysql_install/scripts
sh install_mysql.sh