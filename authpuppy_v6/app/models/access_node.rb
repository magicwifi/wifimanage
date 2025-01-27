require 'net/http'
require 'json'
class AccessNode < ActiveRecord::Base
  default_scope order('updated_at DESC')
  has_many :connections
  has_many :trusted_macs
  has_many :black_macs
  has_many :public_ips
  has_many :online_connections, :class_name => "Connection", :conditions => "used_on is not null and (expired_on is null or expired_on > NOW())"
  has_one :auth
  has_one :conf
  has_one :address
  belongs_to :nodecmd

  attr_accessible :last_seen, :mac, :name, :portal_url, :redirect_url, :remote_addr, :sys_memfree, :sys_upload, :sys_uptime, :update_time, :cmdflag, :configflag, :cmdline, :time_limit, :auth, :lat, :long, :developer, :nodecmd_id,:ssid, :wan_ip, :belong_type, :dev_id, :guest_id,:auth_plattype, :task_code, :task_params
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
    #AccessNode.where(:name => sanitize_mac_address(mac)).first
    self.find(:first, :conditions => ["mac = ?", sanitize_mac_address(mac)])
  end

  def self.sanitize_mac_address(mac)
    return nil if mac.nil?
    mac.gsub(/[:-]/, "").upcase
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
    if self.last_seen && Time.now-self.last_seen < 60
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

  def self.addnodes(params)
    #if params[:AP].nil? || params[:AP].length > 10
    #  {:check=>false,:code=>104, :msg=>"AP More Than ten"}
    #else
      begin
        self.transaction do
          #params[:AP].each do |param|
            object = params[:data]
            object[:developer] = params[:username]
            logger.info "zc begin creating"
            access = self.create!(object)
            logger.info "zc  node.id=#{access.id}"
            Auth.create!(auth_type:"radius",auth_device:false,access_node_id:access.id)
            logger.info "zc auth created!"
            Conf.create!(access_node_id:access.id)
            logger.info "zc conf created!"
            ob_address = params[:address]
            Address.create!(access_node_id:access.id,city:ob_address[:city],detail:ob_address[:detail],province:ob_address[:province],district:ob_address[:district])
            ob_contact = params[:contact]
            logger.info "zc address created"
            Contact.create!(access_node_id:access.id,merchant:ob_contact[:merchant],name:ob_contact[:name],phonenum:ob_contact[:phonenum],telephonenum:ob_contact[:telephonenum],email:ob_contact[:email],weixin:ob_contact[:weixin],node_mac:object[:mac])
            logger.info "zc contact created"
          #end
        end
      rescue Exception => e
        return {:check=>false,:code=>105, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true, :code=>200, :msg=>"Success", :serverIP=>""}
    #end
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
            Auth.create!(auth_type:"radius",auth_device:false,access_node_id:access.id)
            Conf.create!(access_node_id:access.id)
          end
        end
      rescue Exception => e
        return {:check=>false,:code=>105, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true, :code=>200, :msg=>"Success"}
    end
  end

  def self.update_publicip(params)
    if params[:data].nil? || params[:data].length > 5
      {:check=>false,:code=>104, :msg=>"Data More Than Five"}
    elsif  !access=self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
      begin
        self.transaction do
          access.public_ips.delete_all
          params[:data].each do |object|
            object[:access_node_id]=access.id
            PublicIp.create!(object);
          end
     	  access.update_attributes( :configflag => true );
     	  access.clean_all_conn 
        end
      rescue Exception => e
        return {:check=>false,:code=>105, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true, :code=>200, :msg=>"Success"}
    end
  end
  
  def self.update_trustedmacs(params)
    if params[:data].nil? || params[:data].length > 5
      {:check=>false,:code=>104, :msg=>"Data More Than Five"}
    elsif  !access=self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
      begin
        self.transaction do
          access.trusted_macs.delete_all
          params[:data].each do |object|
            object[:access_node_id]=access.id
            TrustedMac.create!(object);
          end
          access.update_attributes( :configflag => true );
          access.clean_all_conn
        end
      rescue Exception => e
        return {:check=>false,:code=>105, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true, :code=>200, :msg=>"Success"}
    end
  end

  def self.show_connections(mac)
    access = self.find_by_mac(mac)
    if  access
      connections = Connection.show_by_date(access,Time.now.to_date)
      status = Status.first
      { :check=>true,  :conn=>connections, :status => status }
    else
      {:check=>false, :code=>102,:msg=>"Not Found AccessNode"}
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

  def self.update_cmdline(params)
    times = params[:times].to_i
    nodecmd_id = params[:nodecmd_id].to_i
    if times<=0 or times>5
      return {:check=>false, :code=>102, :msg=>"Execced Max Number"}
    elsif  nodecmd_id > 6 or nodecmd_id <= 0
      return {:check=>false, :code=>105, :msg=>"Set Wrong Number"}
    elsif !access = self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
      begin
        access.update_attributes!(:nodecmd_id=>params[:nodecmd_id],:cmdflag =>true )
      rescue Exception => e
        return {:check=>false,:code=>103, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true,:code=>200,:msg=>"Success"}
    end
  end

  def self.update_conf(params)
    times = params[:times].to_i
    if times<=0 or times>5
      return {:check=>false, :code=>102, :msg=>"Execced Max Number"}
    elsif  params[:checkinterval].nil? or params[:authinterval].nil? or params[:clienttimeout].nil? or params[:httpmaxconn].nil?
      return {:check=>false, :code=>105, :msg=>"Less Params Error"}
    elsif !access = self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
      begin
        access.conf.update_attributes(checkinterval:params[:checkinterval],authinterval:params[:authinterval],clienttimeout:params[:clienttimeout],httpmaxconn:params[:httpmaxconn])
     	access.update_attributes( :configflag => true );
     	access.clean_all_conn 
      rescue Exception => e
        return {:check=>false,:code=>103, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true,:code=>200,:msg=>"Success"}
    end
  end

  def self.create_address(params)
    if  params[:city].nil? or params[:province].nil? or params[:district].nil? or params[:detail].nil?
      return {:check=>false, :code=>105, :msg=>"Less Params Error"}
    elsif !access = self.find_by_mac(params[:mac])
      {:check=>false, :code=>104,:msg=>"Not Found AccessNode"}
    else
      begin
        Address.create!(city:params[:city],province:params[:province],district:params[:district],detail:params[:detail],access_node_id:access.id)
      rescue Exception => e
        return {:check=>false,:code=>103, :msg=>"Insert Error #{e.to_s}"}
      end
      {:check=>true,:code=>200,:msg=>"Success"}
    end
  end


   def self.ping(params,request)
     node = self.find_by_mac(params[:gw_id])
     pongstr = "Pong"
     if node.nil?
        node = self.create!(mac:params[:gw_id],belong_type:1)
        Auth.create!(auth_type:"radius",auth_device:false,access_node_id:node.id)
        Conf.create!(access_node_id:node.id)
     end
     if node
       wan_ip =  request.headers["action_dispatch.remote_ip"].to_s()
       if node.wan_ip.nil? or (wan_ip and wan_ip!= node.wan_ip) or true
           city=""
           detail=""
           province=""
           district=""
	   param = {}
	   param["ip"] = wan_ip
           uri = URI.parse("http://ip.taobao.com/service/getIpInfo.php")
           res = Net::HTTP.post_form(uri, param)

           h = JSON.parse res.body
           ss= h["data"]["region_id"]
           province=ss.encode("utf-8")
           ss= h["data"]["city_id"]
           city=ss.encode("utf-8")
           ss= h["data"]["county_id"]
           district=ss.encode("utf-8")
           logger.info city
           ad = Address.where(:access_node_id => node.id).first
	   if ad.nil?
              Address.create!(access_node_id:node.id,city:city,detail:detail,province:province,district:district)
           else
              ad.update_attributes(
                 :city => city,
                 :province => province,
                 :district => district
              )
           end
       end
       sys_uptime  = node.sys_uptime
       if params[:sys_uptime]
         sys_uptime=params[:sys_uptime]
       end
       sys_upload = node.sys_upload
       if params[:sys_upload]
         sys_upload = params[:sys_upload]
       end
       sys_memfree  = node.sys_memfree
       if params[:sys_memfree]
         sys_memfree=params[:sys_memfree]
       end
       update_time  = node.update_time
       if params[:wifidog_uptime]
         update_time=params[:wifidog_uptime]
       end
       ssid  = node.ssid
       if params[:ssid]
         ssid=params[:ssid]
       end
       node.update_attributes(
         :sys_uptime => sys_uptime,
         :sys_upload => sys_upload,
         :sys_memfree => sys_memfree,
         :update_time => update_time,
         :remote_addr => request.remote_addr,
         :wan_ip => wan_ip,
         :ssid => ssid,
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

  def self.ping_zj(params,request)
     node = self.find_by_dev_id(params[:dev_id])
     pongstr = "Pong"
     if node
       wan_ip =  request.headers["action_dispatch.remote_ip"].to_s()
       if node.wan_ip.nil? or (wan_ip and wan_ip!= node.wan_ip) or true
           city=""
           detail=""
           province=""
           district=""
	   param = {}
	   param["ip"] = wan_ip
           uri = URI.parse("http://ip.taobao.com/service/getIpInfo.php")
           res = Net::HTTP.post_form(uri, param)

           h = JSON.parse res.body
           ss= h["data"]["region_id"]
           province=ss.encode("utf-8")
           ss= h["data"]["city_id"]
           city=ss.encode("utf-8")
           ss= h["data"]["county_id"]
           district=ss.encode("utf-8")
           logger.info city
           ad = Address.where(:access_node_id => node.id).first
	   if ad.nil?
              Address.create!(access_node_id:node.id,city:city,detail:detail,province:province,district:district)
           else
              ad.update_attributes(
                 :city => city,
                 :province => province,
                 :district => district
              )
           end
       end
       node.update_attributes(
         :sys_uptime => params[:sys_uptime],
         :sys_upload => params[:sys_load],
         :sys_memfree => params[:sys_memfree],
         :update_time => params[:uptime],
         :remote_addr => request.remote_addr,
         :wan_ip => wan_ip,
         :ssid => params[:ssid],
         :last_seen => Time.now
       )
       
     end
     
     if node.cmdflag == true
        node.update_attributes( :cmdflag => false );
        pongstr = "Task"
     end
     pongstr
  end

  def self.ping_task(params,request)
     node = self.find_by_mac(params[:gw_id])
     if node.nil?
        node = self.create!(mac:params[:gw_id],name:params[:gw_id],belong_type:1)
        Auth.create!(auth_type:"radius",auth_device:false,access_node_id:node.id)
        Conf.create!(access_node_id:node.id)
     end
     pongstr = "Pong"
     if node
       wan_ip =  request.headers["action_dispatch.remote_ip"].to_s()
       if node.wan_ip.nil? or (wan_ip and wan_ip!= node.wan_ip) or true
           city=""
           detail=""
           province=""
           district=""
           param = {}
           param["ip"] = wan_ip
           uri = URI.parse("http://ip.taobao.com/service/getIpInfo.php")
           res = Net::HTTP.post_form(uri, param)

           h = JSON.parse res.body
           ss= h["data"]["region_id"]
           province=ss.encode("utf-8")
           ss= h["data"]["city_id"]
           city=ss.encode("utf-8")
           ss= h["data"]["county_id"]
           district=ss.encode("utf-8")
           logger.info city
           ad = Address.where(:access_node_id => node.id).first
           if ad.nil?
              Address.create!(access_node_id:node.id,city:city,detail:detail,province:province,district:district)
           else
              ad.update_attributes(
                 :city => city,
                 :province => province,
                 :district => district
              )
           end
           node.update_attributes(:belong_type => 1)
       end
       sys_uptime  = node.sys_uptime
       if params[:sys_uptime]
         sys_uptime=params[:sys_uptime]
       end
       sys_upload = node.sys_upload
       if params[:sys_upload]
         sys_upload = params[:sys_upload]
       end
       sys_memfree  = node.sys_memfree
       if params[:sys_memfree]
         sys_memfree=params[:sys_memfree]
       end
       update_time  = node.update_time
       if params[:wifidog_uptime]
         update_time=params[:wifidog_uptime]
       end
       ssid  = node.ssid
       if params[:ssid]
         ssid=params[:ssid]
       end

       node.update_attributes(
         :sys_uptime => sys_uptime,
         :sys_upload => sys_upload,
         :sys_memfree => sys_memfree,
         :update_time => update_time,
         :remote_addr => request.remote_addr,
         :wan_ip => wan_ip,
         :ssid => ssid,
         :last_seen => Time.now
       )

       if node.cmdflag == true
         #node.update_attributes( :cmdflag => false );
         #pongstr = "Task"
       end
     end
     pongstr
  end

  def self.retrieve(params)
    node = self.find_by_mac(params[:gw_id])
    str = "Cmd:"
    if !node.nodecmd.nil?
      str="Cmd:"+node.nodecmd.cmdline
    end
    str
  end

  def self.taskrequest(params)
    node = self.find_by_dev_id(params[:dev_id])
    x = {}
    sjson="{"
    if params[:message].nil?
        x["task_id"]="1"
        x["task_code"]=node.task_code
        x["task_params"]=node.task_params
        x["result"]="OK"
        x["code"]="0x0000"
        x["message"]="success"
    else 
        x["result"]="OK"
        x["code"]="0x000"
        x["message"]="success"
    end
    node.update_attributes( :last_seen => Time.now, :cmdflag=>false )
    x
  end

  def self.setconfigflag(params)
    node = self.find_by_mac(params[:gw_id])
    node.update_attributes( :configflag => true );
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
    str
  end

  def self.login(params)
    node = self.find_by_mac(params[:gw_id]) 
    conn =  Connection.where("expired_on > ? and mac = ? ",Time.now, params[:mac]).first
    if conn
       if conn.access_mac != node.mac
          nodepre = self.find_by_mac(conn.access_mac)
          guest1 = Guestnode.where("access_node_id = ?  ", nodepre.id).first
          guest2 = Guestnode.where("access_node_id = ?  ", node.id).first
          if guest1 and guest2
             if guest1.guest_id == guest2.guest_id
               token=SecureRandom.urlsafe_base64(nil, false)
               login_connection = Connection.create!(:token => token,
                                                :phonenum => conn.phonenum,
                                                :access_mac => node.mac,
                                                :device => "",
                                                :access_node_id => node.id,
                                                :roaming => 1,
                                                :expired_on => conn.expired_on,
                                                :portal_url => params[:url]
                                               )
               redirect_url ||= "http://#{params[:gw_address]}:#{params[:gw_port]}/ctbrihuang/auth?token=#{token}"
             end
          end
       end
    end
    if redirect_url
      redirect_url
    else
      if !node.redirect_url.blank?
        redirect_url = node.redirect_url
        if node.redirect_url.index("?")
           uri = URI.parse(node.redirect_url)
           if !uri.query.blank?
             redirect_url +="&" 
           end
        else
           redirect_url +="?"
        end
        redirect_url += "gw_address=#{params[:gw_address]}&gw_port=#{params[:gw_port]}&gw_id=#{params[:gw_id]}&url=#{params[:url]}&mac=#{params[:mac]}"
      end
      redirect_url ||= "/404"
    end
  end

  def self.login_zj(params)
    node = self.find_by_dev_id(params[:dev_id]) 
    mac=""
    if params[:client_mac]
      mac = params[:client_mac].gsub(/[:-]/, "").upcase
    end
    conn =  Connection.where("expired_on > ? and mac = ? ",Time.now, mac).first
    node = self.find_by_dev_id(params[:dev_id])
    if conn
       if conn.access_mac != node.mac
          nodepre = self.find_by_mac(conn.access_mac)
          guest1 = Guestnode.where("access_node_id = ?  ", nodepre.id).first
          guest2 = Guestnode.where("access_node_id = ?  ", node.id).first
          if guest1 and guest2
             logger.info guest1.guest_id
             logger.info guest2.guest_id
             logger.info "111111111"
             if guest1.guest_id == guest2.guest_id
               token=SecureRandom.urlsafe_base64(nil, false)
               login_connection = Connection.create!(:token => token,
                                                :phonenum => conn.phonenum,
                                                :access_mac => node.mac,
                                                :device => "",
                                                :access_node_id => node.id,
                                                :roaming => 1,
                                                :expired_on => conn.expired_on,
                                                :portal_url => params[:url]
                                               )
               redirect_url ||= "http://#{params[:gw_address]}:#{params[:gw_port]}/smartwifi/auth?token=#{token}&url=baidu.com"
               logger.info redirect_url
             end
          end
       end
    end
    if redirect_url
      redirect_url
    else
      if !node.redirect_url.blank?
        redirect_url = node.redirect_url
        if node.redirect_url.index("?")
           uri = URI.parse(node.redirect_url)
           if !uri.query.blank?
             redirect_url +="&" 
           end
        else
           redirect_url +="?"
        end
        redirect_url += "gw_address=#{params[:gw_address]}&gw_port=#{params[:gw_port]}&dev_id=#{params[:dev_id]}&url=#{params[:url]}&client_mac=#{params[:client_mac]}"
        redirect_url += "&gw_id=#{node.mac}&mac=#{params[:client_mac]}"
      end
      redirect_url ||= "/404"
    end
  end

  def self.portal(params)
    node = self.find_by_mac(params[:gw_id])
    conn =  Connection.where("expired_on > ? and mac = ? ",Time.now, params[:mac]).first
    
    if conn and conn.roaming == 1
      redirect_url = conn.portal_url
    else
      if !node.portal_url.blank?
        redirect_url = node.portal_url
        if node.portal_url.index("?")
           uri = URI.parse(node.portal_url)
           if !uri.query.blank?
             redirect_url +="&"
           end
        else
           redirect_url +="?"
        end
        redirect_url +=  "mac="+params[:mac].to_s
      end
      redirect_url ||=  "http://www.baidu.com"
    end
  end
  
  def self.portal_zj(params)
    node = self.find_by_dev_id(params[:dev_id])
    unless node
      redirect_url = "/404"
    else
      if !node.portal_url.blank?
        redirect_url = node.portal_url
        if node.portal_url.index("?")
           uri = URI.parse(node.portal_url)
           if !uri.query.blank?
             redirect_url +="&"
           end
        else
           redirect_url +="?"
        end
        redirect_url +=  "url="+params[:url].to_s
      end
      redirect_url ||=  "http://www.baidu.com"
    end
  end

  def self.authenticate(params,device)
    node = self.find_by_mac(params[:gw_id])
    if node.nil? or  params[:gw_id].nil? or params[:gw_address].nil? or params[:gw_port].nil? or !node.auth.check_device(device)
      redirect_url = "/404"
    else
      #unless node.auth.authenticate params[:username],params[:checkcode],"local"
      unless true
        redirect_url = node.redirect_url+"&gw_address=#{params[:gw_address]}&gw_port=#{params[:gw_port]}&gw_id=#{params[:gw_id]}&public_ip=124.127.116.177&mac=#{params[:mac]}"
      else
        token=SecureRandom.urlsafe_base64(nil, false)
        curcon=Connection.find(:first, :conditions => ["mac = ? and expired_on > NOW()",params[:mac]])
        logger.info(token)
        if curcon
           token=curcon.token
           logger.info(token)
        else
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
        end
        if node.auth_plattype==1
           {:check=>true,:code=>200, :token=>"#{token}", :msg=>"OK",:auth_url=> "http://#{params[:gw_address]}:#{params[:gw_port]}/ctbrihuang/auth?token=#{token}"}
        else 
          if node.auth_plattype==2
            {:check=>true,:code=>200, :token=>"#{token}", :msg=>"OK",:auth_url=> "http://#{params[:gw_address]}:#{params[:gw_port]}/smartwifi/auth?token=#{token}&url=baidu.com"}
       
          else
             redirect_url ||= "http://#{params[:gw_address]}:#{params[:gw_port]}/ctbrihuang/auth?token=#{token}"
          end
        end
      end
    end
  end

  def self.freeland(params)
    node = self.find_by_mac(params[:gw_id])
    if node.nil? or  params[:gw_id].nil? or params[:gw_address].nil? or params[:gw_port].nil? or params[:mac].nil? 
      return {:check=>false, :code=>102, :msg=>"Params Not Enough"}
    else
      token=SecureRandom.urlsafe_base64(nil, false)
      if !node.time_limit.nil? and node.time_limit > 0
        login_connection = Connection.create!(:token => token,
                                              :access_mac => params[:gw_id],
                                              :mac => params[:mac],
                                              :access_node_id => node.id,
                                              :expired_on => Time.now+node.time_limit.minutes,
                                              :portal_url => params[:url]
                                             )
      else
        login_connection = Connection.create!(:token => token,
                                              :access_mac => params[:gw_id],
                                              :mac => params[:mac],
                                              :access_node_id => node.id,
                                              :expired_on => Time.now+30.minutes,
                                              :portal_url => params[:url]
                                             )
      end
      redirect_url = "http://#{params[:gw_address]}:#{params[:gw_port]}/ctbrihuang/auth?token=#{token}"
    end
    {:check=>true, :code=>200, :msg=>redirect_url }
  end
end

