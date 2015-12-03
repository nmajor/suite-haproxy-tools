#!/bin/bash

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH"

rm -rf /sbin/haproxy_helper
cp ../script/haproxy_helper.rb /sbin/haproxy_helper
chmod +x /sbin/haproxy_helper

cd "$PARENT_PATH/.."