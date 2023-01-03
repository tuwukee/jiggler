# jiggler
Background job processor based on Socketry Async

Jiggler is a [Sidekiq](https://github.com/mperham/sidekiq)-inspired background job processor using [Socketry Async](https://github.com/socketry/async) and [Optimized JSON](https://github.com/ohler55/oj).
It uses fibers to processes jobs, making context switching lightweight and efficient. Requires Ruby 3+, Redis 6+.

NOTE: Altrough some performance results may look interesting, it's absolutly not recommended to switch to it from well-tested stable solutions. \
Jiggler has a meager set of features and a very basic monitoring. It's a small indie gem made purely for fun and to gain some hand-on experience with async and fibers. It isn't tested with production projects and is likely to explode as soon as it runs into real tasks. \
However, it's good to play around and/or to try it in the name of science.

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

The tests were run on local (OSX 12.3, Chip M1 Pro 2021) within a (Docker Desktop 4.6.1) container (`ruby:latest` Debian 5.10.104-linuxkit) with `redis:6.2.6-alpine`. \
On the other configurations depending on internal threads context switching management the results may differ significantly.

Ruby 3.2.0 \
Poller interval 5s \
Monitoring interval 10s \
Logging level `WARN`

```ruby
def perform(_idx)
  # just an empty job doing nothing
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS    |
|------------------|-------------|----------------|---------------------------|--------------|---------------|
| Sidekiq 7.0.2    | 5-           | 100_000        | 47.98 sec                 | 160_116 bytes | 125_076 bytes (GC hit) |
| Jiggler 0.1.0rc1 | 5           | 100_000        | 32.02 sec                 | 127_876 bytes | 129_792 bytes |
| -                |             |                |                           |               |              |
| Sidekiq 7.0.2    | 10-          | 100_000        | 46.99 sec                 | 162_848 bytes | 131_824 bytes (GC hit) |
| Jiggler 0.1.0rc1 | 10          | 100_000        | 31.92 sec                 | 127_728 bytes | 129_628 bytes |
| -                |             |                |                           |               |              |
| Sidekiq 7.0.2    | 5-           | 1_000_000 (enqueue 100k batches x10) | 496.55 sec | 227_548 bytes | 232_680 bytes |
| Jiggler 0.1.0rc1 | 5           | 1_000_000 (enqueue 100k batches x10) | 299.15 sec | 158_564 bytes | 161_368 bytes |
| -                |             |                |                           |               |              |
| Sidekiq 7.0.2    | 10-          | 1_000_000 (enqueue 100k batches x10) | 450.51 sec | 196_980 bytes | 223_760 bytes |
| Jiggler 0.1.0rc1 | 10          | 1_000_000 (enqueue 100k batches x10) | 310.10 sec | 158_732 bytes | 126_148 bytes (GC hit) |


The idea of the next test is to simulate jobs with a realistic IO/CPU bound ratio. \
IO: `sample_get_request` sends a GET request to `https://httpbin.org` using `net/http`, also there's `puts`. \ 
CPU: recursive `fib` method.

```ruby
require 'uri'
require 'net/http'

def fib(n)
  if n <= 1
    1
  else
    (fib(n-1) + fib(n-2))
  end
end

def sample_get_request
  uri = URI("https://httpbin.org/ip")
  res = Net::HTTP.get_response(uri)
  puts "Request Error!!!" unless res.is_a?(Net::HTTPSuccess)
end
```

#### Simulate a high I/O bound job

```ruby
# IO ~71%
# CPU-tasks ~29%
# a single job takes ~1.28s to perform
def perform(idx)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  sample_get_request # 0.91
  fib(33) # 0.36 
  puts "#{idx} ended #{Process.clock_gettime(Process::CLOCK_MONOTONIC) - start}\n"
end
```

It's not recommended to run sidekiq with high concurrency values, setting it for the sake of test. \

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   | average %CPU |
|------------------|-------------|----------------|---------------------------|--------------|--------------|--------------|
| Sidekiq 7.0.2    | 5           | 10             | 29.2 sec                  | 58_348 bytes | 87_544 bytes | 85.01 |
| Jiggler 0.1.0rc1 | 5           | 10             | 27.46 sec                 | 75_896 bytes | 84_484 bytes | 99.5 |
| -                |             |                |                           |              |              |       |
| Sidekiq 7.0.2    | 10          | 10             | 27.85 sec                 | 58_260 bytes | 91_380 bytes | 88.75 |
| Jiggler 0.1.0rc1 | 10          | 10             | 26.94 sec                 | 75_788 bytes | 84_504 bytes | 48.19 |
| -                |             |                |                           |              |              |       |
| Sidekiq 7.0.2    | 5           | 100            | 276.47 sec                | 57_564 bytes | 90_508 bytes | 98.14 |
| Jiggler 0.1.0rc1 | 5           | 100            | 278.39 sec                | 73_068 bytes | 92_064 bytes | 95.08 |
| -                |             |                |                           |              |              |      |
| Sidekiq 7.0.2    | 10          | 100            | 271.32 sec                | 57_628 bytes | 95_904 bytes | 97.9 |
| Jiggler 0.1.0rc1 | 10          | 100            | 270.49 sec                | 72_876 bytes | 91_768 bytes | 97.7 |
| -                |             |                |                           |              |              |      |
| Sidekiq 7.0.2    | 15          | 100            | 269.34 sec                | 57_572 bytes | 100_972 bytes | 99.19 |
| Jiggler 0.1.0rc1 | 15          | 100            | 271.39 sec                | 72_696 bytes | 92_272 bytes | 97.95 |
| -                |             |                |                           |              |              |      |
| Sidekiq 7.0.2    | 20          | 100            | 267.86 sec                | 57_580 bytes | 105_372 bytes | 99.37 |
| Jiggler 0.1.0rc1 | 20          | 100            | 270.52 sec                | 72_816 bytes | 92_420 bytes | 99.27 |

NOTE: Jiggler has more dependencies, so with small load `start RSS` takes more space. \
Jiggler is effective only for tasks with a lot of IO. For IO bound tasks increasing concurrency may gain effectiveness. \
You must test the concurrency setting with your jobs to find out what configuration works best for your payload. \
With CPU-heavy jobs Jiggler has poor performance.

#### Simulate CPU-only job

It's unlikely that someone ever uses such setup, as it doesn't make much sense, but just to make sure it's generally able to work:

```ruby
# a single job takes 0.35s to perform
def perform(_idx)
  fib(33)
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   |
|------------------|-------------|----------------|---------------------------|--------------|--------------|
| Sidekiq 7.0.2    | 5           | 100            | 268.12 sec                | 56_956 bytes | 75_456 bytes |
| Jiggler 0.1.0rc1 | 5           | 100            | 256.21 sec                | 70_716 bytes | 72_344 bytes |
| -                |             |                |                           |              |              |
| Sidekiq 7.0.2    | 10          | 100            | 265.92 sec                | 56_900 bytes | 79_572 bytes |
| Jiggler 0.1.0rc1 | 10          | 100            | 269.57 sec                | 70_624 bytes | 72_664 bytes |


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
  config[:queues]      = ["shippers"]     # An array of queue names the server is going to listen to. On default uses ["default"]
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
AnotherJob.enqueue_in(seconds, num1, num2)
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

Then, the client methods could be called with something like:
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
