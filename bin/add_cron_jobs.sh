#!/bin/bash

(crontab -l 2>/dev/null; echo "* * * * * haproxy_helper refresh_config") | crontab -
(crontab -l 2>/dev/null; echo "0 */6 * * * haproxy_helper deregister_nodes") | crontab -
