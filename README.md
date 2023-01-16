# jiggler
Background job processor based on Socketry Async

Jiggler is a [Sidekiq](https://github.com/mperham/sidekiq)-inspired background job processor using [Socketry Async](https://github.com/socketry/async) and [Optimized JSON](https://github.com/ohler55/oj). \
It uses fibers to processes jobs, making context switching lightweight. Requires Ruby 3+, Redis 6+.

Jiggler is based on Sidekiq implementation, and re-uses most of its concepts and ideas.

NOTE: Altrough some performance results may look interesting, it's absolutly not recommended to switch to it from well-tested stable solutions. \
Jiggler has a meager set of features and a very basic monitoring. It's a small indie gem made purely for fun and to gain some hand-on experience with async and fibers. It isn't tested with production projects and might have not-yet-discovered issues. \
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
On the other configurations the results may differ significantly, f.e. with Apple M1 Max chip it treats some IO operations as blocking and shows a poor performance ಠ_ಥ.

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

The parent process enqueues the jobs, starts the monitoring, and then forks the child job-processor-process. Thus, `RSS` value is affected by the number of jobs uploaded in the parent process. See `bin/jigglerload` to see the load test structure and measuring.

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS  | Finish RSS    |
|------------------|-------------|----------------|---------------------------|------------|---------------|
| Sidekiq 7.0.2    | 5           | 100_000        | 24.55 sec                 | 128_524 kb | 106_428 kb (GC hit) |
| Jiggler 0.1.0rc1 | 5           | 100_000        | 14.91 sec                 | 93_164 kb  | 95_324 kb |
| -                |             |                |                           |            |           |
| Sidekiq 7.0.2    | 10          | 100_000        | 20.70 sec                 | 128_440 kb | 121_176 kb (GC hit) |
| Jiggler 0.1.0rc1 | 10          | 100_000        | 13.98 sec                 | 93_060 kb  | 95_384 kb |
| -                |             |                |                           |            |           |
| Sidekiq 7.0.2    | 5           | 1_000_000 (enqueue 100k batches x10) | 193.99 sec | 191_512 kb | 165_884 kb (GC hit) |
| Jiggler 0.1.0rc1 | 5           | 1_000_000 (enqueue 100k batches x10) | 155.69 sec | 105_256 kb | 75_108 kb (GC hit) |
| -                |             |                |                           |               |              |
| Sidekiq 7.0.2    | 10          | 1_000_000 (enqueue 100k batches x10) | 193.51 sec | 222_212 kb | 336_560 kb |
| Jiggler 0.1.0rc1 | 10          | 1_000_000 (enqueue 100k batches x10) | 140.25 sec | 107_680 kb | 112_168 kb |


#### IO tests

The idea of the next tests is to simulate jobs with different kinds of IO tasks. \
Ruby 3 has introduced fiber scheduler interface, which allows to implement hooks related to IO/blocking operations.\
The context switching won't work well in case IO is performed by C-extentions which are not aware of Ruby scheduler. 

##### NET/HTTP requests

Spin-up a local sinatra server to exclude network issues while testing HTTP requests (it uses `puma` for multi-threading).

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
# a single job takes ~0.1s to perform
def perform
  uri = URI("http://127.0.0.1:9292/hello")
  res = Net::HTTP.get_response(uri)
  puts "Request Error!!!" unless res.is_a?(Net::HTTPSuccess)
end
```

It's not recommended to run sidekiq with high concurrency values, setting it for the sake of test. \
The time difference for these samples is within the statistical error, however the memory consumption is less with the fibers. \
Since fibers have relatively small memory foot-print and context switching is also relatively cheap, it's possible to set concurrency to higher values within Jiggler without too much trade-offs.

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS | Finish RSS | average %CPU |
|------------------|-------------|----------------|---------------------------|-----------|------------|--------------|
| Sidekiq 7.0.2    | 5           | 1_000          | 25.14 sec                 | 32_760 kb | 48_224 kb | 11.04 |
| Jiggler 0.1.0rc1 | 5           | 1_000          | 24.48 sec                 | 41_296 kb | 42_232 kb | 6.49  |
| -                |             |                |                           |           |           |       |
| Sidekiq 7.0.2    | 10          | 1_000          | 13.74 sec                 | 32_716 kb | 53_360 kb | 19.01 |
| Jiggler 0.1.0rc1 | 10          | 1_000          | 13.85 sec                 | 40_760 kb | 42_412 kb | 11.79 |
| -                |             |                |                           |           |           |       |
| Sidekiq 7.0.2    | 15          | 1_000          | 10.31 sec                 | 31_696 kb | 58_676 kb | 25.44 |
| Jiggler 0.1.0rc1 | 15          | 1_000          | 9.65 sec                  | 40_764 kb | 42_400 kb | 16.88 |

NOTE: Jiggler has more dependencies, so with small load `start RSS` takes more space.

##### PostgreSQL connection/queries

`pg` gem supports Ruby's `Fiber.scheduler` starting from 1.3.0 version. Make sure yours DB-adapter supports it.

```ruby
### global namespace
require "pg"

$pg_pool = ConnectionPool.new(size: CONCURRENCY) do
  PG.connect({ dbname: "test", password: "test", user: "test" })
end

### worker context
# a single job takes ~0.63s to perform
def perform
  $pg_pool.with do |conn|
    conn.exec("SELECT *, pg_sleep(0.1) FROM pg_stat_activity")
  end
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS | Finish RSS | average %CPU |
|------------------|-------------|----------------|---------------------------|-----------|------------|--------------|
| Sidekiq 7.0.2    | 5           | 100            | 23.54 sec                 | 30_228 kb | 48_872 kb  | 5.07 |
| Jiggler 0.1.0rc1 | 5           | 100            | 21.02 sec                 | 41_268 kb | 46_252 kb  | 1.49 |
| -                |             |                |                           |           |            |      |
| Sidekiq 7.0.2    | 10          | 100            | 18.11 sec                 | 30_548 kb | 53_080 kb  | 10.2 |
| Jiggler 0.1.0rc1 | 10          | 100            | 17.85 sec                 | 41_708 kb | 46_828 kb  | 2.82 |
| -                |             |                |                           |           |            |      |
| Sidekiq 7.0.2    | 15          | 100            | 16.09 sec                 | 30_496 kb | 58_444 kb  | 11.58 |
| Jiggler 0.1.0rc1 | 15          | 100            | 14.23 sec                 | 42_004 kb | 46_968 kb  | 4.62 |

##### File IO

```ruby
def perform(file_name, id)
  File.open(file_name, "a") { |f| f.write("#{id}\n") }
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS    | Finish RSS | average %CPU |
|------------------|-------------|----------------|---------------------------|--------------|------------|--------------|
| Sidekiq 7.0.2    | 5           | 20_000         | 10.16 sec                 | 51_340 kb    | 64_456 kb  | 76.37 |
| Jiggler 0.1.0rc1 | 5           | 20_000         | 6.01 sec                  | 50_512 kb    | 53_568 kb  | 52.23 |
| -                |             |                |                           |              |            |       |
| Sidekiq 7.0.2    | 10          | 20_000         | 9.11 sec                  | 52_336 kb    | 72_232 kb  | 80.3  |
| Jiggler 0.1.0rc1 | 10          | 20_000         | 5.57 sec                  | 50_316 kb    | 53_768 kb  | 58.56 |


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

# a single job takes ~0.035s to perform
def perform(_idx)
  fib(25)
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS  | Finish RSS |
|------------------|-------------|----------------|---------------------------|------------|------------|
| Sidekiq 7.0.2    | 5           | 100            | 5.61 sec                  | 29_164 kb  | 48_188 kb |
| Jiggler 0.1.0rc1 | 5           | 100            | 5.67 sec                  | 38_896 kb  | 39_620 kb |
| -                |             |                |                           |            |           |
| Sidekiq 7.0.2    | 10          | 100            | 5.71 sec                  | 28_148 kb  | 48_112 kb |
| Jiggler 0.1.0rc1 | 10          | 100            | 5.36 sec                  | 39_144 kb  | 39_800 kb |


#### IO Event selector

`IO_EVENT_SELECTOR` is an env variable which allows to specify the event selector used by the Ruby scheduler. \
On default it uses `Epoll` (`IO_EVENT_SELECTOR=EPoll`). \
Another available option is `URing` (`IO_EVENT_SELECTOR=URing`). Underneath it uses `io_uring` library. It is a Linux kernel library that provides a high-performance interface for asynchronous I/O operations. It was introduced in Linux kernel version 5.1 and aims to address some of the limitations and scalability issues of the existing AIO (Asynchronous I/O) interface.
In the future it might bring a lot of performance boost into Ruby fibers world (once `async` project fully adopts it), but at the moment in the most cases its performance is similar to `EPoll`, yet it could give some boost with File IO.

#### Socketry stack

The gem allows to use libs from `socketry` stack (https://github.com/socketry) within workers, potentially they could provide a better performance boost compared to Ruby native calls.
F.e. when making HTTP requests using `async/http/internet` to the Sinatra app described above:

```ruby
### global namespace
require "async/http/internet"
$internet = Async::HTTP::Internet.new

### worker context
def perform
  uri = "https://127.0.0.1/hello"
  res = $internet.get(uri)
  res.finish
  puts "Request Error!!!" unless res.status == 200
end
```

| Job Processor    | Concurrency | Number of Jobs | Time to complete all jobs | Start RSS | Finish RSS | average %CPU |
|------------------|-------------|----------------|---------------------------|-----------|------------|--------------|
| Jiggler 0.1.0rc1 | 5           | 1_000          | 23.07 sec                 | 41_528 kb | 44_372 kb  | 3.01 |
| -                |             |                |                           |           |            |      |
| Jiggler 0.1.0rc1 | 10          | 1_000          | 12.7 sec                  | 40_480 kb | 44_404 kb  | 6.08 |

### Getting Started

Conceptually Jiggler consists of two parts: the `client` and the `server`. \
The `client` is responsible for pushing jobs to `Redis` and allows to read stats, while the `server` reads jobs from `Redis`, processes them, and writes stats.

The `client` uses `client_concurrency`, `redis_url` (this one is reused by the `server`) and `async_client` settings. The rest of the settings are `server` specific. On default the `client` uses sync `Redis` connections. It's possible to configure it to be async as well via setting `client_async` to `true`. More info below. \
The `server` uses async `Redis` connections. \
The configuration can be skipped if you're using the default values.

```ruby
require "jiggler"

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
irb(main)> Jiggler.summary
=> 
{"retry_jobs_count"=>0,
 "dead_jobs_count"=>3,
 "scheduled_jobs_count"=>0,
 "failures_count"=>4,
 "processed_count"=>0,
 "processes"=>
  {"jiggler:svr:d5bb7021a927:JulijaA-MBP.local:10:25:default:1:1673628278:83647"=>
    {"heartbeat"=>1673628288.142401,
     "rss"=>44992,
     "current_jobs"=>{},
     "name"=>"jiggler:d5bb7021a927",
     "hostname"=>"JulijaA-MBP.local",
     "concurrency"=>"10",
     "timeout"=>"25",
     "queues"=>"default",
     "poller_enabled"=>true,
     "started_at"=>"1673628278",
     "pid"=>"83647"}},
 "queues"=>{"mine"=>1, "unknown"=>1, "test"=>1}}
```
Note: Jiggler summary shows only queues which have enqueued jobs. 

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
require "async/pool"

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
