# frozen_string_literal: true

require "async/redis"

module Jiggler
  class AsyncRedisStore
    attr_reader :client

    def initialize(options = {})
      @options = options
      endpoint = options[:redis_url].is_a?(String) ? 
        make_redis_endpoint(URI(options[:redis_url])) : Async::Redis.local_endpoint 
      @client = Async::Redis::Client.new(endpoint, **options.slice(:concurrency))
    end

    private

    def make_redis_endpoint(uri)
      tcp_endpoint = Async::IO::Endpoint.tcp(uri.hostname, uri.port)
      case uri.scheme
      when "redis"
        tcp_endpoint
      when "rediss"
        ssl_context = OpenSSL::SSL::SSLContext.new
        ssl_context.set_params(
          ca_file: @options[:ca_file],
          cert: OpenSSL::X509::Certificate.new(File.read(@options[:cert])),
          key: OpenSSL::PKey::RSA.new(File.read(@options[:key])),
        )
        Async::IO::SSLEndpoint.new(tcp_endpoint, ssl_context: ssl_context)
      else
        raise ArgumentError
      end
    end
  end
end
