#!/bin/bash

# install haproxy

add-apt-repository ppa:vbernat/haproxy-1.5
apt-get update
apt-get -y dist-upgrade
apt-get -y install haproxy