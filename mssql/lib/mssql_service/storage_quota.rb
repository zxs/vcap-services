# Copyright (c) 2009-2011 VMware, Inc.

module VCAP; module Services; module Mssql; end; end; end

class VCAP::Services::Mssql::Node

  DATA_LENGTH_FIELD = 6

  def dbs_size()
    # result = @dbh.query('show databases')
    # dbs =[]
    # result.each {|db| dbs << db[0]}
    # sizes = @dbh.query(
    #   'SELECT table_schema "name",
    #    sum( data_length + index_length ) "size"
    #    FROM information_schema.TABLES
    #    GROUP BY table_schema')
    # result ={}
    # sizes.each do |i|
    #   name, size = i
    #   result[name] = size.to_i
    # end
    # # assume 0 size for db which has no tables
    # dbs.each {|db| result[db] = 0 unless result.has_key? db}
    # result
  end

  def kill_user_sessions(target_user, target_db)
    # process_list = @dbh.list_processes
    # process_list.each do |proc|
    #   thread_id, user, _, db = proc
    #   if (user == target_user) and (db == target_db) then
    #     @dbh.query('KILL CONNECTION ' + thread_id)
    #   end
    # end
  end

  def access_disabled?(db)
    # rights = @dbh.query("SELECT insert_priv, create_priv, update_priv
    #                             FROM db WHERE Db=" +  "'#{db}'")
    # rights.each do |right|
    #   if right.include? 'Y' then
    #     return false
    #   end
    # end
    true
  end

  def grant_write_access(db, service)
    # @logger.warn("DB permissions inconsistent....") unless access_disabled?(db)
    # @dbh.query("UPDATE db SET insert_priv='Y', create_priv='Y',
    #                    update_priv='Y' WHERE Db=" +  "'#{db}'")
    # @dbh.query("FLUSH PRIVILEGES")
    # # kill existing session so that privilege take effect
    # kill_database_session(db)
    service.quota_exceeded = false
    service.save
  end

  def revoke_write_access(db, service)
    # @logger.warn("DB permissions inconsistent....") if access_disabled?(db)
    # @dbh.query("UPDATE db SET insert_priv='N', create_priv='N',
    #                    update_priv='N' WHERE Db=" +  "'#{db}'")
    # @dbh.query("FLUSH PRIVILEGES")
    # kill_database_session(db)
    service.quota_exceeded = true
    service.save
  end

  def fmt_db_listing(user, db, size)
    "<user: '#{user}' name: '#{db}' size: #{size}>"
  end

  def enforce_storage_quota
    @logger.debug("enforce_storage_quota NOOP")
    # @dbh.select_db('mysql')
    # sizes = dbs_size
    # ProvisionedService.all.each do |service|
    #   db, user, quota_exceeded = service.name, service.user, service.quota_exceeded
    #   size = sizes[db]
    #   # ignore the orphan instance
    #   next if size.nil?

    #   if (size >= @max_db_size) and not quota_exceeded then
    #     revoke_write_access(db, service)
    #     @logger.info("Storage quota exceeded :" + fmt_db_listing(user, db, size) +
    #                  " -- access revoked")
    #   elsif (size < @max_db_size) and quota_exceeded then
    #     grant_write_access(db, service)
    #     @logger.info("Below storage quota:" + fmt_db_listing(user, db, size) +
    #                  " -- access restored")
    #   end
    # end
    # rescue Mssql::Error => e
    #   @logger.warn("MySQL exception: [#{e.errno}] #{e.error} " +
    #                e.backtrace.join("|"))
  end

  def kill_database_session(database)
    @logger.info("Kill all sessions connect to db: #{database}")
    process_list = @dbh.list_processes
    process_list.each do |proc|
      thread_id, user, _, db, command, time, _, info = proc
      if (db == database) and (user != "root")
        @dbh.query("KILL #{thread_id}")
        @logger.info("Kill session: user:#{user} db:#{db}")
      end
    end
  end

end
