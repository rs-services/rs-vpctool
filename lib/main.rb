require 'rubygems'
require 'logger'
require "right_api_client"
require 'yaml'
@logger            = Logger.new(STDOUT)

def initialize_api_client(options = {})
  # Require gems in initialize
  account_id=ARGV[2] #ENV['RS_ACCOUNT_ID']
  email=ARGV[1]#ENV['RS_EMAIL']
  password=ARGV[0]#ENV['RS_PASSWORD']
  api_url = 'https://my.rightscale.com'
  options = {
    account_id: account_id,
    email: email,
    password: password,
    api_url: api_url
  }.merge options
  RightApi::Client.new(options)
end

def cloud()
  @client.clouds(id: @config[:cloud_id]).show
end
def create_network(name)
  network=@client.networks.index(filter: ["name==#{name}","cloud_href==#{@cloud.href}"]).first
  if network
    @logger.info "network found #{network.show.name}"
    sgs = @cloud.security_groups.index(filter: ["network_href==#{network.href}"])
    sgs.each{|sg| @cloud.security_groups(id: sg.href.split('/').last).destroy unless sg.name=='default'}
    network_id=network.href.split('/').last
    nng= @client.network_gateways.index(filter: ["network_href==#{network.href}"]).first
    nng.update(network_gateway:{network_href:''}) if nng
    subnets = @cloud.subnets.index(filter: ["network_href==#{network.href}"])
    subnets.each{|subnet| @cloud.subnets(id: subnet.href.split('/').last).destroy}
    route_tables = @client.route_tables.index(filter: ["network_href==#{network.href}","name<>rt-"])
    route_tables.each{|route_table| @client.route_tables(id: route_table.href.split('/').last).destroy} 
    @client.networks(id: network_id).destroy 

    @logger.info "network #{network.show.name} deleted"
  end
  
  new_network=@client.networks.create(network:{cidr_block: '10.0.0.0/16',cloud_href: @cloud.href,
      name: name})
  @logger.info "new network #{new_network.show.name} created" if new_network
  @client.networks(id: new_network.href.split('/').last).show
end

def create_admin_security_group()

  sg= @cloud.security_groups.create(security_group: {name: "#{@network.name}-admin", network_href: @network.href})
  @logger.info "security group #{sg.show.name} created" if sg
  sgr=sg.show.security_group_rules.create(security_group_rule: {cidr_ips: '0.0.0.0/0', 
      direction: 'ingress', protocol: 'tcp',protocol_details: {end_port: '22',start_port: "22"},
      source_type: 'cidr_ips'})
  @logger.info "security group rule for #{sg.show.name} 22-22 added" if sgr
  sgr=sg.show.security_group_rules.create(security_group_rule: {cidr_ips: '0.0.0.0/0', 
      direction:'ingress', protocol: 'tcp',protocol_details:{end_port: '3389',start_port: 3389},
      source_type: 'cidr_ips'})
  @logger.info "security group rule for #{sg.show.name} 3389 added" if sgr
  sg
end
def create_nathost_security_group()

  sg= @cloud.security_groups.create(security_group: {name: "#{@network.name}-nathost", network_href: @network.href})
  @logger.info "security group #{sg.show.name} created" if sg
  sgr=sg.show.security_group_rules.create(security_group_rule: {cidr_ips: '10.0.0.0/16', 
      direction:'ingress', protocol: 'all',protocol_details:{start_port: '0',end_port: "65535"},
      source_type: 'cidr_ips'})
  @logger.info "security group rule for #{sg.show.name} ingress 0-65535 added" if sgr
  sgr=sg.show.security_group_rules.create(security_group_rule: {cidr_ips: '10.0.0.0/16', 
      direction:'egress', protocol: 'all',protocol_details:{start_port: '0',end_port: '65565'},
      source_type: 'cidr_ips'})
  @logger.info "security group rule for #{sg.show.name} egress 0-65535 added" if sgr

  sg
end
def create_passthrough_security_group()
  sg= @cloud.security_groups.create(security_group: {name: "#{@network.name}-private_pass_through", network_href: @network.href})
  @logger.info "security group #{sg.show.name} created" if sg
  sgr = sg.show.security_group_rules.create(security_group_rule: {cidr_ips: '10.0.0.0/16', 
      direction:'ingress', protocol: 'all',protocol_details:{end_port: '0',start_port: '65535'},
      source_type: 'cidr_ips'})
  @logger.info "security group rule for #{sg.show.name} ingress 0-65535 added" if sgr
  sgr = sg.show.security_group_rules.create(security_group_rule: {cidr_ips: '10.0.0.0/16', 
      direction:'egress', protocol: 'all',protocol_details:{end_port: '0',start_port: '65535'},
      source_type: 'cidr_ips'})
  @logger.info "security group rule for #{sg.show.name} egress 0-65535 added" if sgr
  sg
end

def create_subnet(name,cidr_block, datacenter)

  subnet = @cloud.subnets.create(subnet: {cidr_block: cidr_block, name: name ,
      datacenter_href: datacenter.href, network_href: @network.href,description: name}) 
  while subnet.show.state=='pending'
    sleep 30
    @logger.info "subnet status: #{subnet.show.state}"
  end
  @logger.info "Created subnet #{name} for datacenter #{datacenter.name}"
  subnet.show
end

def create_rt_public()
  rt = @client.route_tables.index(filter: ["name==public","network_href==#{@network.href}",
      "cloud_href==#{@cloud.href}"]).first
  unless rt
    rt = @client.route_tables.create(route_table: {name: 'public', 
        network_href: @network.href, cloud_href: @cloud.href})
   
    rt.show.routes.create(route: {destination_cidr_block: '0.0.0.0/0', 
        next_hop_type: 'network_gateway', next_hop_href: @gateway.href ,route_table_href: rt.href})
  end
  rt.show
end
def create_rt_private()
  rt = @client.route_tables.index(filter: ["name==private","network_href==#{@network.href}",
      "cloud_href==#{@cloud.href}"]).first
  unless rt
    rt = @client.route_tables.create(route_table: {name: 'private', cloud_href: @cloud.href, network_href: @network.href})
    
  end
  rt.show
end

def create_gw()
  ng=@client.network_gateways.index(filter: ["name==#{@network.name}-igw","cloud_href==#{@cloud.href}"]).first
  if ng
    @logger.info "network gateway #{ng.show.name} found"
    network_id=ng.href.split('/').last
    @client.network_gateways(id: network_id).destroy 
    @logger.info "network gateway #{ng.show.name} deleted"
  else
    ng= @client.network_gateways.create(network_gateway:{name: "#{@network.name}-igw", 
        cloud_href: @cloud.href, type: 'internet'})
    ng.update(network_gateway:{network_href: @network.href})
    @logger.info "Network Gateway #{ng.show.name} created."
  end
  while ng.show.state == 'pending'
    sleep 30
  end
  
  ng.show
end

def create_eip()
end

def create_nat_host()
  server_template = @client.server_templates(id: '333429003' ).show
  ssh_key = @cloud.ssh_keys.index.first
  sgs = @cloud.security_groups.index(filter: ["name==#{@network.name}"]).collect{|s| s.href}
  subnet  = @cloud.subnets.index(filter: ["name==public","network_href==#{@network.href}"]).first
  server  = @deployment.show.servers.create(server: { name: 'vpc nat host',  
      instance: {cloud_href: @cloud.href, 
        associate_public_ip_address: true, datacenter_href: subnet.datacenter.href,
        security_group_hrefs: sgs ,server_template_href: server_template.href,
        ssh_key_href: ssh_key.href, subnet_hrefs: [subnet.href]}})
  server.launch
  server
end

def add_nat_to_rt(server)
  rt = @client.route_tables.index(filter: ["name==private","network_href==#{@network.href}"]).first
  @logger.info server.href
  while  server.show.state == 'pending'
    sleep 30
    
    @logger.info "Waiting for server to boot to attach Route: server status: #{server.show.state}"
  end
  server =  @client.servers(id: server.href.split('/').last ).show
  rt.routes.create(route: {destination_cidr_block: '0.0.0.0/0', 
      next_hop_type: 'instance', next_hop_href: server.current_instance.href ,route_table_href: rt.href})
end



@client = RightApi::Client.new(YAML.load_file(File.expand_path('../../config/login.yml', __FILE__)))
@config = YAML.load_file(File.expand_path('../../config/network.yml', __FILE__))

@client.log(STDOUT) if @config[:client_log_enable]
network_name=@config[:network_name]

@cloud = cloud()
@logger.info "Building Network"

unless @config[:deployment_id]
  @logger.error "Missing deployment_id parameter"
  abort
else
  @deployment = @client.deployments(id: @config[:deployment_id]).show
  servers =  @deployment.servers.index(filter: ["name==vpc nat host"])
  servers.each do |server| 
    server_id = server.href.split('/').last
    state =  server.show.state
    server.terminate unless state=='inactive'
    while state != 'inactive'
      sleep 30
      state =  @client.servers(id: server_id ).show.state
      @logger.info "Waiting for server to terminate.  Server state: #{state}"
    end
    server.destroy
  end
end

@logger.info "Creating Network"
@network = create_network(network_name)
@logger.info "Creating Internet Gateway"
@gateway=create_gw()

@logger.info "Create Network Security Groups"
create_admin_security_group()
create_passthrough_security_group()
create_nathost_security_group()

datacenters= @cloud.datacenters.index

@logger.info "Create Network Public Subnets"
public_rt=nil
datacenters[0..datacenters.size - 1].each_with_index do |d,i|
  name="public-#{d.name.split('-').last}"
  @logger.info "Creating subnet #{name} in #{d.name}"
  begin
    subnet = create_subnet(name, "10.0.#{i}.0/24", d)
    # there should only be one route table.
    public_rt = create_rt_public() if public_rt.nil?
    subnet.update(subnet:{route_table_href: public_rt.href})
  rescue StandardError => e
    @logger.error e.message
    @logger.info "datacenter #{d.name} unavailable.  trying another"
    next
  end
 
end

@logger.info "Create Network Private Subnets"
rt=nil
datacenters[0..datacenters.size - 1].each_with_index do |d,i|
  name="private-#{d.name.split('-').last}"
  @logger.info "Creating subnet #{name} in #{d.name}"
  begin
    subnet = create_subnet(name, "10.0.1#{i}.0/24", d)
    rt = create_rt_private() if rt.nil?
    subnet.update(subnet:{route_table_href: rt.href})
  rescue StandardError => e
    @logger.error e.message
    @logger.info "datacenter #{d.name} unavailable.  trying another"
    next
  end
  
end

@logger.info "Launching Server"
server = create_nat_host()

@logger.info "Adding Nat Host to public route"
add_nat_to_rt(server)

@logger.info "Network Built"