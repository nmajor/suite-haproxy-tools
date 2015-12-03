#!/bin/bash

# install haproxy

apt-get update
apt-get -y install haproxy

rm -rf /etc/init.d/haproxy
cp ../script/haproxy.sh /etc/init.d/haproxy
chmod +x /etc/init.d/haproxy