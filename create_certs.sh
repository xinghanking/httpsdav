#!/bin/bash
#创建SSL证书的脚本，作者:刘重量(13439694341@qq.com)

set -e
set -E
trap 'echo "Fail unexpectedly on ${BASH_SOURCE[0]}:$LINENO!" >&2' ERR

WEBDAV_ROOT=$(readlink -f `dirname $BASH_SOURCE[0]`/..) #httpsdav的安装目录
HOST_IP=$(hostname -I |awk '{print $1}')    			#服务器IP
CERTS_DIR="$WEBDAV_ROOT/certs"                          #证书目录
APPLYER=`whoami`                                        #证书申请人用户名
IS_AUTO="n"                                             #是否使用默认申请信息自动创建证书

#参数处理（接受两个参数 -u：证书申请使用名； -k: 是否使用默认申请信息）
for parm in $*
do
    if [ "$parm" = "-u" ]; then
        str="$*"
        var=(${str##*-u})
        APPLYER="${var[0]}"
    elif [ "$parm" = "-k" ]; then
        IS_AUTO="y"
    fi
done

#创建证书工作目录
mkdir -p $CERTS_DIR/{ca,server,client}

#生成根证书
if [ ! -s "$CERTS_DIR/ca/webdavCA.crt" -o ! -s "$CERTS_DIR/ca/webdavCA.key" ]; then
    cd $CERTS_DIR/ca
    openssl genrsa -out webdavCA.key 2048
    openssl req -utf8 -new -x509 -days 3650 -key webdavCA.key -subj "/C=CN/ST=BeiJing/L=HaiDian/O=BeyondSoft/OU=dev/CN=httpsdav/emailAddress=13439694341@qq.com" -out webdavCA.crt
fi

#生成服务器端应用证书
if [ ! -s "$CERTS_DIR/server/server.crt" -o ! -s "$CERTS_DIR/server/server.key" ]; then
	cd $CERTS_DIR/server
	openssl genrsa -out server.key 2048
	openssl req -utf8 -new -key server.key -subj "/C=CN/ST=BeiJing/L=HaiDian/O=BeyondSoft/OU=dev/CN=${HOST_IP}/emailAddress=$APPLYER@${HOSTNAME}" -out server.csr
	openssl x509 -req -in server.csr -signkey server.key -CA $CERTS_DIR/ca/webdavCA.crt -CAkey $CERTS_DIR/ca/webdavCA.key  -CAcreateserial -days 3650 -out server.crt
    openssl verify -CAfile $CERTS_DIR/ca/webdavCA.crt server.crt
fi

#生成客户端证书
if [ ! -s "$CERTS_DIR/client/webdav_client.pfx" ]; then
	cd $CERTS_DIR/client
	openssl genrsa -out client.key 2048
	openssl req -utf8 -new -key client.key -subj "/C=CN/ST=BeiJing/L=HaiDian/O=BeyondSoft/OU=rdqa/CN=$APPLYER/emailAddress=$APPLYER@{HOSTNAME}" -out client.csr
	openssl x509 -req -in client.csr -signkey client.key -CA $CERTS_DIR/ca/webdavCA.crt -CAkey $CERTS_DIR/ca/webdavCA.key -CAcreateserial -days 3650 -out client.crt
	openssl verify -CAfile $CERTS_DIR/ca/webdavCA.crt client.crt
	#生成客户端的个人信息交换加密证书文件
	#openssl pkcs12 -export -in client.crt -inkey client.key -out webdav_client.pfx
fi