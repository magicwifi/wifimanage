class AccessNode < ActiveRecord::Base
  default_scope order('updated_at DESC')
  has_many :connections
  has_many :trusted_macs
  has_many :black_macs
  has_many :public_ips
  has_many :online_connections, :class_name => "Connection", :conditions => "used_on is not null and (expired_on is null or expired_on > NOW())"
  has_one :auth
  has_one :conf
  has_one :authserver

  attr_accessible :last_seen, :mac, :name, :portal_url, :redirect_url, :remote_addr, :sys_memfree, :sys_upload, :sys_uptime, :update_time, :cmdflag, :configflag, :cmdline, :time_limit, :auth, :lat, :long, :developer
  validates :name, presence: true, uniqueness:true

  VALID_MAC_REGEX = /^[0-9A-F]+$/
  validates :mac, presence:true, uniqueness:true, length: { is:12 }, format: { with: VALID_MAC_REGEX }
  before_validation :sanitize_mac

  class << self
    def show_unlinked
      AccessNode.where("last_seen < ? and last_seen > ? ",Time.now - 60, Time.now - 600)
    end

   def disconnect
      nodes = AccessNode.show_unlinked
      nodes.each do |node|
        node.clean_all_conn
      end
    end
    
    def count_online_node
      AccessNode.where("last_seen > ? ", Time.now-60 ).count
    end


  end

  def show_online
    self.online_connections.count
  end

  def list_uniq_mac
    self.connections.select(:mac).uniq
  end

  def sanitize_mac
    self.mac = AccessNode.sanitize_mac_address(self.mac)
  end

  def self.find_by_mac(mac)
    self.find(:first, :conditions => ["mac = ?", sanitize_mac_address(mac)])
  end

  def self.sanitize_mac_address(mac)
    return nil if mac.nil?
    mac.gsub(/[:-]/, "").upcase
  end

  def self.list_by_time(page)
    paginate :per_page => 10, :page => page,  :order => 'last_seen desc'
  end 

  def total_up
    bytes_up = 0
    connections = self.connections.find(:all, :conditions => [ 'created_at > ?', Time.now - 1.month ])
    connections.each do |connection|
      unless connection.outgoing.nil?
        bytes_up += connection.outgoing
      end
    end
    return bytes_up
  end

  def total_down
    bytes_down = 0
    connections = self.connections.find(:all, :conditions => [ 'created_at > ?', Time.now - 1.month ])
    connections.each do |connection|
      unless connection.incoming.nil?  
        bytes_down += connection.incoming
      end
    end
    return bytes_down
  end

  def running?
    if self.last_seen && Time.now-self.last_seen < 70
      return true;
    else
      return false;
    end 
  end
 
  def clean_all_conn 
    connections = self.online_connections
    connections.each do |connection|
      connection.expire!
    end
  end

  def show_running?
    if self.last_seen && Time.now-self.last_seen < 60
      return true;
    else
      return false;
    end 
  end

  def banned_mac?(mac)
    self.black_macs.each do |black|
      if black.mac == mac
        return true;
      end
    end
    return  false;
  end

  def self.bindurl(params)
    if params[:data].nil? || params[:data].length > 10
      {:check=>false,:code=>104, :msg=>"Data More Than ten"}
    else
      begin
        self.transaction do
          params[:data].each do |object|
            object[:developer] = params[:username]
            access = self.create!(object)
            Auth.create!(auth_type:"local",auth_device:false,access_node_id:access.id)
            Conf.create!(access_node_id:access.id)
          end
        end
      rescue Exception => e
        return {:check=>false,:code=>105, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true, :code=>200, :msg=>"Success"}
    end
  end

  def self.createnode(params,ipaddr)
    #if params[:data].nil? || params[:data].length > 10
    #  {:check=>false,:code=>104, :msg=>"Data More Than ten"}
    #else
      begin
        self.transaction do
          #params[:AP].each do |param|
            object = params[:data]
            object[:developer] = params[:username]
            access = self.create!(object)
 logger.info "zc access.id=#{access.id}"        
    PublicIp.create!(publicip:"218.94.58.242",access_node_id:access.id);
            #Auth.create!(auth_type:"radius",auth_device:false,access_node_id:access.id)
            Conf.create!(access_node_id:access.id)
            Authserver.create!(access_node_id:access.id,ipaddr:ipaddr,node_mac:object[:mac])
          #end
        end
      rescue Exception => e
        return {:check=>false,:code=>105, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true, :code=>200, :msg=>"#{ipaddr}"}
    #end
  end
  
  def self.show_connections(params)
    access = self.find_by_mac(params[:mac])
    if  access
      connections = access.connections.limit(20)
      status = Status.first
      { :check=>true,  :results=>connections, :status => status }
    else
      {:check=>false, :code=>102,:msg=>"Not Found AccessNode"}
    end
  end

  def self.show_node(params)
    access = self.find_by_mac(params[:mac])
    if  access
      status = Status.first
      { :check=>true,  :results=>access, :status => status }
    else
      {:check=>false, :code=>102,:msg=>"Not Found AccessNode"}
    end
  end
  
  def self.show_nodes(params)
    page = params[:page].to_i
    if page > 0 
      logger.info "success"
      nodes = self.list_by_time(page)
      status = Status.first
      { :check=>true,  :results => nodes, :status => status }
    else
      logger.info "error"
      {:check=>false, :code=>102,:msg=>"Page Number Error"}
    end
  end

  def self.update_auth_type(params)
    times = params[:times].to_i
    if times<=0 or times>5
      {:check=>false, :code=>102, :msg=>"Execced Max Number"}
    elsif params[:authtype].nil? or !access=self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
        authtype = params[:authtype].to_s  
      begin
        access.auth.update_attributes!(auth_type:authtype) 
      rescue Exception => e
        {:check=>false,:code=>103, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true,:code=>200,:msg=>"Success"}
    end
  end

  def self.update_portal_url(params)
    if params[:redirect_url].nil? and params[:portal_url].nil?
      {:check=>false, :code=>102, :msg=>"Not Found URL"}
    elsif !access=self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
        portal={}
        portal[:redirect_url] = params[:redirect_url].to_s  if !params[:redirect_url].nil?
        portal[:portal_url] = params[:portal_url].to_s  if !params[:portal_url].nil?
      begin
        access.update_attributes!(portal) 
      rescue Exception => e
        {:check=>false,:code=>103, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true,:code=>200,:msg=>"Success"}
    end
  end

  def self.update_auth_device(params)
    times = params[:times].to_i
    if times<=0 or times>5
      return {:check=>false, :code=>102, :msg=>"Execced Max Number"}
    elsif !access=self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
      begin
        access.auth.update_attributes!(auth_device:params[:authdevice]) 
      rescue Exception => e
        return {:check=>false,:code=>103, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true,:code=>200,:msg=>"Success"}
    end
  end

  def self.update_access_time(params)
    times = params[:times].to_i
    timeline = params[:time_delay].to_i
    if times<=0 or times>5
      return {:check=>false, :code=>102, :msg=>"Execced Max Number"}
    elsif  timeline > 720 or timeline <= 0
      return {:check=>false, :code=>105, :msg=>"Set Wrong Time"}
    elsif !access = self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
      begin
        access.update_attributes!(time_limit:timeline) 
      rescue Exception => e
        return {:check=>false,:code=>103, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true,:code=>200,:msg=>"Success"}
    end
  end


   def self.ping(params)
     node = self.find_by_mac(params[:gw_id])
     pongstr = "Pong"
     if node
       node.update_attributes(
         :sys_uptime => params[:sys_uptime],
         :sys_upload => params[:sys_load],
         :sys_memfree => params[:sys_memfree],
         :update_time => params[:wifidog_uptime],
         #:remote_addr => request.remote_addr,
         :last_seen => Time.now
       )

       if node.cmdflag == true
         node.update_attributes( :cmdflag => false );
         pongstr += ":cmdflag"
       elsif node.configflag == true
         node.update_attributes( :configflag => false );
         pongstr += ":configflag"
       end
     end
     pongstr
  end


  def self.retrieve(params)
    node = self.find_by_mac(params[:gw_id])
    str = "Cmd:"
    if node
      str="Cmd:"+node.cmdline
    end
    str
  end

  def self.addnodes(params)

    server_ip=''
    @@turn=Hash.new
    if params[:AP].nil? || params[:AP].length > 10
      return {:check=>false,:code=>104, :msg=>"AP More Than ten"}
    else
      begin
        self.transaction do
          params[:AP].each do |param|
            province_code = param[:address][:province]
logger.info "province_code=#{province_code}"
            pservers = Server.find(:all,:conditions=>["province_code=?",province_code])
logger.info "pservers.size=#{pservers.size}"            
            if pservers.nil? or pservers.size == 0
              return {:check=>false,:code=>103,:msg=>"Province code not found"}
            end
            unless @@turn.keys.index(province_code)
                 @@turn[province_code] =0
            end
            if @@turn[province_code] > pservers.size-1 then
              @@turn[province_code] =0
            end
            puts pservers.size           
            param[:username] = params[:username]
            param[:password] = params[:password]
            server_ip = pservers[@@turn[province_code]].server_ip
 logger.info "zc ip=#{server_ip}"
            result = HTTParty.post("http://#{server_ip}/addnodes.json",
                          :body => param.to_json,
                            :headers => { 'Content-Type' => 'application/json' }
                         )
code = result["status"]["code"]
logger.info "result:#{result},code=#{code}"
            if result["status"]["code"] == "200"
logger.info "181 ok param=#{param}"
               check =  AccessNode.createnode  param, server_ip
               @@turn[province_code] = @@turn[province_code]+1
            else
               return {:code=> result[:status][:code],:msg=> "#{result[:status][:message]}"}
            end
          end
        end
      rescue Exception => e
        return {:check=>false,:code=>105, :msg=>"Insert Error #{e.to_s}"}
      end
      return {:check=>true, :code=>200, :msg=>"Success", :serverIP=>"#{server_ip}"}
    end
  end


  def self.fetchconf(params)
    node = self.find_by_mac(params[:gw_id])
    str ="Conf:"
    if node
      node.update_attributes( :last_seen => Time.now, :configflag=>false, :cmdflag=>false )
      conf = node.conf
      if !conf.nil?
        str += "checkinterval="+conf.checkinterval.to_s+"&authinterval="+conf.authinterval.to_s+"&clienttimeout="+conf.clienttimeout.to_s+"&httpdmaxconn="+conf.httpmaxconn.to_s

      else
        str += "checkinterval=60&authinterval=60&clienttimeout=5&httpdmaxconn=10"
      end

      if !node.trusted_macs.empty?
        str += "&trustedmaclist="
        macs = Array.new
        node.trusted_macs.each do |trusted|
          macs.push(trusted.mac)
        end
        str += macs.join("+")
      end

      if !node.public_ips.empty?
        str += "&firewallrule="
        ips = Array.new
        node.public_ips.each do |ip|
          ips.push(ip.publicip)
        end
        str += ips.join("+")
      end
    end
    

    if !node.authserver.nil?
      uri = URI.parse("http://#{node.authserver.ipaddr}/setconfigflag")  
      res = Net::HTTP.post_form(uri, params)   
      puts res.header['set-cookie']  
      puts res.body 
      str += "&authserver=#{node.authserver.ipaddr}"
    end
    str
  end

  def self.login(params)
    node = self.find_by_mac(params[:gw_id]) 
    unless node
      redirect_url = "http://218.94.58.242"
    else
      if !node.redirect_url.blank?
        redirect_url = node.redirect_url+"&gw_address=#{params[:gw_address]}&gw_port=#{params[:gw_port]}&gw_id=#{params[:gw_id]}&public_ip=117.34.78.195&mac=#{params[:mac]}"
      end
      redirect_url ||= "/404"
    end
  end

  def self.portal(params)
    node = self.find_by_mac(params[:gw_id])
    unless node
      redirect_url = "/404"
    else
      if !node.portal_url.blank?
        redirect_url =  node.portal_url+"&mac="+params[:mac].to_s
      end
      redirect_url ||=  "http://www.baidu.com"
    end
  end

  def self.authenticate(params,device)
    node = self.find_by_mac(params[:gw_id])
    if node.nil? or  params[:gw_id].nil? or params[:gw_address].nil? or params[:gw_port].nil? or params[:logintype].nil? or !node.auth.check_device(device)
      redirect_url = "/404"
    else
      unless node.auth.authenticate params[:username],params[:checkcode], params[:logintype]

        redirect_url = node.redirect_url+"&gw_address=#{params[:gw_address]}&gw_port=#{params[:gw_port]}&gw_id=#{params[:gw_id]}&public_ip=117.34.78.195&mac=#{params[:mac]}"
      else
        token=SecureRandom.urlsafe_base64(nil, false)
        if !node.time_limit.nil? and node.time_limit > 0
          login_connection = Connection.create!(:token => token,
                                                :phonenum => params[:username],
                                                :access_mac => params[:gw_id],
                                                :device => device,
                                                :access_node_id => node.id,
                                                :expired_on => Time.now+node.time_limit.minutes,
                                                :portal_url => params[:url]
                                               )
        else
          login_connection = Connection.create!(:token => token,
                                                :phonenum => params[:username],
                                                :access_mac => params[:gw_id],
                                                :device => device,
                                                :access_node_id => node.id,
                                                :expired_on => Time.now+30.minutes,
                                                :portal_url => params[:url]
                                               )
        end

        redirect_url ||= "http://#{params[:gw_address]}:#{params[:gw_port]}/ctbrihuang/auth?token=#{token}"
      end
    end
  end

end

