#!/bin/bash

# install haproxy

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH"

apt-get update
apt-get -y install haproxy

rm -rf /etc/init.d/haproxy
cp ../script/haproxy.sh /etc/init.d/haproxy
chmod +x /etc/init.d/haproxy

cd "$PARENT_PATH/.."