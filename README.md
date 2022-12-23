# jiggler
Background job processor based on Socketry Async

Jiggler is a Sidekiq-inspired background job processor based on Socketry Async.
It uses fibers to processes jobs, making context switching lightweight and more efficient. Requires Ruby 3+.

### Installation

Install the gem:
```
gem install jiggler
```

Start Jiggler server as a separate process with bin command:
```
jiggler -r <FILE_PATH>
```
`-r` specifies a file with loading instructions. \
For Rails apps the command'll be `jiggler -r ./config/environment.rb`

Run `jiggler --help` to see the list of command line arguments.

### Performance

TODO

### Getting Started

Conceptually Jiggler consists of two parts: the client and the server. \
The client is responsible for pushing jobs to Redis and allows to read stats, while the server reads jobs from Redis, processes them, and writes stats.

Both the server and the client can be configured in the same initializer file. \
The server uses async connections. \
The client on default uses synchronous Redis connections. If your app code supports fibers (f.e. you're using Falcon web server), you can configure client to be async as well. \
The configuration can be skipped if you're using the default values.

```ruby
Jiggler.configure_client do |config|
  config[:concurrency] = 10               # Should equal to the number of threads/fibers in the client app. Defaults to 10
  config[:environment] = "myenv"          # On default fetches the value ENV["APP_ENV"] and fallbacks to "development"
  config[:redis_mode]  = :sync            # Can be :sync or :async. Defaults to :sync
  config[:redis_pool]  = nil              # Custom redis connections pool compatible with Async::Pool
  config[:redis_url]   = ENV["REDIS_URL"] # On default fetches the value from ENV["REDIS_URL"]
end

Jiggler.configure_server do |config|
  config[:concurrency] = 12               # Defaults to 10
  config[:timeout]     = 12               # Seconds Jiggler wait for jobs to finish before shotdown. Defaults to 25
  config[:require]     = "./jobs.rb"      # Path to file with jobs/app initializer
  config[:redis_pool]  = nil              # Custom redis connections pool compatible with Async::Pool
  config[:redis_url]   = ENV["REDIS_URL"] # On default fetches the value from ENV["REDIS_URL"]
  config[:queues]      = ["shippers"]     # An array of queue names the server is going to listen to
  config[:config_file] = "./jiggler.yml"  # .yml file with Jiggler settings
end
```

Internally Jiggler server consists of 3 parts: Manager, Poller, Monitor. \
Manager is responsible for workers. \
Poller picks up data for retries and scheduled jobs. \
Monitor periodically loads stats data into redis. \
Manager is mandatory, while Poller and Monitor can be disabled in case there's no need in these services.

```ruby
Jiggler.configure_server do |config|
  config[:stats_enabled]  = true # Defaults to true
  config[:stats_interval] = 15   # Defaults to 10
  config[:poller_enabled] = true # Defaults to true
  config[:poll_interval]  = 10   # Defaults to 5
end
```

`Jiggler::Web.new` is a rack application. It can be run on its own or be mounted in app routes, f.e. with Rails:

```ruby
require "jiggler/web"

Rails.application.routes.draw do
  mount Jiggler::Web.new => "/jiggler"

  # ...
end
```

To get the available stats run:
```ruby
Jiggler.summary
```
Note: Jiggler shows only queues which have enqueued jobs. 

Job classes should include `Jiggler::Job` and implement `perform` method.

```ruby
class MyJob
  include Jiggler::Job

  def perform
    puts "Performing..."
  end
end
```

The job can be enqued with:
```ruby
MyJob.enqueue
```

Specify custom job options:
```ruby
class AnotherJob
  include Jiggler::Job
  job_options queue: "custom", retries: 10

  def perform(num1, num2)
    puts num1 + num2
  end
end
```

To override the options for a specific job:
```ruby
AnotherJob.with_options(queue: "default").enqueue(num1, num2)
```

It's possible to enqueue multiple jobs at once with:
```ruby
arr = [[num1, num2], [num3, num4], [num5, num6]]
AnotherJob.enqueue_bulk(arr)

# if jiggler client supports async redis mode, then you might want to run in async manner
AnotherJob.with_options(async: true).enqueue_bulk(arr)
```

For the cases when you want to enqueue jobs with a delay or at a specific time run:
```ruby
seconds = 100
AnotherJob.enqueue_at(seconds, [num1, num2])
```

To cleanup the data from Redis you can run one of these:
```ruby
# prune data for a specific queue
Jiggler.config.cleaner.prune_queue(queue_name)

# prune all queues data
Jiggler.config.cleaner.prune_all_queues

# prune specific process data from Redis. It's not going to kill to process, only data removal 
Jiggler.config.cleaner.prune_process(process_uuid)

# prune all Jiggler data from Redis including all enqued jobs, stats, etc.
Jiggler.config.cleaner.prune_all
```

### Local development

Docker! You can spin up a local development environment without the need to install dependencies directly on your local machine.

To get started, make sure you have Docker installed on your system. Then, simply run the following command to build the Docker image and start a development server:
```
docker-compose up --build
```

Debug:
```
docker-compose up -d && docker attach jiggler_app
```

Start irb:
```
docker-compose exec app bundle exec irb
```

Run tests: 
```
docker-compose run --rm web -- bundle exec rspec
```

To run the load tests modify the `docker-compose.yml` to point to `bin/jigglerload`
