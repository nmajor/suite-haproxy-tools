!#/bin/bash

# Install Ruby

cd /tmp
RUN apt-get -y --force-yes install gcc make
curl -O http://cache.ruby-lang.org/pub/ruby/ruby-2.2.3.tar.gz
tar -xvzf ruby-2.2.3.tar.gz
cd /tmp/ruby-2.2.3
./configure --prefix=/usr/local
make
make install

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH/.."