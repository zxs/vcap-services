# Copyright (c) 2009-2011 VMware, Inc.
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..', '..', 'base', 'lib')

require 'base/provisioner'
require 'postgresql_service/common'

class VCAP::Services::Postgresql::Provisioner < VCAP::Services::Base::Provisioner

  include VCAP::Services::Postgresql::Common

  def node_score(node)
    node['available_storage'] if node
  end

end
