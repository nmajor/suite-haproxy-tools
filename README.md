
    apt-get install git
    git clone git://github.com/nmajor/suite-haproxy-tools.git
    cd suite-haproxy-tools
    bash start.sh


cd suite


vim /etc/haproxy/haproxy.cfg
service haproxy restart


server emailgate-e7e80bd79676 192.168.130.212 check port 80 inter 5000 fastinter 1000 fall 1 rise 1 weight 1


# After days of trying, this article finally gave a solution to the ssl passthrough
https://scriptthe.net/2015/02/08/pass-through-ssl-with-haproxy/
