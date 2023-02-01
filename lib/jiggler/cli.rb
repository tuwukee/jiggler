# frozen_string_literal: true

require 'singleton'
require 'optparse'
require 'yaml'
require 'erb'
require 'async'
require 'async/io/trap'
require 'async/pool'

module Jiggler
  class CLI
    include Singleton

    attr_reader :logger, :config, :environment

    SIGNAL_HANDLERS = {
      :INT => ->(cli) {
        cli.logger.fatal('Received INT, shutting down')
        cli.stop 
      },
      :TERM => ->(cli) {
        cli.logger.fatal('Received TERM, shutting down')
        cli.stop 
      },
      :TSTP => ->(cli) {
        cli.logger.info('Received TSTP, no longer accepting new work')
        cli.suspend
      }
    }
    UNHANDLED_SIGNAL_HANDLER = ->(cli) { cli.logger.info('No signal handler registered, ignoring') }
    SIGNAL_HANDLERS.default = UNHANDLED_SIGNAL_HANDLER
    SIGNAL_HANDLERS.freeze
    
    def parse_and_init(args = ARGV.dup)
      @config ||= Jiggler.config

      setup_options(args)
      initialize_logger
      validate!
      load_app
    end

    def start
      return unless ping_redis
      @cond = Async::Condition.new
      scheduler_loop = Fiber.current
      Async do
        setup_signal_handlers
        cleanup = patch_scheduler(scheduler_loop, config[:fiber_switcher_threshold])
        @launcher = Launcher.new(config).tap(&:start)
        Async { @cond.wait }
      ensure
        cleanup.call
      end
    end

    def stop
      @launcher.stop
      logger.info('Jiggler is stopped, bye!')
      @cond.signal
    end

    def suspend
      @launcher.suspend
      logger.info('Jiggler is suspended')
    end

    private

    # forces scheduler to switch fibers if they take more than threshold to execute
    def patch_scheduler(scheduler_fiber, threshold)
      switch_value = Struct.new(:switched_at).new

      thr = Thread.new(switch_value) do |switch_value|
        loop do
          sleep(threshold)
          transfer = switch_value.switched_at
          next if transfer.nil?
          Process.kill('URG', Process.pid) if now - transfer > threshold
        end
      end

      Signal.trap('URG') do
        next unless Async::Task.current? # shouldn't really happen
        Async::Task.current.yield
      end

      tp = TracePoint.trace(:fiber_switch) do |tp|
        update = Fiber.current.object_id != scheduler_fiber
        switch_value.switched_at = update ? now : nil
      end

      -> do
        thr.exit
        tp.disable
      end
    end

    def setup_signal_handlers
      SIGNAL_HANDLERS.each do |signal, handler|
        trap = Async::IO::Trap.new(signal)
        trap.install!
        Async(transient: true) do
          trap.wait
          invoked_traps[signal] += 1
          handler.call(self)
        end
      end
    end

    def invoked_traps
      @invoked_traps ||= Hash.new { |h, k| h[k] = 0 }
    end

    def validate!
      if config[:queues].any? { |q| q.include?(':') }
        raise ArgumentError, 'Queue names cannot contain colons'
      end

      [:concurrency, :client_concurrency, :timeout].each do |opt|
        raise ArgumentError, "#{opt}: #{config[opt]} is not a valid value" if config[opt].to_i <= 0
      end
    end

    def parse_options(argv)
      opts = {}
      @parser = option_parser(opts)
      @parser.parse!(argv)
      opts
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def option_parser(opts)
      parser = OptionParser.new do |o|
        o.on '-c', '--concurrency INT', 'Number of fibers to use on the server' do |arg|
          opts[:concurrency] = Integer(arg)
        end

        o.on '-e', '--environment ENV', 'Application environment' do |arg|
          opts[:environment] = arg
        end

        o.on '-q', '--queue QUEUE1,QUEUE2', 'Queues to process' do |arg|
          opts[:queues] ||= []
          arg.split(',').each do |queue|
            opts[:queues] << queue
          end
        end

        o.on '-r', '--require PATH', 'File to require' do |arg|
          opts[:require] = arg
        end

        o.on '-t', '--timeout NUM', 'Shutdown timeout' do |arg|
          opts[:timeout] = Integer(arg)
        end

        o.on '-v', '--verbose', 'Print more verbose output' do |arg|
          opts[:verbose] = arg
        end

        o.on '-C', '--config PATH', 'Path to YAML config file' do |arg|
          opts[:config_file] = arg
        end

        o.on '-V', '--version', 'Print version and exit' do
          puts("Jiggler #{Jiggler::VERSION}")
          exit(0)
        end

        o.on_tail '-h', '--help', 'Show help' do
          puts o 
          exit(0)
        end
      end
      parser.banner = 'Jiggler [options]'
      parser
    end

    def setup_options(args)
      opts = parse_options(args)

      set_environment(opts)

      opts = parse_config(opts[:config_file]).merge(opts) if opts[:config_file]
      opts[:queues] = [Jiggler::Config::DEFAULT_QUEUE] if opts[:queues].nil?
      opts[:server_mode] = true # cli starts only in server mode
      config.merge!(opts)
    end

    def set_environment(opts)
      opts[:environment] ||= ENV['APP_ENV'] || 'development'
      @environment = opts[:environment]
    end

    def initialize_logger
      @logger = config.logger
      logger.level = ::Logger::DEBUG if config[:verbose]
    end

    def symbolize_keys_deep!(hash)
      hash.keys.each do |k|
        symkey = k.respond_to?(:to_sym) ? k.to_sym : k
        hash[symkey] = hash.delete k
        symbolize_keys_deep! hash[symkey] if hash[symkey].is_a? Hash
      end
    end

    def parse_config(path)
      erb = ERB.new(File.read(path))
      erb.filename = File.expand_path(path)
      opts = YAML.safe_load(erb.result, permitted_classes: [Symbol], aliases: true) || {}

      symbolize_keys_deep!(opts)

      opts = opts.merge(opts.delete(environment.to_sym) || {})
      opts.delete(:strict)

      opts
    rescue => error
      raise ArgumentError, "Error parsing config file: #{error.message}"
    end

    def ping_redis
      config.with_sync_redis { |conn| conn.call('PING') }
      true
    rescue => err
      logger.fatal("Redis connection error: #{err.message}")
      false
    end

    def load_app
      if config[:require].nil? || config[:require].empty?
        logger.warn('No require option specified. Please specify a Ruby file to require with --require')
        # allow to start empty server
        return
      end
      # the code required by this file is expected to call Jiggler.configure
      # thus it'll be executed in the context of the current process
      # and apply the configuration for the server
      require config[:require]
    rescue LoadError => e
      logger.fatal("Could not load jobs: #{e.message}")
      exit(1)
    end
  end
end
