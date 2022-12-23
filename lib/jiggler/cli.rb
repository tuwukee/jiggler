# frozen_string_literal: true

require 'singleton'
require 'optparse'
require 'async/io/trap'
require 'erb'
require 'debug'
require 'yaml'

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
        cli.quite
      },
      :TTIN => ->(cli) {
        # log running tasks here (+ backtrace)
      }
    }
    UNHANDLED_SIGNAL_HANDLER = ->(cli) { cli.logger.info('No signal handler registered, ignoring') }
    SIGNAL_HANDLERS.default = UNHANDLED_SIGNAL_HANDLER
    SIGNAL_HANDLERS.freeze
    
    def parse(args = ARGV.dup)
      @config ||= Jiggler.config

      setup_options(args)
      initialize_logger
      validate!
    end

    def start
      Async do
        load_app
        @launcher = Launcher.new(config)
        setup_signal_handlers
        @launcher.start
      end
      @launcher&.cleanup
    end

    def stop
      logger.info('Stopping Jiggler, bye!')
      @launcher.stop
    end

    def quite
      logger.debug('Quietly shutting down Jiggler')
      @launcher.quite
    end

    private

    def setup_signal_handlers
      SIGNAL_HANDLERS.map do |signal, handler|
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
        logger.warn('No require option specified, Jiggler will not init any jobs')
        return
      end
      require config[:require]
    rescue LoadError => e
      logger.fatal("Could not load jobs: #{e.message}")
      exit(1)
    end
  end
end
