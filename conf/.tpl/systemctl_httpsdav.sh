#!/bin/bash
#httpsdav 控制脚本
#作者：刘重量 Email:13439694341@qq.com

#执行前初始化环境设置
set -e
set -E
OLD_LC_ALL=${LC_ALL:-""}                    #保存原来的语言编码
export LC_ALL="zh_CN.UTF-8"                 #设置界面显示语言及编码

#退出操作函数
operate_exit() {
    export LC_ALL="$OLD_LC_ALL"
    exit $RETV
}

#获取httpsdav套件的管理目录位置
HTTPSDAV_ROOT=$(readlink -f `dirname "$0"`)

#如果目录不存在就创建
if [ ! -d $HTTPSDAV_ROOT/bin ]; then
    mkdir -p $HTTPSDAV_ROOT/bin
fi

httpsdav="$HTTPSDAV_ROOT/bin/httpsdav"

#判断执行的前提条件
if [ ! -x $httpsdav ]; then
    rm -fr $httpsdav
    if [ -f /usr/sbin/apachectl -a -x /usr/sbin/apachectl ]; then
        ln -s /usr/sbin/apachectl $httpsdav
    elif [ -f /usr/sbin/httpd -a -x /usr/sbin/httpd ]; then
        ln -s /usr/sbin/httpd $httpsdav
    else
        echo "没有在默认位置找到httpd组件，退出执行"
        operate_exit
    fi
fi

#基本设置
prog="httpsdav"                                #程序名
loglevel="error"                               #错误日志记录级别
errorlog="$HTTPSDAV_ROOT/logs/error_log"       #错误日志的位置
lockfile="$HTTPSDAV_ROOT/var/subsys/httpsdav"
pidfile="$HTTPSDAV_ROOT/run/httpsdav.pid"

basecommand="-d $HTTPSDAV_ROOT -f $HTTPSDAV_ROOT/conf/httpsdav.conf -e $loglevel -E $errorlog -k"

RETVAL=0 #命令推出时的状态值

show_success() {
    echo -e "                   \e[33m[\e[32m OK \e[33m]\e[0m"
    return 0
}
show_fail() {
    echo -e "                   \e[33m[\e[31mFAIL\e[33m]\e[0m"
    return 0
}
#启动函数
start() {
    echo -n "启动$prog服务:"
    $httpsdav $basecommand start > /dev/null 2>&1
    RETVAL=$?
    [ $RETVAL -eq 0 ] && touch ${lockfile} && show_success && return $RETVAL
    show_fail && return $RETVAL
}

#关闭函数
stop() {
    echo -n "关停$prog服务:"
    $httpsdav $basecommand stop >& /dev/null 2>&1
    RETVAL=$?
    if [[ $RETVAL -eq 0 ]]; then
        show_success
        rm -fr ${lockfile} ${pidfile}
    else
        show_fail
    fi
    return $RETVAL
}

#重载函数
reload() {
    echo -n "重载$prog配置:"
    if ( ! $httpsdav -d $HTTPSDAV_ROOT -f $HTTPSDAV_ROOT/conf/httpsdav.conf -t >& /dev/null 2>&1 ); then
        echo -e "\n\e[31m检查配置文件中存在错误，不能重新加载配置文件\e[0m"
        operate_exit
    else
        $httpsdav $basecommand graceful >& /dev/null 2>&1
        RETVAL=$?
        if [[ $RETVAL -eq 0 ]]; then
            show_success
        else
            show_fail
        fi
    fi
    return $RETVAL
}

#重启函数
restart() {
    echo -n "重启$prog服务:"
    if ( ! $httpsdav -d $HTTPSDAV_ROOT -f $HTTPSDAV_ROOT/conf/httpsdav.conf -t >& /dev/null 2>&1 ); then
        echo -e "\n\e[31m检查配置文件中存在错误，修改正确后再重启吧？\e[0m"
        operate_exit
    else
        $httpsdav $basecommand restart >& /dev/null 2>&1
        RETVAL=$?
        if [[ $RETVAL -eq 0 ]]; then
            show_success
        else
            show_fail
        fi
    fi
    return $RETVAL
}

#参数调用
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    reload)
        reload
        ;;
    *)
    echo "请使用: systemctl_httpsdav.sh {start|stop|restart|reload}"
    RETVAL=2
esac

exit $RETV
