#!/bin/bash
#安装文件
#作者：刘重量 Email:13439694341@qq.com

#执行前初始化环境设置
set -e
set -E
trap 'echo "Fail unexpectedly on ${BASH_SOURCE[0]}:$LINENO!" >&2' ERR

OLD_LC_ALL=${LC_ALL:-""}                    #保存原来的语言编码
export LC_ALL="zh_CN.UTF-8"                 #设置界面显示语言及编码
HTTPSDAV_ROOT=$(readlink -f `dirname "$0"`) #获取安装目录路径
DEFAULT_PORT=8443                           #默认启动端口号
HOST_IP=$(hostname -I |awk '{print $1}')     #服务器IP

#安装脚本退出函数
install_exit() {
    export LC_ALL="$OLD_LC_ALL"
    exit 0;
}

#安装条件检查函数
check_install_conditions() {
   if (!type httpd >/dev/null 2>&1); then
       echo '没有安装httpd或缺少执行权限'
       echo '请先用管理员账号执行'
       echo '    yum -y install httpd mod_dav_fs mod_ssl'
       echo '安装相关组建或给当前账号添加httpd的执行权限'
       install_exit
   fi
   if test ! -e "/etc/httpd/modules/mod_dav.so" -o ! -e "/etc/httpd/modules/mod_ssl.so" 
   then
       echo '没有安装apache的model_dav模块或mod_ssl模块'
       echo '请先用管理员账号执行'
       echo '    yum -y install mod_dav* mod_ssl'
       echo '安装相应模块'
       install_exit
   fi
   if (!type openssl >/dev/null 2>&1); then
       echo '没有安装openssl或缺少执行权限, 请先用管理员账号执行'
       echo '    yum -y install openssl'
       echo '安装openssl 或者给当前账号添加openssl的执行权限'
       install_exit
   fi    
}

#安装httpsdav函数
httpsdav_install() {
    echo -e "\e[1m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\e[;36m 开始安装httpsdav \e[;0m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\n"
    chmod -R 700 $HTTPSDAV_ROOT    #给安装目录权限
    user=`whoami`  #获取当前用户名
    note_text="请输入你要启用的端口(默认:$DEFAULT_PORT): "
    checknum=3
    while(( $checknum > 0 ))
    do
        read -p $note_text webdav_port
        webdav_port=${webdav_port:=$DEFAULT_PORT}
        if [[ $webdav_port =~ ^[1-9]+$ ]]; then
            if (( $webdav_port < 8000 || $webdav_port > 65535)); then
                note_text="请选择 8000 ~ 65535 之间的端口号"
            elif [[ ! `netstat -anlt | grep ":$webdav_port .*LISTEN"` ]]; then
                break
            else
                note_text="端口号已被占用，请选择其它端口号输入："
            fi
        elif (( $checknum == 1 )); then
            echo "多次输入错误，安装中止退出"
            install_exit
        else
            note_text="输入错误，请重新输入："
        fi
        let "checknum--"
    done
	
    checknum=3
    if [ -w $HOME -a -x $HOME ]; then
        default_dav_path="$HOME/webdav_disk"
    else
        default_dav_path="/tmp/webdav_disk"
    fi
    note_text="请输入webdav目录的服务器路径(默认:$default_dav_path): "
    while(( $checknum > 0 ))
    do
        read -p $note_text webdav_path
        if test -z $webdav_path
        then
            webdav_path=$default_dav_path
            mkdir -p $webdav_path
            chmod 700 $webdav_path
        fi
        if test -r $webdav_path -a -w $webdav_path -a -x $webdav_path
        then
           checknum=0
        elif (( $checknum == 1 )); then
           install_exit
        else
           note_text="输入错误或没有rwx权限，请重新输入："
           let "checknum--"
        fi
    done
    read -p "请输入你要设置的身份认证登录名(默认:$user): " wedav_login
    webdav_login=${webdav_login:=$user}
    read -p "请设置访问密码: " webdavpwd
    if test -z $webdavpwd
    then
        webdavpwd=$(openssl rand -base64 4)
    fi
    succ_txt="> \e[1;33m[\e[;32m成功\e[;33m]\e[;0m"
    dav_name=${dav_name:='webdav'}
    echo -e "\n执行安装:\n"

    echo -n "    构建httpsdav的目录结构 ----------------------------------------"
    mkdir -p $HTTPSDAV_ROOT/{bin,var,logs,run}
    mkdir -p $HTTPSDAV_ROOT/var/subsys
    mkdir -p $HTTPSDAV_ROOT/conf/davs
    echo -e $succ_txt

    echo -n "    创建用户登录身份认证文件 --------------------------------------"
    auth_file="$HTTPSDAV_ROOT/conf/davs/.$dav_name"
	if  (!$(htpasswd -nb $webdav_login $webdavpwd > $auth_file)>/dev/null 2>&1); then
		echo "${webdav_login}:$(openssl passwd -crypt $webdavpwd)" > $auth_file
    fi
    echo -e $succ_txt

    echo -n "    生成SSL证书 ---------------------------------------------------"
    . $HTTPSDAV_ROOT/scripts/create_certs.sh > $HTTPSDAV_ROOT/logs/create_ssl.log 2>&1
    echo -e $succ_txt 

    echo -n "    构建httpsdav的配置文件 ----------------------------------------"
    httpsdavconf="$HTTPSDAV_ROOT/conf/httpsdav.conf" 
    echo "ServerName $HOSTNAME" > $httpsdavconf
    echo "Listen $webdav_port" >> $httpsdavconf
    echo "User $user" >> $httpsdavconf
    group=(`groups`)
    group=${group[0]}
    echo "Group $group" >> $httpsdavconf
    echo "<VirtualHost $HOST_IP:$webdav_port>" >> $httpsdavconf
    cat $HTTPSDAV_ROOT/conf/.tpl/httpsdav.conf >> $httpsdavconf
    echo -e $succ_txt

    echo -n "    创建本次安装httpsdav服务的第一个webdav站点 --------------------"
    webdav_name=${dav_name:='webdav'}
    echo "Alias /$webdav_name \"$webdav_path\"" > $HTTPSDAV_ROOT/conf/davs/$dav_name.conf
    echo "<Directory \"$webdav_path\">" >> $HTTPSDAV_ROOT/conf/davs/$dav_name.conf
    echo "   AuthUserFile \"conf/davs/.$dav_name\"" >> $HTTPSDAV_ROOT/conf/davs/$dav_name.conf
    cat $HTTPSDAV_ROOT/conf/.tpl/webdav.conf >> $HTTPSDAV_ROOT/conf/davs/$dav_name.conf
    httpd_path=`which httpd`
    httpd_path=${httpd_path%%:*}
    rm -fr $HTTPSDAV_ROOT/bin/httpsdav
    ln -s $httpd_path $HTTPSDAV_ROOT/bin/httpsdav
    echo -e $succ_txt

    echo -e -n "\n启动你的webdav站点 ------------------------"	                                 
    $HTTPSDAV_ROOT/bin/httpsdav -C "ServerRoot $HTTPSDAV_ROOT" -f $HTTPSDAV_ROOT/conf/httpsdav.conf --pidfile=$HTTPSDAV_ROOT/run/httpsdav.pid
    echo -e "\e[5;32m 成功！\e[25m\n"
    mv $HTTPSDAV_ROOT/conf/.tpl/systemctl_httpsdav.sh $HTTPSDAV_ROOT/systemctl_httpsdav.sh
    echo "$HTTPSDAV_ROOT" > $HTTPSDAV_ROOT/.install_lock

    echo -e "\n\e[1;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\e[;32m 安装完成 \e[;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\n\e[;0m"
    echo "    欢迎使用httpsdav"
    echo "    你的httpsdav(使用SSL加密通道的webdav服务，即ssl+webdav)站点信息："
    echo "    访问地址：https://$HOST_IP:$webdav_port/$webdav_name"
    echo "    映射目录: $webdav_path/"
    echo "    登录名称：$webdav_login"
    echo "    验证密码：$webdavpwd"
    echo "    你可以在当前目录下执行 ./systemctl_httpsdav.sh start|stop|reload|restart "
    echo "        ./systemctl_httpsdav.sh start|stop|reload|restart"
    echo "    的命令对本机的httpsdav服务程序进行 启动|关闭|重载|重启 的操作"
    echo "    如果你有安装中遇到什么问题或有什么建议和需求，或者使用httpsdav中遇到了什么问题"
    echo "    可以联系我：刘重量;  Email:13439694341@qq.com"
    echo -e "\n\e[1;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊ \e[;32m 祝你生活愉快 \e[;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\e[0m\n\n"
    rm -fr $HTTPSDAV_ROOT/install.sh
    return 0
}

if [[ -s "$HTTPSDAV_ROOT/.install_lock" ]]; then
    echo '你已经安装过了'
else
    check_install_conditions
    httpsdav_install
fi
install_exit