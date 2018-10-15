#!/bin/bash
#创建SSL证书的脚本，作者:刘重量(13439694341@qq.com)
set -e
set -E
trap 'echo "Fail unexpectedly on ${BASH_SOURCE[0]}:$LINENO!" >&2' ERR
WEBDAV_ROOT=$(readlink -f `dirname $BASH_SOURCE[0]`/..) #httpsdav的安装目录
HOST_IP=$(hostname -I |awk '{print $1}')    #服务器IP
OPENSSL_CNF="$WEBDAV_ROOT/conf/openssl.cnf"
echo "CAHOME          = $WEBDAV_ROOT/certs/tmp" > $OPENSSL_CNF
cat $WEBDAV_ROOT/conf/.tpl/openssl.cnf >> $OPENSSL_CNF
CERTS_DIR="$WEBDAV_ROOT/certs"
rm -fr $CERTS_DIR/server $CERTS_DIR/client $CERTS_DIR/tmp
mkdir -p $CERTS_DIR/{server,client,tmp}
touch $CERTS_DIR/tmp/index.txt
echo "00" > $CERTS_DIR/tmp/serial
openssl rand 100 > $CERTS_DIR/tmp/.rnd
if [ ! -d "$CERTS_DIR/ca" ]; then
    mkdir -p $CERTS_DIR/ca
    cd $CERTS_DIR/ca
    openssl genrsa -out webdavCA.key 2048
    openssl req -utf8 -new -x509 -days 3650 -key webdavCA.key -subj "/C=CN/ST=BeiJing/L=HaiDian/O=BeyondSoft/OU=dev/CN=liuzhongliang/emailAddress=13439694341@qq.com" -out webdavCA.crt
fi
USER=`whoami`
cd $CERTS_DIR/server
openssl genrsa -out server.key 2048
openssl req -utf8 -new -key server.key -subj "/C=CN/ST=BeiJing/L=HaiDian/O=BeyondSoft/OU=dev/CN=${HOST_IP}/emailAddress=$USER@${HOSTNAME}" -out server.csr
openssl ca -utf8 -config $WEBDAV_ROOT/conf/openssl.cnf -in server.csr -cert $CERTS_DIR/ca/webdavCA.crt -keyfile $CERTS_DIR/ca/webdavCA.key -days 3650 -out server.crt <<EOF
y
y
EOF
openssl verify -CAfile $CERTS_DIR/ca/webdavCA.crt server.crt
cd $CERTS_DIR/client
openssl genrsa -out client.key 2048
openssl req -utf8 -new -key client.key -subj "/C=CN/ST=BeiJing/L=HaiDian/O=BeyondSoft/OU=rdqa/CN=$USER/emailAddress=$USER@{HOSTNAME}" -out client.csr
openssl ca -utf8 -config $WEBDAV_ROOT/conf/openssl.cnf -in client.csr -cert $CERTS_DIR/ca/webdavCA.crt -keyfile $CERTS_DIR/ca/webdavCA.key -days 3650 -out webdavClient.crt <<EOF
y
y
EOF
openssl verify -CAfile $CERTS_DIR/ca/webdavCA.crt webdavClient.crt
rm -fr $CERTS_DIR/tmp $WEBDAV_ROOT/conf/openssl.cnf
