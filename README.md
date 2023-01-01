# jiggler
Background job processor based on Socketry Async

Jiggler is a [Sidekiq](https://github.com/mperham/sidekiq)-inspired background job processor using [Socketry Async](https://github.com/socketry/async).
It uses fibers to processes jobs, making context switching lightweight and efficient. Requires Ruby 3+, Redis 6+.

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

The tests were run on local (OSX 12.3, Chip M1 Pro 2021) within a (Docker Desktop 4.6.1) container (`ruby:latest` 5.10.104-linuxkit) with `redis:6.2.6-alpine`. \
On the other configurations depending on internal threads context switching management the results may differ significantly.

Ruby 3.2.0 \
Concurrency 10 \
Poller interval 5s \
Monitoring interval 10s \
Logging level `WARN`

```ruby
def perform(_idx)
  # just an empty job doing nothing
end
```

| Job Processor    | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS    |
|------------------|----------------|---------------------------|--------------|---------------|
| Sidekiq 7.0.2    | 100_000        | 48.70 sec                 | 160_296 bytes| 124_516 bytes (GC hit) |
| Jiggler 0.1.0rc1 | 100_000        | 32.17 sec                 | 133_784 bytes| 94_080 bytes (GC hit) |
| -                |                |                           |              |              |
| Sidekiq 7.0.2    | 1_000_000 (enqueue 100k batches x10) | 496.55 sec                | 227_548 bytes| 232_680 bytes |
| Jiggler 0.1.0rc1 | 1_000_000 (enqueue 100k batches x10) | 303.27 sec                | 152_412 bytes| 125_896 bytes (GC hit) |

```ruby
def fib(n)
  if n <= 1
    1
  else
    (fib(n-1) + fib(n-2))
  end
end

# the idea is to simulate a somehow real job
# most of the time it's doing I/O operations (puts/sleep)
# and a bit of time - CPU-tasks (fib)
# a single job takes 0.62s to perform
def perform(idx)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  sleep 0.1
  fib(10)
  sleep 0.5
  fib(25)
  puts "#{idx} ended #{Process.clock_gettime(Process::CLOCK_MONOTONIC) - start}\n"
end
```

| Job Processor    | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   |
|------------------|----------------|---------------------------|--------------|--------------|
| Sidekiq 7.0.2    | 100            | 20.29 sec                 | 57_056 bytes | 75_028 bytes |
| Jiggler 0.1.0rc1 | 100            | 14.61 sec                 | 71_044 bytes | 71_904 bytes |
| -                |                |                           |              |              |
| Sidekiq 7.0.2    | 1000           | 175.42 sec                | 58_300 bytes | 76_656 bytes |
| Jiggler 0.1.0rc1 | 1000           | 122.24 sec                | 71_848 bytes | 75_872 bytes |


Jiggler is effective for tasks with a lot of IO. \
With CPU-heavy jobs it has poor performance.

```ruby
def fib(n)
  if n <= 1
    1
  else
    (fib(n-1) + fib(n-2))
  end
end

# a single job takes 0.35s to perform
def perform(_idx)
  fib(33)
end
```

| Job Processor    | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   |
|------------------|----------------|---------------------------|--------------|--------------|
| Sidekiq 7.0.2    | 100            | 268.12 sec                | 56_956 bytes | 75_456 bytes |
| Jiggler 0.1.0rc1 | 100            | 269.57 sec                | 70_624 bytes | 72_664 bytes |

### Getting Started

Conceptually Jiggler consists of two parts: the `client` and the `server`. \
The `client` is responsible for pushing jobs to `Redis` and allows to read stats, while the `server` reads jobs from `Redis`, processes them, and writes stats.

Both the `server` and the `client` can be configured in the same initializer file. \
The `server` uses async `Redis` connections. \
The `client` uses sync `Redis` connections. It's possible to configure it to be async as well. More info below. \
The configuration can be skipped if you're using the default values.

```ruby
Jiggler.configure_client do |config|
  config[:concurrency] = 12               # Should equal to the number of threads/fibers in the client app. Defaults to 10
  config[:redis_url]   = ENV["REDIS_URL"] # On default fetches the value from ENV["REDIS_URL"]
end

Jiggler.configure_server do |config|
  config[:concurrency] = 12               # The number of running fibers. Defaults to 10
  config[:timeout]     = 12               # Seconds Jiggler wait for jobs to finish before shotdown. Defaults to 25
  config[:environment] = "myenv"          # On default fetches the value ENV["APP_ENV"] and fallbacks to "development"
  config[:require]     = "./jobs.rb"      # Path to file with jobs/app initializer
  config[:redis_url]   = ENV["REDIS_URL"] # On default fetches the value from ENV["REDIS_URL"]
  config[:queues]      = ["shippers"]     # An array of queue names the server is going to listen to
  config[:config_file] = "./jiggler.yml"  # .yml file with Jiggler settings
end

# this call applies the settings
Jiggler.run_configuration
```

Internally Jiggler server consists of 3 parts: `Manager`, `Poller`, `Monitor`. \
`Manager` is responsible for workers. \
`Poller` fetches data for retries and scheduled jobs. \
`Monitor` periodically loads stats data into redis. \
`Manager` and `Monitor` are mandatory, while `Poller` can be disabled in case there's no need for retries/scheduled jobs.

```ruby
Jiggler.configure_server do |config|
  config[:stats_interval] = 12   # Defaults to 10
  config[:poller_enabled] = true # Defaults to true
  config[:poll_interval]  = 12   # Defaults to 5
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
  job_options queue: "custom", retries: 10, retry_queue: "custom_retries"

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
```

For the cases when you want to enqueue jobs with a delay or at a specific time run:
```ruby
seconds = 100
AnotherJob.enqueue_in(seconds, [num1, num2])
```

To cleanup the data from Redis you can run one of these:
```ruby
# prune data for a specific queue
Jiggler.config.cleaner.prune_queue(queue_name)

# prune all queues data
Jiggler.config.cleaner.prune_all_queues

# prune all Jiggler data from Redis including all enqued jobs, stats, etc.
Jiggler.config.cleaner.prune_all
```

On default `client` uses synchronous `Redis` connections.  \
In case the client is being used in async app (f.e. with [Falcon](https://github.com/socketry/falcon) web server, or in Polyphony, etc.), then it's possible to set a custom redis pool capable of sending async requests into redis. \
The pool should be compatible with `Async::Pool` - support `acquire` method.

```ruby
Jiggler.configure_client do |config|
  config[:redis_pool] = my_async_redis_pool
end

# or use build-in async pool with
Jiggler.configure_client do |config|
  config[:async] = true
end
```

Then, the client methods could be called with:
```ruby
Async do
  Jiggler.config.cleaner.prune_all
  MyJob.enqueue
end
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
