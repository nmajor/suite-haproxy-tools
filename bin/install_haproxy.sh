#!/bin/bash

# install haproxy

# add-apt-repository ppa:vbernat/haproxy-1.5
# apt-get update
# apt-get -y dist-upgrade
# apt-get -y install haproxy

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH"

apt-get update
apt-get -y install haproxy
sed -i "s/ENABLED=0/ENABLED=1/" /etc/default/haproxy

mkdir -p /run/haproxy/

# rm -rf /etc/init.d/haproxy
# cp ../script/haproxy.sh /etc/init.d/haproxy
# chmod +x /etc/init.d/haproxy

cd "$PARENT_PATH/.."