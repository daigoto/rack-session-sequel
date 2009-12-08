require 'rack/session/abstract/id'
require 'sequel'

module Rack
  module Session
    # Rack::Session::Sequel provides simple cookie based session management.
    # Session data is stored in database. The corresponding session key is
    # maintained in the cookie.It made it referring to Rack::Session::Memcache.
    # And is compatible with Rack::Session::Memcache.

    class Sequel < Abstract::ID
      attr_reader :mutex, :dataset
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge \
      :namespace => 'rack:session'

      def initialize(app, options={})
        super
        @mutex = Mutex.new
        if options.key? :dataset
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
          session = Marshal.load(data[:session].unpack("m*").first) if data
        end
        @mutex.lock if env['rack.multithread']
        unless sid and session
          env['rack.errors'].puts("Session '#{sid.inspect}' not found, initializing...") if $VERBOSE and not sid.nil?
          session = {}
          sid = generate_sid
          @dataset.insert(
            :sid       => sid,
            :session   => [Marshal.dump(session)].pack('m*'),
            :update_at => Time.now.utc
          )
        end
warn "get_session#{generate_sid}"
        session.instance_variable_set('@old', {}.merge(session))
        return [sid, session]
      rescue 
        warn $!.inspect
        return [ nil, {} ]
      ensure
        @mutex.unlock if env['rack.multithread']
      end

      def set_session(env, session_id, new_session, options)
warn "set_session#{session_id}"
        expiry = options[:expire_after]
        expiry = expiry.nil? ? 0 : expiry + 1

warn "set_session#{session_id}"
        @mutex.lock if env['rack.multithread']
        data = @dataset.filter('sid = ?', session_id).first
warn "set_session#{session_id}"
        session = {}
warn "set_session#{session_id}:#{data[:session]}:#{data[:session].unpack("m*")}"
        if data[:session]
          session = Marshal.load(data[:session].unpack("m*").first) 
        end
warn "set_session#{session_id}:#{options[:renew]}:#{options[:drop]}"
        if options[:renew] or options[:drop]
          data.delete if data
          return false if options[:drop]
          session_id = generate_sid # change new session_id
          renew_session = {}
          @dataset.insert(
            :sid       => session_id,
            :session   => [Marshal.dump(renew_session)].pack('m*'),
            :update_at => Time.now.utc
          )
        end
warn "set_session#{session_id}"
        old_session = new_session.instance_variable_get('@old') || {}
warn "set_session#{session_id}"
        session = merge_sessions session_id, old_session, new_session, session
warn "set_session#{session_id}"
        @dataset.filter('sid = ?', session_id).update(
          :session   => [Marshal.dump(session)].pack('m*'),
          :update_at => Time.now.utc
        )
warn "set_session#{session_id}"
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
        warn "//@#{sid}: delete #{delete*','}" if $VERBOSE and not delete.empty?
        delete.each{|k| cur.delete k }

        update = new.keys.select{|k| new[k] != old[k] }
        warn "//@#{sid}: update #{update*','}" if $VERBOSE and not update.empty?
        update.each{|k| cur[k] = new[k] }
        cur
      end
    end
  end
end

