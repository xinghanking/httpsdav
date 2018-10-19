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
HOST_IP=$(hostname -I |awk '{print $1}')    #服务器IP
USER=`whoami`
DAV_USER="$USER"
DAV_PATH="/home/$USER/mycloud"
if [ "$USER" = "root" ]; then
    DAV_USER="webdav"
    DAV_PATH="/home/mycloud"
fi

#安装脚本退出函数
install_exit() {
    export LC_ALL="$OLD_LC_ALL"
    unset $DAV_USER
    exit 0;
}

#安装依赖组件
prepare_install() {
    if [ "$USER" = "root" ]; then
        yum -y install httpd mod_dav* mod_ssl openssl
        return 0
    fi
    return 1
}

#创建程序运行用户
create_dav_user() {
    if ( ! id $DAV_USER >& /dev/null 2>&1 ); then
   	    useradd -s /sbin/nologin -M $DAV_USER
	    DAV_GROUP="$DAV_USER"
    else
        DAV_GROUP=`id -g -n $DAV_USER`
		DAV_GROUP=${DAV_GROUP[0]}
    fi
    chown -R $DAV_USER:$DAV_GROUP $DAV_PATH	
}

#安装条件检查函数
check_install_conditions() {
   if ( ! type httpd >/dev/null 2>&1 && ! prepare_install ); then
       echo '没有安装httpd或缺少执行权限'
       echo '请先用管理员账号执行'
       echo '    yum -y install httpd mod_dav_fs mod_ssl'
       echo '安装相关组建或给当前账号添加httpd的执行权限'
       install_exit
   fi
   if [ ! -e "/etc/httpd/modules/mod_dav.so" -o ! -e "/etc/httpd/modules/mod_ssl.so" ] && ! prepare_install ; then
       echo '没有安装apache的model_dav模块或mod_ssl模块'
       echo '请先用管理员账号执行'
       echo '    yum -y install mod_dav* mod_ssl'
       echo '安装相应模块'
       install_exit
   fi
   if ( ! type openssl >/dev/null 2>&1 && ! prepare_install ); then
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
    
    echo -n "请输入你要启用的端口(默认：$DEFAULT_PORT)："
    checknum=3
    while [ $checknum -ge 0 ]
    do
        read webdav_port
        webdav_port=${webdav_port:=$DEFAULT_PORT}
        note_text="输入错误，请重新输入："
        if [ $webdav_port -ge 0 >& /dev/null 1>&2 ]; then
            if [ $webdav_port -le 8000 -o $webdav_port -ge 65535 ]; then
                note_text='请选择 8000 ~ 65535 之间的端口号：'
            elif [[ ! `netstat -anlt | grep ":$webdav_port .*LISTEN"` ]]; then
                break
            else
                note_text="端口号已被占用，请指定其它端口号输入："
            fi
        fi
        if  [ $checknum -eq 1 ]; then
            echo "多次输入错误，安装中止退出"
            install_exit
        fi
        let "checknum--"
        echo -n $note_text
    done
	
    checknum=3
    note_text="请输入webdav目录的服务器路径(默认：$DAV_PATH): "
    while [ $checknum -ge 0 ]
    do
        if [ $checknum -eq 0 ]; then
           echo "多次输入错误，安装程序退出"
           install_exit
        fi
        read -p $note_text webdav_path
        if [ -z $webdav_path ]; then
            mkdir -p $DAV_PATH
			if [ "$USER" = "root" ]; then
			    create_dav_user
			fi
            webdav_path="$DAV_PATH"
            chmod 700 $webdav_path
            break	
        fi
        note_text="输入错误或没有rwx权限，请重新输入："
        webdav_root_path=`dirname $webdav_path`
        if [[ "$webdav_root_path" = '.' ]]; then
            note_text="请使用绝对路径，重新输入："
            let "checknum--"
            continue
        fi
        path_base_name=`basename $webdav_path`
        if ( [ "$webdav_root_path" = "/" ] || ( [ "$webdav_root_path" = "/home" ] && [ "$path_base_name" = "root" ] ) ); then
           note_text="目录不允许使用，请重新输入："
           let "checknum--"
           continue
        elif [ ! -e $webdav_path -a -r $webdav_root_path -a -w $webdav_root_path -a -x $webdav_root_path ]; then
            mkdir -p $webdav_path
            DAV_PATH="$webdav_path"
            chmod 700 $webdav_path
        fi
        if [ -d $webdav_path -a -r $webdav_path -a -w $webdav_path -a -x $webdav_path ]; then
            if [ "$USER" != "root" ]; then
                break
            elif [ -s $webdav_path ]; then
                if [ "$webdav_root_path"="/home" ]; then
                    DAV_USER="$path_base_name"
                fi
                create_dav_user
                break
            else
                note_text="不允许使用root用户的非空目录，请重新输入"
            fi
        fi
        let "checknum--"
    done
	
    read -p "请输入你要设置的身份认证登录名(默认:$DAV_USER): " wedav_login
    webdav_login=${webdav_login:=$DAV_USER}
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
    mkdir -p $HTTPSDAV_ROOT/var/{subsys,dav}
    mkdir -p $HTTPSDAV_ROOT/conf/davs
    echo -e $succ_txt

    echo -n "    创建用户登录身份认证文件 --------------------------------------"
    auth_file="$HTTPSDAV_ROOT/conf/davs/.$dav_name"
	if  ( ! $(htpasswd -nb $webdav_login $webdavpwd > $auth_file)>/dev/null 2>&1 ); then
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
    echo "User $DAV_USER" >> $httpsdavconf
    echo "Group $DAV_GROUP" >> $httpsdavconf
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
