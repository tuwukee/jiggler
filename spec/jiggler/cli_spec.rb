# frozen_string_literal: true

RSpec.describe Jiggler::CLI do
  let(:cli) { Jiggler::CLI.instance }
  before do
    # reset
    Jiggler.instance_variable_set(:@config, nil) 
    cli.instance_variable_set(:@config, nil)
  end
  after do
    # reset
    Jiggler.instance_variable_set(:@config, nil) 
    cli.instance_variable_set(:@config, nil)
  end

  describe '.parse_and_init' do
    context 'with no args' do
      it 'uses default config' do
        cli.parse_and_init
        expect(cli.config[:concurrency]).to be 10
        expect(cli.config[:queues]).to eq ['default']
        expect(cli.config[:require]).to be nil
        expect(cli.config[:timeout]).to be 25
      end
    end

    context 'with args' do
      before { cli.instance_variable_set(:@config, Jiggler::Config.new(verbose: true)) }
      after { cli.instance_variable_set(:@config, Jiggler::Config.new) }
      let(:path) { './spec/fixtures/config/jiggler.yml' }
      let(:jobs_file) { './spec/fixtures/jobs' }

      it 'fetches config file' do
        cli.parse_and_init(['-C', path])
        expect(cli.config[:config_file]).to eq(path)
        expect(cli.config[:concurrency]).to be 1
        expect(cli.config[:queues]).to eq([['users', 0], ['blep', 3]])
      end

      it 'fetches concurrency' do
        cli.parse_and_init(['-c', '11'])
        expect(cli.config[:concurrency]).to be 11
      end

      it 'fetches queues' do  
        cli.parse_and_init(['-q', 'test,qwerty'])
        expect(cli.config[:queues]).to eq(['test', 'qwerty'])
      end

      it 'fetches require' do
        cli.parse_and_init(['-r', jobs_file])
        expect(cli.config[:require]).to eq(jobs_file)
      end

      it 'fetches timeout' do
        cli.parse_and_init(['-t', '10'])
        expect(cli.config[:timeout]).to be 10
      end

      it 'fetches verbose' do 
        cli.parse_and_init(['-v'])
        expect(cli.config[:verbose]).to be true
      end

      it 'fetches version & exits' do
        expect do
          expect { cli.parse_and_init(['-V']) }.to output('Jiggler #{Jiggler::VERSION}').to_stdout
        end.to raise_error(SystemExit)
      end

      it 'fetches help & exits' do
        expect do
          expect { cli.parse_and_init(['-h']) }.to output.to_stdout
        end.to raise_error(SystemExit)
      end

      it 'fetches environment' do
        cli.parse_and_init(['-e', 'test'])
        expect(cli.config[:environment]).to eq('test')
      end
    end

    context 'with invalid args' do
      after { cli.instance_variable_set(:@config, Jiggler::Config.new) }

      it { expect { cli.parse_and_init(['-c', 'invalid']) }.to raise_error(ArgumentError) }
      it { expect { cli.parse_and_init(['-c', '-1']) }.to raise_error(ArgumentError) }
      it { expect { cli.parse_and_init(['-t', 'yo']) }.to raise_error(ArgumentError) }
      it { expect { cli.parse_and_init(['-r', 'test.rb']) }.to raise_error(SystemExit) }
      it { expect { cli.parse_and_init(['-q', 'in:va:lid']) }.to raise_error(ArgumentError) }
    end

    context 'config validation' do
      context 'with mode' do
        it 'raises an error when invalid mode' do
          Jiggler.configure do |config|
            config[:mode] = :invalid
          end
          expect { cli.parse_and_init }.to raise_error(ArgumentError)
        end

        it 'does not raise an error when valid mode' do
          Jiggler.configure do |config|
            config[:mode] = :at_most_once
          end
          expect { cli.parse_and_init }.not_to raise_error
        end
      end

      context 'with numeric values' do
        it 'raises an error when invalid value' do
          Jiggler::CLI::NUMERIC_OPTIONS.each do |option|
            Jiggler.configure do |config|
              config[option] = [0, -1, 'a'].sample
            end
            expect { cli.parse_and_init }.to raise_error(ArgumentError)
          end
        end
      end
    end
  end
end
