#!/usr/bin/ruby

require 'net/http'
require 'json'

service_name_map = {
  :concept => ''
}

class Service
  attr_accessor :name, :nodes

  def initialize name: nil, nodes: nil
    @name ||= name
    @nodes ||= nodes
  end

  def host
    host_map[name] || "#{name}.com"
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

  def has_admin?
    admin_map[name] || false;
  end

  def ssl_map
    return {
      "emailgate" => true,
    }
  end

  def host_map
    {
      "concept" => "api.concept.nmajor.com",
      "dathobby" => "api.dathobby.com",
      "emailgate" => "myemailbook.com",
    }
  end

  def admin_map
    {
      "emailgate" => true,
    }
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
    response = Request.new("/agent/service/deregister/#{id}", method: "post").send if !healthy?
    puts response
    response
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
    ["critical"].include?(status)
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
      restart
    end
  end

  def restart
    `service haproxy restart`
  end

  def config_text
@config_text ||= <<EOT
#{default_config}

frontend http-in *:80
\tmode http
\toption httplog
#{ frontend_service_text }

frontend https-in *:443
\toption socket-stats
\ttcp-request inspect-delay 5s
\ttcp-request content accept if { req_ssl_hello_type 1 }
#{ frontend_service_text_https }
#{ backend_service_text }
#{ backend_service_text_https }
listen stats :1936
\tmode http
\tstats enable
\tstats hide-version
\tstats realm Haproxy\ Statistics
\tstats uri /
\tstats auth nike:#{ENV["HAPROXY_STATS_PASS"]}
EOT
  end

   def default_config
<<EOT
global
\tlog 127.0.0.1 local0 notice
\tchroot /var/lib/haproxy
\tstats socket /run/haproxy.sock mode 660 level admin
\tstats timeout 30s
\tuser haproxy
\tgroup haproxy
\tdaemon

defaults
\tlog     global
\toption  dontlognull
\ttimeout connect 5000
\ttimeout client  50000
\ttimeout server  50000
\t# errorfile 400 /etc/haproxy/errors/400.http
\t# errorfile 403 /etc/haproxy/errors/403.http
\t# errorfile 408 /etc/haproxy/errors/408.http
\t# errorfile 500 /etc/haproxy/errors/500.http
\t# errorfile 502 /etc/haproxy/errors/502.http
\t# errorfile 503 /etc/haproxy/errors/503.http
\t# errorfile 504 /etc/haproxy/errors/504.http
EOT
  end

  def frontend_service_text
    ( service_list.map{|service| acl_text(service) } + service_list.map{|service| use_backend_text(service) } ).join
  end

  def frontend_service_text_https
    ( service_list.map{|service| acl_text_https(service) } + service_list.map{|service| use_backend_text_https(service) } ).join
  end

  def acl_text service
    "\tacl #{acl_name(service)} hdr_end(host) -i #{service.host}\n"
  end

  def acl_text_https service
  admin_acl = service.has_admin? ? "\tacl #{acl_name(service)}_https_admin req_ssl_sni -i admin.#{service.host}" : nil
<<EOT
\tacl #{acl_name(service)}_https req_ssl_sni -i #{service.host}
\tacl #{acl_name(service)}_https_www req_ssl_sni -i www.#{service.host}
#{admin_acl}
EOT
  end

  def use_backend_text service
    "\tuse_backend #{backend_name(service)} if #{acl_name(service)}\n"
  end

  def use_backend_text_https service
    admin_backend_text =  service.has_admin? ? "\tuse_backend #{backend_name(service)}_https if #{acl_name(service)}_https_admin" : nil
<<EOT
\tuse_backend #{backend_name(service)}_https if #{acl_name(service)}_https
\tuse_backend #{backend_name(service)}_https if #{acl_name(service)}_https_www
#{admin_backend_text}
EOT
  end

  def backend_service_text
    ( service_list.map{|service| backend_text(service) } ).join
  end

  def backend_service_text_https
    ( service_list.map{|service| backend_text_https(service) } ).join
  end

  def backend_text service
<<EOT
backend #{backend_name(service)}
\tmode http
\tbalance roundrobin
\toption forwardfor
#{ service.healthy_nodes.map{|n| server_text(n) }.join }
EOT
  end

  def backend_text_https service
<<EOT
backend #{backend_name(service)}_https
\tmode tcp
\tstick-table type binary len 32 size 30k expire 30m
\tacl clienthello req_ssl_hello_type 1
\tacl serverhello rep_ssl_hello_type 2
\ttcp-request inspect-delay 5s
\ttcp-request content accept if clienthello
\ttcp-response content accept if serverhello
\tstick on payload_lv(43,1) if clienthello
\tstick store-response payload_lv(43,1) if serverhello
\toption httpchk HEAD /health HTTP/1.1\\r\\nHost:localhost
#{ service.healthy_nodes.map{|n| server_text_https(n) }.join }
EOT
  end

  def server_text service_node
    # "\tserver #{service_node.id} #{service_node.address}:#{service_node.port} check inter 5000 fastinter 1000 fall 1 rise 1 weight 1 maxconn 100\n"
    "\tserver #{service_node.id} #{service_node.address}:80 check inter 5000 fastinter 1000 fall 1 rise 1 weight 1\n"
    # "\tserver #{service_node.id} #{service_node.address}:#{service_node.port} check\n"
  end

  def server_text_https service_node
    "\tserver #{service_node.id} #{service_node.address}:443 check port 80 inter 5000 fastinter 1000 fall 1 rise 1 weight 1\n"
  end

  def backend_name service
    "#{service.name}_backend"
  end

  def acl_name service
    "#{service.name}_acl"
  end
end

# HAProxy.new(list: ServiceList.new.services).refresh_config

case ARGV[0]
when "refresh_config"
  HAProxy.new(list: ServiceList.new.services).refresh_config
when "deregister_nodes"
  ServiceList.new.services.each{|service| service.deregister_unhealthy_nodes }
else
  HAProxy.new(list: ServiceList.new.services).refresh_config
end
