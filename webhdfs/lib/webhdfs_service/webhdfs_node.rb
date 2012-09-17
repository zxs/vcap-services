# Copyright (c) 2009-2011 VMware, Inc.
require "fileutils"
require "logger"
require "datamapper"
require "uuidtools"

require "rkerberos"
require "webhdfs"


$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..', '..', 'base', 'lib')
require 'base/node'

module VCAP
  module Services
    module WebHDFS
      class Node < VCAP::Services::Base::Node
      end
    end
  end
end

require "webhdfs_service/common"
require "webhdfs_service/webhdfs_error"

class VCAP::Services::WebHDFS::Node

  include VCAP::Services::WebHDFS::Common
  include VCAP::Services::WebHDFS

  class ProvisionedService
    include DataMapper::Resource
    property :name,       String,   :key => true
#    property :host,       String,   :required => true
#    property :port,       Integer,  :required => true
    property :user,       String,   :required => true   # :user is the same with :name
    property :password,   String,   :required => true
    property :homedir,		String,		:required => false
    property :binder,			String,		:required => false
    property :plan,       Enum[:free], :required => true
  end

  def initialize(options)
    super(options)

    @base_dir = options[:base_dir]
    FileUtils.mkdir_p(@base_dir)
    @local_db = options[:local_db]
    @webhdfs_config = options[:webhdfs]

    @kadm5_user = options[:kadm5_user]
    @kadm5_pass = options[:kadm5_pass]
    @hdfs_keytab = options[:hdfs_keytab]
		@hdfs_princ = keytab_hdfs_princ(@hdfs_keytab)

    @logger.debug("xxxxxx ---- init : #{@webhdfs_config}")
  end

  def pre_send_announcement
    super
    start_db
    ProvisionedService.all.each do |instance|
#      @available_memory -= (instance.memory || @max_memory)
    end
  end

  def announcement
    a = {
	      :available_capacity => @capacity,
        :capacity_unit => capacity_unit 
    }
  end

  def provision(plan, credentials = nil)
    @logger.debug("xxxxxx ---- provision : #{credentials}, #{plan}")
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_INVALID_PLAN, plan) unless plan == @plan
    provisioned_service = ProvisionedService.new
    provisioned_service.plan = plan

    if credentials
      name, user, password, binder = %w(name user password).map{|key| credentials[key]}
      provisioned_service.name = name
      provisioned_service.user = user
      provisioned_service.password = password
      provisioned_service.binder = binder
    else
      provisioned_service.name = 'fU' + UUIDTools::UUID.random_create.to_s.gsub(/-/, '')
      provisioned_service.user = provisioned_service.name       
      provisioned_service.password = 'p' + UUIDTools::UUID.random_create.to_s
      provisioned_service.binder = 'bU' + UUIDTools::UUID.random_create.to_s.gsub(/-/, '')
    end

	  kadm_add_princ({
	    "princ_name" => provisioned_service.user,
	    "princ_pass" => provisioned_service.password,
	    "kadm5_user" => @kadm5_user,
	    "kadm5_pass" => @kadm5_pass
	  })

    provisioned_service.homedir = webhdfs_get_home({
	    "host"  =>  @webhdfs_config["host"],
	    "port"  =>  @webhdfs_config["port"],
	    "user"  =>  provisioned_service.user,
	    "pass"  =>  provisioned_service.password,
	    "hdfs_princ" =>  @hdfs_princ,
	    "hdfs_keytab" =>  @hdfs_keytab
	  })  
   
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_SAVE_INSTANCE_FAILED, provisioned_service.inspect) unless provisioned_service.save

    response = {
      "hostname" => @webhdfs_config["host"],
      "host" => @webhdfs_config["host"],
      "port" => @webhdfs_config["port"],
      "name" => provisioned_service.name,
      "user" => provisioned_service.user,
      "username" => provisioned_service.user,
      "password" => provisioned_service.password,
      "homedirectory" => provisioned_service.homedir,
      "binder" => provisioned_service.binder
    }
    @logger.debug("Provision response: #{response.inspect}")

    return response
  rescue => e
    @logger.error("Error provision instance: #{e}")
    #record_service_log(provisioned_service.name)
    cleanup_service(provisioned_service)
    raise e
  end


  def unprovision(name, credentials=[])
    return if name.nil?
    @logger.debug("Unprovision dfs:#{name} and its #{credentials.size} bindings")

    provisioned_service = ProvisionedService.get(name)
		raise WebHDFSError.new(WebHDFSError::WEBHDFS_CONFIG_NOT_FOUND, name)  if provisioned_service.nil?
	  @logger.debug("#{provisioned_service.inspect}")

    begin
      credentials.each{ |credential| unbind(credential)} if credentials
    rescue =>e
      # ignore error, only log it
      @logger.warn("Error found in unbind operation:#{e}")
    end

		webhdfs_drop_home({
      "host" => @webhdfs_config["host"],
      "port" => @webhdfs_config["port"],
      "user" => provisioned_service.user,
      "pass" => provisioned_service.password,
      "homedir" 		=> provisioned_service.homedir,
	    "hdfs_princ" 	=>  @hdfs_princ,
	    "hdfs_keytab" =>  @hdfs_keytab
		}) 

  	kadm_del_princ({
	    "princ_name" => provisioned_service.user,
	    "kadm5_user" => @kadm5_user,
	    "kadm5_pass" => @kadm5_pass
		})		 
  
    if not provisioned_service.destroy
      @logger.error("Could not delete service: #{provisioned_service.errors.inspect}")
      raise WebHDFSError.new(WebHDFSError::WEBHDFS_DESTORY_INSTANCE_FAILED )
    end    
    
    @logger.info("Successfully fulfilled unprovision request: #{name}.")
    true
  end


  def bind(name, bind_opts, credential=nil)
    @logger.debug("Bind service for dfs=#{name}, bind_opts = #{bind_opts}, credential=#{credential.inspect}")
    provisioned_service = ProvisionedService.get(name)
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_CONFIG_NOT_FOUND, name) unless provisioned_service
    
    @logger.debug("Get service: #{provisioned_service.inspect}")
    
  	binder = credential && credential['binder'] ? credential['binder'] : UUIDTools::UUID.random_create.to_s.gsub(/-/, '')

    response = {
        "hostname" => @webhdfs_config["host"],
        "host" => @webhdfs_config["host"],
        "port" => @webhdfs_config["port"],
        "name" => name,
        "user" => provisioned_service.user,
        "username" => provisioned_service.user,
        "password" => provisioned_service.password,
        "homedirectory" => provisioned_service.homedir,
        "binder" => binder,
    }
    @logger.debug("Bind response: #{response.inspect}")
    return response
  end

  def unbind(credential)
    @logger.info("Unbind request: credential=#{credential}")
    name = credential['name']
    provisioned_service = ProvisionedService.get(name)
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_CONFIG_NOT_FOUND, name) unless provisioned_service
	
		# provisioned_service.binder = nil

    @logger.debug("Successfully unbind #{credential}")
    true
  end


  def start_db
    DataMapper.setup(:default, @local_db)
    DataMapper::auto_upgrade!
  end

  def keytab_hdfs_princ(hdfs_keytab)
    @logger.debug("xxxxxx ---- keytab_hdfs_princ : #{hdfs_keytab}")
    hdfs_princ = nil
    keytab = Kerberos::Krb5::Keytab.new( hdfs_keytab )
    keytab.each{ |entry|
      if entry.principal.start_with?("hdfs")
        hdfs_princ = entry.principal
        break
      end
    }
		hdfs_princ
  end
  
  def  kadm_add_princ(opt)
    @logger.debug("xxxxxx ---- kadm_add_princ: #{opt}")
    kadm5 = Kerberos::Kadm5.new(:principal => opt["kadm5_user"], :password => opt["kadm5_pass"])
    result = kadm5.create_principal(opt["princ_name"], opt["princ_pass"])
    princ = kadm5.get_principal(opt["princ_name"])
    @logger.info("xxxxxx ---- princ=")
  end

  def webhdfs_get_home(info)
    @logger.debug("xxxxxx ---- webhdfs_get_home : #{info}")
   
    client = WebHDFS::Client.new
    client.host = info["host"]
    client.port = info["port"]
    client.auth_type  = :kerberos
    #
    client.username=info["user"]
    client.pass_keytab=info["pass"]
    homedir = client.gethomedirectory()
    @logger.info("To mkdir homedir:" + homedir)
    #
    client.username   = info["hdfs_princ"]
    client.pass_keytab= info["hdfs_keytab"]
    client.mkdir(homedir)
    client.setowner(homedir, {:owner=>info["user"],:group=>info["user"]} )
    
    return homedir
  end
  
  def webhdfs_drop_home(info) 
	  @logger.debug("xxxxxx ---- webhdfs_drop_home : #{info}")
    client = WebHDFS::Client.new
    client.host = info["host"]
    client.port = info["port"]
    client.auth_type  = :kerberos
    #
    client.username=info["user"]
    client.pass_keytab=info["pass"]
    homedir = info["homedir"] ? client.gethomedirectory(): info["homedir"]
    @logger.info("To delete homedir:" + homedir)
    #
    client.username   = info["hdfs_princ"]
    client.pass_keytab= info["hdfs_keytab"]
    client.delete(homedir, {"recursive"=>"true"})          
  end

  def kadm_del_princ(opt)
    @logger.debug("xxxxxx ---- kadm_del_princ: #{opt}")
    kadm5 = Kerberos::Kadm5.new(:principal => opt["kadm5_user"], :password => opt["kadm5_pass"])
    result = kadm5.delete_principal(opt["princ_name"])
    @logger.info("xxxxxx ---- #{result}")    
  end

  def save_service( provisioned_service )
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_SAVE_INSTANCE_FAILED, provisioned_service.inspect) unless provisioned_service.save
  end

  def destroy_service(provisioned_service)
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_DESTORY_INSTANCE_FAILED, provisioned_service.inspect) unless provisioned_service.destroy
  end

  def get_service(name)
    provisioned_service = ProvisionedService.get(name)
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_FIND_INSTANCE_FAILED, name) if provisioned_service.nil?
    provisioned_service
  end

  def cleanup_service(provisioned_service)
    err_msg = []
    begin
      destroy_service(provisioned_service)
    rescue => e
      err_msg << e.message
    end
    raise WebHDFSError.new(WebHDFSError::WEBHDFS_CLEANUP_INSTANCE_FAILED, err_msg.inspect) if err_msg.size > 0
  end





end
