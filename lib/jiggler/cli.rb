# frozen_string_literal: true

require 'singleton'
require 'optparse'
require 'yaml'
require 'async'
require 'async/io/trap'
require 'async/pool'

# require jiggler server classes
require 'jiggler/support/helper'
require 'jiggler/scheduled/enqueuer'
require 'jiggler/scheduled/poller'
require 'jiggler/stats/collection'
require 'jiggler/stats/monitor'
require 'jiggler/errors'
require 'jiggler/retrier'
require 'jiggler/launcher'
require 'jiggler/manager'
require 'jiggler/worker'

module Jiggler
  class CLI
    include Singleton
    CONTEXT_SWITCHER_THRESHOLD = 0.5

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
      },
      :HUP => ->(cli) {
        cli.logger.info('Received SIGHUP, no longer accepting new work')
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
      @cond = Async::Condition.new
      Async do
        setup_signal_handlers
        patch_scheduler
        @launcher = Launcher.new(config)
        @launcher.start
        Async do
          @cond.wait
        end
      end
      @switcher&.exit
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
    def patch_scheduler
      @switcher = Thread.new(Fiber.scheduler) do |scheduler|
        loop do
          sleep(CONTEXT_SWITCHER_THRESHOLD)
          switch = scheduler.context_switch
          next if switch.nil?
          next if Process.clock_gettime(Process::CLOCK_MONOTONIC) - switch < CONTEXT_SWITCHER_THRESHOLD

          Process.kill('URG', Process.pid)
        end
      end

      Signal.trap('URG') do
        next Fiber.scheduler.context_switch!(nil) unless Async::Task.current?
        Async::Task.current.yield
      end

      Fiber.scheduler.instance_eval do
        def context_switch
          @context_switch
        end

        def context_switch!(value = Process.clock_gettime(Process::CLOCK_MONOTONIC))
          @context_switch = value
        end

        def block(...)
          context_switch!(nil)
          super
        end

        def kernel_sleep(...)
          context_switch!(nil)
          super
        end

        def resume(fiber, *args)
          context_switch!
          super
        end
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
      [:concurrency, :timeout].each do |opt|
        raise ArgumentError, "#{opt}: #{config[opt]} is not a valid value" if config[opt].to_i <= 0
      end
    end

    def parse_options(argv)
      opts = {}
      @parser = option_parser(opts)
      @parser.parse!(argv)
      opts
    end

    def option_parser(opts)
      parser = OptionParser.new do |o|
        o.on '-c', '--concurrency INT', 'Number of fibers to use' do |arg|
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

      if opts[:config_file]
        unless File.exist?(opts[:config_file])
          raise ArgumentError, "No such file #{opts[:config_file]}"
        end
      end

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
