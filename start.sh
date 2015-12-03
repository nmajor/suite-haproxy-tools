!#/bin/bash

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH"

bash ./install_ruby.sh
bash ./install_haproxy.sh
bash ./add_haproxy_helper.sh
bash ./add_consul_host.sh
bash ./add_cron_jobs.sh