#!/usr/bin/ruby

require 'net/http'
require 'json'

class Service
  attr_accessor :name, :nodes

  def initialize name: nil, nodes: nil
    @name ||= name
    @nodes ||= nodes
  end

  def host
    "#{name}.com"
  end

  def healthy_nodes
    nodes.select{|n| n.healthy? }
  end

  def unhealthy_nodes
    nodes.select{|n| !n.healthy? }
  end

  def deregister_unhealthy_nodes
    unhealthy_nodes.each{|n| n.deregister! }
  end
end

class ServiceNode
  attr_accessor :id, :service_name, :tags, :address, :port, :checks

  def initialize id: nil, service_name: nil, tags: nil, address: nil, port: nil, checks: nil
    @id ||= id
    @service_name ||= service_name
    @tags ||= tags
    @address ||= address
    @port ||= port
    @checks ||= checks

    checks.each{|c| c.service = self }
  end

  def container_id
    id.gsub(/#{service_name}-/, '')
  end

  def healthy?
    !checks.any?{|c| c.failed? }
  end

  def deregister!
    Request.new("/agent/service/deregister/#{id}", method: "post").send if !healthy?
  end
end

class Check
  attr_accessor :service, :id, :name, :status, :notes, :output

  def initialize service: nil, attributes: nil
    @service ||= service

    if attributes
      @id ||= attributes["CheckID"]
      @name ||= attributes["Name"]
      @status ||= attributes["Status"]
      @notes ||= attributes["Notes"]
      @output ||= attributes["Output"]
    end
  end

  def service_name
    service.name
  end

  def service_id
    service.id
  end

  def failed?
    ["critical"].include?(status) && output.include?("request canceled while waiting for connection")
  end
end

class ServiceList
  def get_services
    get_request("/agent/services")
  end

  def grouped_services
    @grouped_services ||= get_services.map{|s| s[1] }.group_by{|s| s["Service"]}
  end

  def get_checks
    get_request("/agent/checks")
  end

  def services
    grouped_services.map do |service_name, service_attribute_list|
      next if service_name == 'consul'
      ServiceFactory.new(service_name: service_name, service_attribute_list: service_attribute_list, checks: get_checks).service
    end.compact
  end

  private
    def get_request path
      Request.new(path).response_body
    end
end

class ServiceFactory
  attr_accessor :service_name, :service_attribute_list, :checks

  def initialize service_name: nil, service_attribute_list: nil, checks: nil
    @service_name ||= service_name
    @service_attribute_list ||= service_attribute_list
    @checks ||= checks
  end

  def service_attribute_list
    @service_attribute_list ||= ServiceList.new.grouped_services[service_name]
  end

  def checks
    @checks ||= ServiceList.new.get_checks
  end

  def service
    Service.new(name: service_name, nodes: service_nodes)
  end

  def grouped_checks
    @grouped_checks ||= checks.map{|c| c[1] }.group_by{|s| s["ServiceID"]}
  end

  def checks_for_service_id service_id
    return [] unless grouped_checks[service_id]

    grouped_checks[service_id].map{|c| Check.new(attributes: c)}
  end

  def service_nodes
    service_attribute_list.map do |service|
      ServiceNode.new(
        id: service["ID"],
        service_name: service["Service"],
        tags: service["Tags"],
        address: service["Address"],
        port: service["Port"],
        checks: checks_for_service_id(service["ID"])
      )
    end
  end
end

class Request
  attr_accessor :path, :method

  CONSUL = 'consul'

  def initialize path, method: 'get'
    @path ||= path
    @method ||= method
  end

  def consul_base_uri
    URI("http://#{CONSUL}:8500/v1")
  end

  def base_uri
    consul_base_uri
  end

  def response_body
    JSON.parse(send_request.body)
  end

  def send
    send_request
  end

  def request
    Object::const_get("Net::HTTP::#{method.capitalize}").new(base_uri.path+path)
  end

  def send_request
    Net::HTTP.new(base_uri.host, base_uri.port).start {|http| http.request(request) }
  end
end

class HAProxy
  CONFIG = '/etc/haproxy/haproxy.cfg'

  attr_accessor :list, :old_config
  alias_method :service_list, :list

  def initialize list: []
    @list = list
  end

  def config_file
    CONFIG
  end

  def refresh_config
    old_config = File.read(config_file)
    if old_config != config_text
      File.open(config_file, "w") do |file|
         file.write(config_text)
      end
      # restart
    end
  end

  def restart
    `sv reload haproxy`
  end

  def config_text
@config_text ||= <<EOT
#{default_config}

frontend http-in
\tbind *:80
\tmode http

#{ service_list.map{|service| frontend_service_text(service) }.join }

#{ service_list.map{|service| backend_service_text(service) }.join }
EOT
  end

   def default_config
<<EOT
global
\tlog /dev/log    local0
\tlog /dev/log    local1 notice
\tchroot /var/lib/haproxy
\tstats socket /run/haproxy/admin.sock mode 660 level admin
\tstats timeout 30s
\tuser haproxy
\tgroup haproxy
\tdaemon

\t# Default SSL material locations
\tca-base /etc/ssl/certs
\tcrt-base /etc/ssl/private

\t# Default ciphers to use on SSL-enabled listening sockets.
\t# For more information, see ciphers(1SSL).
\tssl-default-bind-ciphers kEECDH+aRSA+AES:kRSA+AES:+AES256:RC4-SHA:!kEDH:!LOW:!EXP:!MD5:!aNULL:!eNULL

defaults
\tlog     global
\tmode    http
\toption  httplog
\toption  dontlognull
\ttimeout connect 5000
\ttimeout client  50000
\ttimeout server  50000
\terrorfile 400 /etc/haproxy/errors/400.http
\terrorfile 403 /etc/haproxy/errors/403.http
\terrorfile 408 /etc/haproxy/errors/408.http
\terrorfile 500 /etc/haproxy/errors/500.http
\terrorfile 502 /etc/haproxy/errors/502.http
\terrorfile 503 /etc/haproxy/errors/503.http
\terrorfile 504 /etc/haproxy/errors/504.http
EOT
  end

  def frontend_service_text service
<<EOT
\tacl #{acl_name(service)} hdr(host) -i #{service.host}
\tuse_backend #{backend_name(service)} if #{acl_name(service)}
EOT
  end

  def backend_service_text service
<<EOT
backend #{backend_name(service)}
\tmode http
\tbalance roundrobin
\toption forwardfor
\thttp-request set-header X-Forwarded-Port %[dst_port]
\thttp-request add-header X-Forwarded-Proto https if { ssl_fc }
\toption httpchk HEAD / HTTP/1.1\\r\\nHost:localhost
#{ service.healthy_nodes.map{|n| server_text(n) }.join }
EOT
  end

  def server_text service_node
    "\tserver #{service_node.id} #{service_node.address}:#{service_node.port} check\n"
  end

  def backend_name service
    "#{service.name}_backend"
  end

  def acl_name service
    "#{service.name}_acl"
  end
end

case ARGV[0]
when "refresh_config"
  HAProxy.new(list: ServiceList.new.services).refresh_config
when "deregister_nodes"
  ServiceList.new.services.each{|service| service.deregister_unhealthy_nodes }
end