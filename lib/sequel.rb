require 'rack/session/abstract/id'
require 'sequel'

module Rack
  module Session
    # Rack::Session::Sequel provides simple cookie based session 
management.
    # Session data is stored in database. The corresponding session key 
is
    # maintained in the cookie.It made it referring to 
Rack::Session::Memcache.
    # And is compatible with Rack::Session::Memcache.

    class Sequel < Abstract::ID
      attr_reader :mutex, :dataset
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge :namespace 
=> 'rack:session'

      def initialize(app, options={})
        super
        @mutex = Mutex.new
        if options.keys? :dataset
          @dataset = options[:dataset] 
        else
          raise 'No Sequel Dataset'
        end
      end

      def generate_sid
        loop do
          sid = super
          break sid unless @dataset.filter('sid = ?', sid).first
        end
      end

      def get_session(env, sid)
        if sid
          data = @dataset.filter('sid = ?', sid).first
          session = Marshal.load(data[:session].unpack("m*")) if data
        end
        @mutex.lock if env['rack.multithread']
        unless sid and session
          env['rack.errors'].puts("Session '#{sid.inspect}' not found, 
initializing...") if $VERBOSE and not sid.nil?
          session = {}
          @dataset.insert(
            :sid       => generate_sid,
            :session   => [Marshal.dump(session)].pack('m*'),
            :update_at => Time.now.utc
          )
        end
        session.instance_variable_set('@old', {}.merge(session))
        return [sid, session]
      rescue 
        warn $!.inspect
        return [ nil, {} ]
      ensure
        @mutex.unlock if env['rack.multithread']
      end

      def set_session(env, session_id, new_session, options)
        expiry = options[:expire_after]
        expiry = expiry.nil? ? 0 : expiry + 1

        @mutex.lock if env['rack.multithread']
        data = @dataset.filter('sid = ?', session_id).first
        session = Marshal.load(data[:session].unpack("m*")) ||= {}
        if options[:renew] or options[:drop]
          data.delete if data
          return true if options[:drop]
          session_id = generate_sid # change new session_id
          @dataset.insert(
            :sid       => session_id,
            :session   => [Marshal.dump({})].pack('m*'),
            :update_at => Time.now.utc
          )
        end
        old_session = new_session.instance_variable_get('@old') || {}
        session = merge_sessions session_id, old_session, new_session, 
session
        @dataset.filter('sid = ?', session_id).update(
          :session   => [Marshal.dump(session)].pack('m*'),
          :update_at => Time.now.utc
        )
        return session_id
      rescue 
        warn $!.inspect
        return false
      ensure
        @mutex.unlock if env['rack.multithread']
      end

      private

      def merge_sessions sid, old, new, cur=nil
        cur ||= {}
        unless Hash === old and Hash === new
          warn 'Bad old or new sessions provided.'
          return cur
        end

        delete = old.keys - new.keys
        warn "//@#{sid}: delete #{delete*','}" if $VERBOSE and not 
delete.empty?
        delete.each{|k| cur.delete k }

        update = new.keys.select{|k| new[k] != old[k] }
        warn "//@#{sid}: update #{update*','}" if $VERBOSE and not 
update.empty?
        update.each{|k| cur[k] = new[k] }
        cur
      end
    end
  end
end

