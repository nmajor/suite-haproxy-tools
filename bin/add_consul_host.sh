#!/bin/bash

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH"

sed --in-place '/consul/d' /etc/hosts

CONSUL=`cat ../config/consul.txt`
echo "$CONSUL consul" >> /etc/hosts

cd "$PARENT_PATH/.."