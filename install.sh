#!/bin/bash
#安装文件
#作者：刘重量 Email:13439694341@qq.com

#执行前初始化环境设置
set -e
set -E
trap 'echo "Fail unexpectedly on ${BASH_SOURCE[0]}:$LINENO!" >&2' ERR

OLD_LC_ALL=${LC_ALL:-""}                    #保存原来的语言编码
OLD_HOME="$HOME"                            #原来的用户主目录
export LC_ALL="zh_CN.UTF-8"                 #设置界面显示语言及编码
HTTPSDAV_ROOT=$(readlink -f `dirname "$0"`) #获取安装目录路径
DEFAULT_PORT=8443                           #默认启动端口号
HOST_IP=$(hostname -I |awk '{print $1}')    #服务器IP
USER=`whoami`								#用户名
DAV_USER="$USER"                            #httpsdav的运行用户
USER_HOME=${HOME:-"/home/$USER"}			#安装用户主目录
IS_INSTALLED="n"                            #是否已经安装过了且在运行；默认否

#获取当前客户端访问所使用的服务器主机IP
CONNECTION_IPS=($SSH_CONNECTION)
if [[ -n ${CONNECTION_IPS[0]} && -n ${CONNECTION_IPS[2]} && ${CONNECTION_IPS[0]} != ${CONNECTION_IPS[2]} ]]; then
    HOST_IP="${CONNECTION_IPS[2]}"
fi

if [ "$USER" = "root" ]; then
    DAV_USER="webdav"
	HOME="/home/$DAV_USER"
    if ( id $DAV_USER >& /dev/null 2>&1 ); then
	    DAV_GROUP=(`id -g -n $USER`)
        DAV_GROUP=${DAV_GROUP[0]}
		HOME=`grep "^$DAV_USER:" /etc/passwd|awk -F [:] '{print $6}'`
	fi
else
    DAV_USER="$USER"
    DAV_GROUP=(`id -g -n $USER`)
    DAV_GROUP=${DAV_GROUP[0]}	
fi
USER_HOME="/home/$DAV_USER"
if [ -d /home/users/$DAV_USER ]; then
    USER_HOME="/home/users/$DAV_USER"	
fi
USER_HOME=${HOME:-$USER_HOME}
DAV_PATH="$USER_HOME/mycloud"               #httpsdav的站点目录

#安装脚本退出函数
install_exit() {
    export LC_ALL="$OLD_LC_ALL"
	export HOME="$OLD_HOME"
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
    mkdir -p $USER_HOME
    useradd -s /bin/bash -M $DAV_USER
    DAV_GROUP=(`id -g -n $DAV_USER`)
	DAV_GROUP=${DAV_GROUP[0]}
    chown $DAV_USER:$DAV_GROUP $USER_HOME
    chmod 700 $USER_HOME
    usermod -d $USER_HOME $DAV_USER
}

#检查是否已安装过
check_installed() {
    IS_INSTALLED="n"
    if [ -f $HTTPSDAV_ROOT/run/httpsdav.pid ]; then
        IS_INSTALLED="y"
    elif [ -f $USER_HOME/httpsdav/run/httpsdav.pid -a $USER = "root" ]; then
        IS_INSTALLED="y"
    fi
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
    if [ $USER != "root" ]; then
        check_installed
        if [ "$IS_INSTALLED" = "y" ]; then
            echo "你已经安装过了，且站点在运行中"
            install_exit
        fi
    fi
}

#安装httpsdav函数
httpsdav_install() {
    echo -e "\e[1m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\e[;36m 开始安装httpsdav \e[;0m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\n"
    chmod -R 700 $HTTPSDAV_ROOT    #给安装目录权限

    checknum=3
    note_text="请输入位于用户目录下的webdav目录的服务器路径(值如默认：$DAV_PATH): "
    while [ $checknum -ge 0 ]
    do
        read -p $note_text webdav_path
        if [ -z $webdav_path ]; then
            if [ "$USER" = "root" ]; then
                check_installed
                if [ "$IS_INSTALLED" = "y" ]; then
                    echo "你已经为默认用户$DAV_USER安装过了,且站点在运行中，为其它用户安装吧？"
                    continue
                elif ( ! id $DAV_USER >& /dev/null 2>&1 ); then
                    create_dav_user
                fi  
                su $DAV_USER -c "mkdir -p $DAV_PATH"
            else  
                mkdir -p $DAV_PATH
			fi
            webdav_path="$DAV_PATH"
            chmod 700 $webdav_path
            break
        fi
        if [[ "$webdav_path" =~ ^/home/[_a-zA-Z0-9\-]+/[^/].* ]]; then
            compare_path=${webdav_path:6}
			compare_home="/home/"
			if [[ "$webdav_path" =~ ^/home/users/[_a-zA-Z0-9\-]+/[^/].* ]]; then
				compare_path=${webdav_path:12}
				compare_home="/home/users/"
			fi
            DAV_USER=${compare_path%%/*}
			USER_HOME="$compare_home/$DAV_USER"
            if [ $USER = "root" ]; then
                if [ -d $webdav_path ]; then
                    OWNER=`ls -ld $webdav_path|awk '{print $3}'`
                    if [ "$OWNER" = "root" ]; then
                        note_txt="不能使用所属用户为root的目录，请重新输入："
                        let "checknum--"
                    fi
                    if ( id $OWNER >& /dev/null 2>&1 ); then
                        DAV_USER="$OWNER"
                        DAV_GROUP=`id -g -n $DAV_USER`
                        DAV_GROUP=${DAV_GROUP[0]}
                        owner_home=`grep "^$DAV_USER:" /etc/passwd|awk -F [:] '{print $6}'`
                        USER_HOME=${owner_home:-$USER_HOME}
                    else
                        create_dav_user
                    fi
                    check_installed
                    if [ "$IS_INSTALLED" = "y" ]; then
                        note_text="你已经为该用户安装过了，且站点在运行中，请换属于其他用户目录输入："
                        continue
                    fi
                    chmod -R 700 $webdav_path
                    break
                else
                    OWNER="$DAV_USER"
	                if [ -d $USER_HOME ]; then
			            OWNER=`ls -ld $USER_HOME|awk '{print $3}'`
				    fi
                    if [[ -n "$OWNER" && "$OWNER" != "root" ]]; then
                        if ( id $OWNER >& /dev/null 2>&1 ); then
                            DAV_USER="$OWNER"
                            DAV_GROUP=`id -g -n $DAV_USER`
                            DAV_GROUP=${DAV_GROUP[0]}
                            owner_home=`grep "^$DAV_USER:" /etc/passwd|awk -F [:] '{print $6}'`
                            USER_HOME=${owner_home:-$USER_HOME}
                            check_installed
                            if [ "$IS_INSTALLED" = "y" ]; then
                                note_text="你已经为该用户安装过了，且站点在运行中，请换属于其他用户目录输入:"
                                continue
                            fi
                        else
                            create_dav_user
                        fi
                        if ( su $DAV_USER -c "mkdir -p $webdav_path" >& /dev/null 2>&1 ); then
                            DAV_PATH="$webdav_path"
                            chmod 700 $webdav_path
                            break
                        fi
				    fi
                fi
            else
                [ ! -d $webdav_path ] && ( mkdir -p $webdav_path >& /dev/null 2>&1 ) && ( chmod 700 $webdav_path )
                if [ -d $webdav_path -a -r $webdav_path -a -w $webdav_path -a -x $webdav_path ]; then
                    break
                fi
            fi
        fi
        if [ $checknum -eq 0 ]; then
           echo "多次输入错误，安装程序退出"
           install_exit
        fi
        note_text="路径不支持或没有rwx权限，请重新输入："
        let "checknum--"
    done
	
	echo -n "请输入你要启用的端口(默认：$DEFAULT_PORT)："
    checknum=3
    while [ $checknum -ge 0 ]
    do
        read webdav_port
        webdav_port=${webdav_port:=$DEFAULT_PORT}
        note_text="输入错误，请重新输入："
        if [ $webdav_port -ge 0 >& /dev/null 1>&2 ]; then
            if [ $webdav_port -le 8000 -o $webdav_port -ge 9000 ]; then
                note_text='请选择 8000 ~ 9000 之间的端口号：'
            elif [[ ! `netstat -anlt | grep ":$webdav_port .*LISTEN"` ]]; then
                break
            else
                note_text="端口号已被占用，请指定其它端口号输入："
            fi
        fi
        if  [ $checknum -eq 0 ]; then
            echo "多次输入错误，安装中止退出"
            install_exit
        fi
        let "checknum--"
        echo -n $note_text
    done

    read -p "请输入你要设置的身份认证登录名(默认:$DAV_USER): " webdav_login
    webdav_login=${webdav_login:-$DAV_USER}
    read -p "请设置访问密码: " webdavpwd
    if test -z $webdavpwd
    then
        webdavpwd=$(openssl rand -base64 4)
    fi

    succ_txt="> \e[1;33m[\e[;32m成功\e[;33m]\e[;0m"
    dav_name=${dav_name:='webdav'}

    echo -e "\n执行安装:\n"

    echo -n "    构建httpsdav的目录结构 ----------------------------------------"
    if [ "$USER" = "root" ]; then
        mkdir -p $USER_HOME/httpsdav
        mkdir -p $USER_HOME/httpsdav/conf/.tpl
        cp -R $HTTPSDAV_ROOT/scripts $USER_HOME/httpsdav/scripts
        cp -R $HTTPSDAV_ROOT/conf/.tpl/* $USER_HOME/httpsdav/conf/.tpl/
        cp -R $HTTPSDAV_ROOT/conf/httpd.conf $USER_HOME/httpsdav/conf/httpd.conf
        HTTPSDAV_ROOT="$USER_HOME/httpsdav"
    fi
    mkdir -p $HTTPSDAV_ROOT/{bin,var,logs,run,sslcache}
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
    . $HTTPSDAV_ROOT/scripts/create_certs.sh -u $DAV_USER > $HTTPSDAV_ROOT/logs/create_ssl.log 2>&1
    echo -e $succ_txt

    echo -n "    构建httpsdav的配置文件 ----------------------------------------"
	APPACHE_VERSION=(`httpd -v|awk -F '.' '{print $2}'`)
	APPACHE_VERSION=${APPACHE_VERSION[0]}
	if [ $APPACHE_VERSION -eq 2 ]; then
		APPACHE_VERSION="2-2"                   #httpd版本
	elif [ $APPACHE_VERSION -eq 4 ]; then
		APPACHE_VERSION="2-4"
	elif [ -f /etc/httpd/conf/httpd.conf ]; then
		modules_conf="$HTTPSDAV_ROOT/conf/.tpl/modules-x.conf"
		cat /etc/httpd/conf/httpd.conf|sed -n '/LoadModule /p' > $modules_conf
		sed -i 's/modules\/\/etc\/httpd\/modules\//g' $modules_conf
		APPACHE_VERSION="x"
	fi
    modulesconf="$HTTPSDAV_ROOT/conf/.tpl/modules-${APPACHE_VERSION}.conf"
    cat $modulesconf > $HTTPSDAV_ROOT/conf/modules.conf
    echo "SSLEngine Off" > $HTTPSDAV_ROOT/conf/ssl.conf
    cat $HTTPSDAV_ROOT/conf/.tpl/client.conf > $HTTPSDAV_ROOT/conf/client.conf
    httpsdavconf="$HTTPSDAV_ROOT/conf/httpsdav.conf"
    echo "ServerName $HOSTNAME" > $httpsdavconf
    echo "Listen $webdav_port" >> $httpsdavconf
    echo "User $DAV_USER" >> $httpsdavconf
    echo "Group $DAV_GROUP" >> $httpsdavconf
    echo "Include conf/httpd.conf" >> $httpsdavconf
    echo "SSLSessionCache dbm:$HTTPSDAV_ROOT/sslcache/sslcache" >> $httpsdavconf
    echo "<VirtualHost $HOST_IP:$webdav_port>" >> $httpsdavconf
	echo "    ServerName $HOST_IP" >> $httpsdavconf
	echo "    DocumentRoot $HTTPSDAV_ROOT/var/dav" >> $httpsdavconf
    cat $HTTPSDAV_ROOT/conf/.tpl/httpsdav.conf >> $httpsdavconf
    echo -e $succ_txt

    echo -n "    创建本次安装httpsdav服务的第一个webdav站点 --------------------"
    webdav_name=${dav_name:='webdav'}
    davconf="$HTTPSDAV_ROOT/conf/davs/$dav_name.conf"
    echo "Alias /$webdav_name \"$webdav_path\"" > $davconf
    echo "<Directory \"$webdav_path\">" >> $davconf
    echo "   AuthUserFile \"conf/davs/.$dav_name\"" >> $davconf
    cat $HTTPSDAV_ROOT/conf/.tpl/webdav.conf >> $davconf
    httpd_path=`which apachectl`
    httpd_path=${httpd_path%%:*}
    rm -fr $HTTPSDAV_ROOT/bin/httpsdav
    ln -s $httpd_path $HTTPSDAV_ROOT/bin/httpsdav
    chown -R $DAV_USER:$DAV_GROUP $HTTPSDAV_ROOT
    chmod -R 700 $HTTPSDAV_ROOT
    echo -e $succ_txt

    echo -e -n "\n启动你的webdav站点 ------------------------"
    cmdstart="$HTTPSDAV_ROOT/bin/httpsdav -d $HTTPSDAV_ROOT -f $HTTPSDAV_ROOT/conf/httpsdav.conf -k start"
	REVAL=1
	if [ "$USER" = "root" ]; then
		(( su $DAV_USER -c "$cmdstart" >& /dev/null 1>&2 ) || ( $cmdstart >& /dev/null 1>&2 )) && REVAL=$?
	else 
		( $cmdstart >& /dev/null 1>&2 ) && REVAL=$?
	fi
    if [ $REVAL -eq 0 ]; then 
        echo -e "\e[5;32m 成功！\e[25m\n"
    else
        echo -e "\e[33m[\e[31m 失败 \e[33m]\e[0m"
        install_exit
    fi
    mv $HTTPSDAV_ROOT/conf/.tpl/systemctl_httpsdav.sh $HTTPSDAV_ROOT/my_webdav

    echo -e "\n\e[1;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\e[;32m 安装完成 \e[;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\n\e[;0m"
    echo "    欢迎使用httpsdav"
    echo "    你的httpsdav(使用SSL加密通道的webdav服务，即ssl+webdav)站点信息："
    echo "    访问地址：http://$HOST_IP:$webdav_port/$webdav_name"
    echo "    映射目录: $webdav_path/"
    echo "    登录名称：$webdav_login"
    echo "    验证密码：$webdavpwd"
    echo "    管理目录：$HTTPSDAV_ROOT"
    echo "    如果你要开启SSL加密传输功能，可在管理目录下执行"
    echo "        ./my_webdav start ssl"
    echo "    执行成功后，您的站点访问地址就变成了"
    echo "        https://$HOST_IP:$webdav_port/$webdav_name"
    echo "    开启后，如果你要关闭ssl功能，重新回到使用http，那么只要执行"
    echo "        ./my_webdav stop ssl"
    echo "    就可以了，同时你的站点访问地址也回到了原来的"
    echo "    你还可以在你的管理目录下使用"
    echo "        ./my_webdav start|stop|reload|restart"
    echo "    的命令对本机的httpsdav服务程序进行 启动|关闭|重载|重启 的操作"
    echo "    本软件为绿色软件，你可以在关闭站点后将管理目录移动到安装用户主目录下的任意路径下重新启动，不影响站点运行"
    echo "    如果你有安装中遇到什么问题或有什么建议和需求，或者使用httpsdav中遇到了什么问题"
    echo "    可以联系我：刘重量;  Email:13439694341@qq.com"
    echo -e "\n\e[1;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊ \e[;32m 祝你生活愉快 \e[;35m＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊\e[0m\n\n"
    return 0
}

check_install_conditions
httpsdav_install
install_exit
