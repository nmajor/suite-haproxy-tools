!#/bin/bash

# Install Ruby

apt-get -y update
apt-get -y install build-essential zlib1g-dev libssl-dev libreadline6-dev libyaml-dev
cd /tmp
curl -O http://cache.ruby-lang.org/pub/ruby/ruby-2.2.3.tar.gz
tar -xvzf ruby-2.2.3.tar.gz
cd /tmp/ruby-2.2.3
./configure --prefix=/usr/local
make
make install

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH/.."