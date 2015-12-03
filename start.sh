!#/bin/bash

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$PARENT_PATH"

bash ./bin/install_ruby.sh
bash ./bin/install_haproxy.sh
bash ./bin/add_haproxy_helper.sh
bash ./bin/add_consul_host.sh
bash ./bin/add_cron_jobs.sh