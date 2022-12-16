# frozen_string_literal: true

RSpec.describe Jiggler::CLI do
  let(:cli) { Jiggler::CLI.instance }

  describe ".parse" do
    context "with no args" do
      it "uses default config" do
        cli.parse
        expect(cli.config[:concurrency]).to be 10
        expect(cli.config[:queues]).to eq ["default"]
        expect(cli.config[:require]).to eq "."
        expect(cli.config[:timeout]).to be 25
      end
    end

    context "with args" do
      before { cli.instance_variable_set(:@config, Jiggler::Config.new(verbose: true)) }
      after { cli.instance_variable_set(:@config, Jiggler::Config.new) }
      let(:path) { File.join("/jiggler/spec/fixtures/config/jiggler.yml") }

      it "fetches config file" do
        cli.parse(["-C", path])
        expect(cli.config[:config_file]).to eq(path)
        expect(cli.config[:concurrency]).to be 1
        expect(cli.config[:queues]).to eq(["users", "blep"])
      end

      it "fetches concurrency" do
        cli.parse(["-c", "11"])
        expect(cli.config[:concurrency]).to be 11
      end

      it "fetches queues" do  
        cli.parse(["-q", "test,qwerty"])
        expect(cli.config[:queues]).to eq(["test", "qwerty"])
      end

      it "fetches require" do
        cli.parse(["-r", path])
        expect(cli.config[:require]).to eq(path)
      end

      it "fetches timeout" do
        cli.parse(["-t", "10"])
        expect(cli.config[:timeout]).to be 10
      end

      it "fetches verbose" do 
        cli.parse(["-v"])
        expect(cli.config[:verbose]).to be true
      end

      it "fetches version & exits" do
        expect do
          expect { cli.parse(["-V"]) }.to output("Jiggler #{Jiggler::VERSION}").to_stdout
        end.to raise_error(SystemExit)
      end

      it "fetches help & exits" do
        expect do
          expect { cli.parse(["-h"]) }.to output.to_stdout
        end.to raise_error(SystemExit)
      end

      it "fetches environment" do
        cli.parse(["-e", "test"])
        expect(cli.config[:environment]).to eq("test")
      end
    end

    context "with invalid args" do
      after { cli.instance_variable_set(:@config, Jiggler::Config.new) }

      it { expect { cli.parse(["-c", "invalid"]) }.to raise_error(ArgumentError) }
      it { expect { cli.parse(["-c", "-1"]) }.to raise_error(ArgumentError) }
      it { expect { cli.parse(["-t", "yo"]) }.to raise_error(ArgumentError) }
      it do 
        cli.parse(["-r", "test.rb"])
        expect { cli.send(:load_app) }.to raise_error(SystemExit) 
      end
    end
  end
end
