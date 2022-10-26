require "singleton"
require "optparse"
require "async/io/trap"
require "erb"

require_relative "../jiggler"
require_relative "./jiggler/config"
require_relative "./jiggler/launcher"

module Jiggler
  class CLI
    include Singleton

    attr_reader :logger, :config
    
    SIGNAL_HANDLERS = {
      # Ctrl-C in terminal
      :INT => ->(cli) { cli.stop },
      # TERM is the signal that Sidekiq must exit.
      # Heroku sends TERM and then waits 30 seconds for process to exit.
      :TERM => ->(cli) { cli.stop },
      :TSTP => ->(cli) {
        cli.logger.info "Received TSTP, no longer accepting new work"
        cli.quiet
      },
      :TTIN => ->(cli) {
        # log running tasks here (+ backtrace)
        # check in sidekiq
      }
    }.freeze
    UNHANDLED_SIGNAL_HANDLER = ->(cli) { cli.logger.info "No signal handler registered, ignoring" }
    SIGNAL_HANDLERS.default = UNHANDLED_SIGNAL_HANDLER
    
    def parse(args = ARGV.dup)
      @config ||= Jiggler.default_config

      setup_options(args)
      initialize_logger
      validate!
    end

    def start(boot_app: true)
      Async do
        load_app if boot_app
        @launcher = Launcher.new(config)
        setup_signal_handlers
        
        @launcher.start
      end
    end

    def stop
      logger.info "Stopping the launcher"
      launcher.stop
    end

    def quite
      logger.info "Quietly shutting down the launcher"
      launcher.quiet
    end

    private

    def setup_signal_handlers
      SIGNAL_HANDLERS.each do |signal, handler|
        trap = Async::IO::Trap.new(signal)
        trap.install!
        Async(transient: true) do
          trap.wait do
            invoked_traps[singal] += 1
            handler.call(self)
          end
        end
      end
    end

    def invoked_traps
      @invoked_traps ||= Hash.new { |h, k| h[k] = 0 }
    end

    def validate!
      if !File.exist?(config[:require])
        logger.info "=================================================================="
        logger.info "  Please point Jiggler to a Ruby file  "
        logger.info "  to load your job classes with -r [FILE]."
        logger.info "=================================================================="
        logger.info @parser
        exit(1)
      end

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
      parser = OptionParser.new { |o|
        o.on "-c", "--concurrency INT", "processor threads to use" do |arg|
          opts[:concurrency] = Integer(arg)
        end

        o.on "-e", "--environment ENV", "Application environment" do |arg|
          opts[:environment] = arg
        end

        o.on "-g", "--tag TAG", "Process tag for procline" do |arg|
          opts[:tag] = arg
        end

        o.on "-q", "--queue QUEUE[,WEIGHT]", "Queues to process with optional weights" do |arg|
          opts[:queues] ||= []
          opts[:queues] << arg
        end

        o.on "-r", "--require [PATH]", "file to require" do |arg|
          opts[:require] = arg
        end

        o.on "-t", "--timeout NUM", "Shutdown timeout" do |arg|
          opts[:timeout] = Integer(arg)
        end

        o.on "-v", "--verbose", "Print more verbose output" do |arg|
          opts[:verbose] = arg
        end

        o.on "-C", "--config PATH", "path to YAML config file" do |arg|
          opts[:config_file] = arg
        end

        o.on "-V", "--version", "Print version and exit" do
          puts "Jiggler #{Jiggler::VERSION}"
          die(0)
        end
      }

      parser.banner = "jiggler [options]"
      parser.on_tail "-h", "--help", "Show help" do
        logger.info parser
        die 1
      end

      parser
    end

    def setup_options(args)
      # parse CLI options
      opts = parse_options(args)

      set_environment opts[:environment]

      # check config file presence
      if opts[:config_file]
        unless File.exist?(opts[:config_file])
          raise ArgumentError, "No such file #{opts[:config_file]}"
        end
      else
        config_dir = File.join(config[:require], "config")

        %w[jiggler.yml jiggler.yml.erb].each do |config_file|
          path = File.join(config_dir, config_file)
          opts[:config_file] ||= path if File.exist?(path)
        end
      end

      # parse config file options
      opts = parse_config(opts[:config_file]).merge(opts) if opts[:config_file]

      # set defaults
      opts[:queues] = [Jiggler::Config::DEFAULT_QUEUE] if opts[:queues].nil?
      opts[:concurrency] = Integer(ENV["JIGGLER_MAX_WORKERS"]) if opts[:concurrency].nil? && ENV["JIGGLER_MAX_WORKERS"]

      # merge with defaults
      config.merge!(opts)
    end

    def set_environment(cli_env)
      # See #984 for discussion.
      # APP_ENV is now the preferred ENV term since it is not tech-specific.
      # Both Sinatra 2.0+ and Sidekiq support this term.
      # RAILS_ENV and RACK_ENV are there for legacy support.
      @environment = cli_env || ENV["APP_ENV"] || ENV["RACK_ENV"] || "development"
    end

    def initialize_logger
      config.logger.level = ::Logger::DEBUG if config[:verbose]
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
      require config[:require]
    end
  end
end