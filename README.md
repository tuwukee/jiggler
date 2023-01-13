# jiggler
Background job processor based on Socketry Async

Jiggler is a [Sidekiq](https://github.com/mperham/sidekiq)-inspired background job processor using [Socketry Async](https://github.com/socketry/async) and [Optimized JSON](https://github.com/ohler55/oj). \
It uses fibers to processes jobs, making context switching lightweight and efficient. Requires Ruby 3+, Redis 6+.

Jiggler is based on Sidekiq implementation, and re-uses some of its concepts and ideas.

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

The tests were run on local (Ubuntu 22.04, Intel(R) Core(TM) i7 6700HQ 2.60GHz). \
On the other configurations depending on internal threads context switching management the results may differ significantly. \
It doesn't really work well on Apple M1 chips. (TODO: WHY? ಠ_ಥ)

Ruby 3.2.0 \
Redis 7.0.7 \
Poller interval 5s \
Monitoring interval 10s \
Logging level `WARN`

#### Noop task measures

```ruby
def perform
  # just an empty job doing nothing
end
```

The parent process enqueues the jobs, starts the monitoring, and then forks the child process, which holds the job processor. Thus, RSS value is affected by the number of jobs uploaded in the parent process. See `bin/jigglerload` to see the load test structure and measuring.

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS    |
|------------------|-------------|----------------|---------------------------|--------------|---------------|
| Sidekiq 7.0.2    | 5           | 100_000        | 24.55 sec                 | 128_524 bytes | 106_428 bytes (GC hit) |
| Jiggler 0.1.0rc1 | 5           | 100_000        | 17.96 sec                 | 92_816 bytes | 94_984 bytes |
| -                |             |                |                           |               |              |
| Sidekiq 7.0.2    | 10          | 100_000        | 20.70 sec                 | 128_440 bytes | 121_176 bytes (GC hit) |
| Jiggler 0.1.0rc1 | 10          | 100_000        | 16.42 sec                 | 92_892 bytes | 95_012 bytes |
| -                |             |                |                           |               |              |
| Sidekiq 7.0.2    | 5           | 1_000_000 (enqueue 100k batches x10) | 193.99 sec | 191_512 bytes | 165_884 bytes (GC hit) |
| Jiggler 0.1.0rc1 | 5           | 1_000_000 (enqueue 100k batches x10) | 155.37 sec | 120_920 bytes | 122_980 bytes |
| -                |             |                |                           |               |              |
| Sidekiq 7.0.2    | 10          | 1_000_000 (enqueue 100k batches x10) | 193.51 sec | 222_212 bytes | 336_560 bytes |
| Jiggler 0.1.0rc1 | 10          | 1_000_000 (enqueue 100k batches x10) | 146.82 sec | 119_008 bytes | 121_784 bytes |


#### IO tests

The idea of the next tests is to simulate jobs with different kinds of IO tasks. \
Ruby 3 has introduced fiber scheduler interface, which allows to implement hooks related to IO/blocking operations.\
The context switching won't work well in case IO is performed by C-extentions which are not aware of Ruby scheduler. 

##### NET/HTTP requests

Spin-up a local sinatra server to exclude network issues while testing HTTP requests.

```ruby
require "sinatra"

class MyApp < Sinatra::Base
  get "/hello" do
    sleep(0.1)
    "Hello World!"
  end
end
```

Then, the code which is going to be performed within the workers should make a `net/http` request to the local endpoint.

```ruby
def perform
  uri = URI("http://127.0.0.1:9292/hello")
  res = Net::HTTP.get_response(uri)
  puts "Request Error!!!" unless res.is_a?(Net::HTTPSuccess)
end
```

It's not recommended to run sidekiq with high concurrency values, setting it for the sake of test. \
Since fibers have relatively small memory foot-print and context switching is also relatively cheap, it's possible to set concurrency to higher values within Jiggler without too much trade-offs.

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   | average %CPU |
|------------------|-------------|----------------|---------------------------|--------------|--------------|--------------|
| Sidekiq 7.0.2    | 5           | 1_000          | 25.14 sec                 | 32_760 bytes | 48_224 bytes | 11.04 |
| Jiggler 0.1.0rc1 | 5           | 1_000          | 24.88 sec                 | 41_376 bytes | 43_584 bytes | 7.27  |
| -                |             |                |                           |              |              |       |
| Sidekiq 7.0.2    | 10          | 1_000          | 13.74 sec                 | 32_716 bytes | 53_360 bytes | 19.01 |
| Jiggler 0.1.0rc1 | 10          | 1_000          | 13.35 sec                 | 41_292 bytes | 44_128 bytes | 12.79 |
| -                |             |                |                           |              |              |       |
| Sidekiq 7.0.2    | 15          | 1_000          | 10.31 sec                 | 31_696 bytes | 58_676 bytes | 25.44 |
| Jiggler 0.1.0rc1 | 15          | 1_000          | 9.6 sec                   | 43_132 bytes | 44_584 bytes | 17.3  |

NOTE: Jiggler has more dependencies, so with small load `start RSS` takes more space.

##### PostgreSQL connection/queries

```ruby
### global namespace
require "pg"

$pg_pool = ConnectionPool.new(size: CONCURRENCY) do
  PG.connect({ dbname: "test", password: "test", user: "test" })
end

### worker context
def perform
  $pg_pool.with do |conn|
    conn.exec("SELECT *, pg_sleep(0.1) FROM pg_stat_activity")
  end
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   | average %CPU |
|------------------|-------------|----------------|---------------------------|--------------|--------------|--------------|
| Sidekiq 7.0.2    | 5           | 100            | 23.54 sec                 | 30_228 bytes | 48_872 bytes | 5.07  |
| Jiggler 0.1.0rc1 | 5           | 100            | 22.27 sec                 | 40_968 bytes | 46_636 bytes | 1.49  |
| -                |             |                |                           |              |              |       |
| Sidekiq 7.0.2    | 10          | 100            | 18.11 sec                 | 30_548 bytes | 53_080 bytes | 10.2 |
| Jiggler 0.1.0rc1 | 10          | 100            | 17.83 sec                 | 41_292 bytes | 47_412 bytes | 3.16 |
| -                |             |                |                           |              |              |       |
| Sidekiq 7.0.2    | 15          | 100            | 16.09 sec                 | 30_496 bytes | 58_444 bytes | 11.58 |
| Jiggler 0.1.0rc1 | 15          | 100            | 14.23 sec                 | 41_720 bytes | 47_668 bytes | 5.31 |

##### File IO

```ruby
def perform(file_name, id)
  File.open(file_name, "a") { |f| f.write("#{id}\n") }
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   | average %CPU |
|------------------|-------------|----------------|---------------------------|--------------|--------------|--------------|
| Sidekiq 7.0.2    | 5           | 10_000         | 6.52 sec                  | 44_452 bytes | 55_004 bytes | 66.06  |
| Jiggler 0.1.0rc1 | 5           | 10_000         | 4.74 sec                  | 48_304 bytes | 47_708 bytes (GC hit) | 39.23  |
| -                |             |                |                           |              |              |       |
| Sidekiq 7.0.2    | 10          | 10_000         | 5.62 sec                  | 44_516 bytes | 60_644 bytes | 87.1 |
| Jiggler 0.1.0rc1 | 10          | 10_000         | 4.06 sec                  | 47_996 bytes | 48_036 bytes | 48.23 |


Jiggler is effective only for tasks with a lot of IO. You must test the concurrency setting with your jobs to find out what configuration works best for your payload.

#### Simulate CPU-only job

With CPU-heavy jobs Jiggler has poor performance. Just to make sure it's generally able to work with CPU-only payloads:

```ruby
def fib(n)
  if n <= 1
    1
  else
    (fib(n-1) + fib(n-2))
  end
end

# a single job takes ~0.024s to perform
def perform(_idx)
  fib(24)
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS   |
|------------------|-------------|----------------|---------------------------|--------------|--------------|
| Sidekiq 7.0.2    | 5           | 200            | 6.68 sec                  | 30_372 bytes | 45_480 bytes |
| Jiggler 0.1.0rc1 | 5           | 200            | 6.41 sec                  | 42_404 bytes | 43_820s bytes |
| -                |             |                |                           |              |              |
| Sidekiq 7.0.2    | 10          | 200            | 6.78 sec                  | 30_940 bytes | 50_312 bytes |
| Jiggler 0.1.0rc1 | 10          | 100            | 6.36 sec                  | 42_212 bytes | 43_740 bytes |


#### IO Event selector

TODO: describe what's it
`IO_EVENT_SELECTOR=EPoll`

### Getting Started

Conceptually Jiggler consists of two parts: the `client` and the `server`. \
The `client` is responsible for pushing jobs to `Redis` and allows to read stats, while the `server` reads jobs from `Redis`, processes them, and writes stats.

The `client` uses `client_concurrency`, `redis_url` (this one is reused by the `server`) and `async_client` settings. The rest of the settings are `server` specific. On default the `client` uses sync `Redis` connections. It's possible to configure it to be async as well via setting `client_async` to `true`. More info below. \
The `server` uses async `Redis` connections. \
The configuration can be skipped if you're using the default values.

```ruby
Jiggler.configure do |config|
  config[:client_concurrency] = 12        # Should equal to the number of threads/fibers in the client app. Defaults to 10
  config[:concurrency] = 12               # The number of running fibers on the server. Defaults to 10
  config[:timeout]     = 12               # Seconds Jiggler wait for jobs to finish before shotdown. Defaults to 25
  config[:environment] = "myenv"          # On default fetches the value ENV["APP_ENV"] and fallbacks to "development"
  config[:require]     = "./jobs.rb"      # Path to file with jobs/app initializer
  config[:redis_url]   = ENV["REDIS_URL"] # On default fetches the value from ENV["REDIS_URL"]
  config[:queues]      = ["shippers"]     # An array of queue names the server is going to listen to. On default uses ["default"]
  config[:config_file] = "./jiggler.yml"  # .yml file with Jiggler settings
end
```

Internally Jiggler server consists of 3 parts: `Manager`, `Poller`, `Monitor`. \
`Manager` is responsible for workers. \
`Poller` fetches data for retries and scheduled jobs. \
`Monitor` periodically loads stats data into redis. \
`Manager` and `Monitor` are mandatory, while `Poller` can be disabled in case there's no need for retries/scheduled jobs.

```ruby
Jiggler.configure do |config|
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
In case the client is being used in async app (f.e. with [Falcon](https://github.com/socketry/falcon) web server, etc.), then it's possible to set a custom redis pool capable of sending async requests into redis. \
The pool should be compatible with `Async::Pool` - support `acquire` method.

```ruby
Jiggler.configure_client do |config|
  config[:client_redis_pool] = my_async_redis_pool
end

# or use build-in async pool with
Jiggler.configure_client do |config|
  config[:client_async] = true
end
```

Then, the client methods could be called with something like:
```ruby
Sync { Jiggler.config.cleaner.prune_all }
Async { MyJob.enqueue }
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
