require 'http/parser'
require 'goliath/env'

module Goliath
  # @private
  class Connection < EM::Connection
    include Constants

    attr_accessor :app, :port, :logger, :status, :config, :options
    attr_reader   :parser

    AsyncResponse = [-1, {}, []].freeze

    def post_init
      @current = nil
      @requests = []
      @pending  = []

      @parser = Http::Parser.new
      @parser.on_headers_complete = proc do |h|

        env = Goliath::Env.new
        env[OPTIONS]     = options
        env[SERVER_PORT] = port.to_s
        env[LOGGER]      = logger
        env[OPTIONS]     = options
        env[STATUS]      = status
        env[CONFIG]      = config
        env[REMOTE_ADDR] = remote_address

        r = Goliath::Request.new(@app, self, env)
        r.parse_header(h, @parser)

        @requests.push r
      end

      @parser.on_body = proc do |data|
        @requests.first.parse(data)
      end

      @parser.on_message_complete = proc do
        req = @requests.shift

        if @current.nil?
          @current = req
          @current.succeed
        else
          @pending.push req
        end

        req.process
      end
    end

    def receive_data(data)
      begin
        @parser << data
      rescue HTTP::Parser::Error => e
        terminate_request(false)
      end
    end

    def unbind
      @requests.map {|r| r.close }
    end

    def terminate_request(keep_alive)
      if req = @pending.shift
        @current = req
        @current.succeed
      else
        @current = nil
      end

      close_connection_after_writing rescue nil if !keep_alive
    end

    def remote_address
      Socket.unpack_sockaddr_in(get_peername)[1]
    rescue Exception
      nil
    end

  end
end
