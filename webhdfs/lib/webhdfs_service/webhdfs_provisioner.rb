# Copyright (c) 2009-2011 VMware, Inc.
require 'webhdfs_service/common'

class VCAP::Services::WebHDFS::Provisioner < VCAP::Services::Base::Provisioner

  include VCAP::Services::WebHDFS::Common

  def node_score(node)
    @logger.debug("XXXXXXXXXXXXXXX------------ #{node} ")
    node['available_capacity'] if node	   
  end

end
