# jiggler
[![Gem Version](https://badge.fury.io/rb/jiggler.svg)](https://badge.fury.io/rb/jiggler)

Background job processor based on Socketry Async

Jiggler is a [Sidekiq](https://github.com/mperham/sidekiq)-inspired background job processor using [Socketry Async](https://github.com/socketry/async) and [Optimized JSON](https://github.com/ohler55/oj). It uses fibers to processes jobs, making context switching lightweight. Requires Ruby 3+, Redis 6+.

*Jiggler is based on Sidekiq implementation, and re-uses most of its concepts and ideas.*

**NOTE**: Altrough some performance results may look interesting, it's absolutly not recommended to switch to it from well-tested stable solutions. Jiggler has a meager set of features and a very basic monitoring. It's a small indie gem made purely for fun and to gain some hand-on experience with async and fibers. It isn't tested with production projects and might have not-yet-discovered issues. \
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

Ruby `3.2.0` \
Redis `7.0.7` \
Poller interval `5s` \
Monitoring interval `10s` \
Logging level `WARN`

#### Noop task measures

```ruby
def perform
  # just an empty job doing nothing
end
```

The parent process enqueues the jobs, starts the monitoring, and then forks the child job-processor-process. Thus, `RSS` value is affected by the number of jobs uploaded in the parent process. See `bin/jigglerload` to see the load test structure and measuring. \
1_000_000 jobs were enqueued in 100k batches x10.

| Job Processor    | Concurrency | Jobs      | Time      | Start RSS  | Finish RSS    |
|------------------|-------------|-----------|-----------|------------|---------------|
| Sidekiq 7.0.2    | 5           | 100_000   | 20.01 sec | 132_080 kb | 103_168 kb (GC) |
| Jiggler 0.1.0rc1 | 5           | 100_000   | 14.25 sec | 87_532 kb  | 91_464 kb |
| -                |             |           |           |            |           |
| Sidekiq 7.0.2    | 10          | 100_000   | 20.49 sec | 132_164 kb | 125_768 kb (GC) |
| Jiggler 0.1.0rc1 | 10          | 100_000   | 13.25 sec | 87_688 kb  | 91_625 kb |
| -                |             |           |           |            |           |
| Sidekiq 7.0.2    | 5           | 1_000_000 | 186.90 sec | 159_712 kb | 186_224 kb |
| Jiggler 0.1.0rc1 | 5           | 1_000_000 | 123.13 sec | 113_212 kb | 116_336 kb |
| -                |             |           |            |            |            |
| Sidekiq 7.0.2    | 10          | 1_000_000 | 186.94 sec | 159_000 kb | 192_780 kb |
| Jiggler 0.1.0rc1 | 10          | 1_000_000 | 115.56 sec | 113_656 kb | 116_896 kb |


#### IO tests

The idea of the next tests is to simulate jobs with different kinds of IO tasks. \
Ruby 3 has introduced fiber scheduler interface, which allows to implement hooks related to IO/blocking operations.\
The context switching won't work well in case IO is performed by C-extentions which are not aware of Ruby scheduler. 

##### NET/HTTP requests

Spin-up a local sinatra app to exclude network issues while testing HTTP requests (it uses `falcon` web server).

```ruby
require "sinatra"

class MyApp < Sinatra::Base
  get "/hello" do
    sleep(0.2)
    "Hello World!"
  end
end
```

Then, the code which is going to be performed within the workers should make a `net/http` request to the local endpoint.

```ruby
# a single job takes ~0.21s to perform
def perform
  uri = URI("http://127.0.0.1:9292/hello")
  res = Net::HTTP.get_response(uri)
  puts "Request Error!!!" unless res.is_a?(Net::HTTPSuccess)
end
```

It's not recommended to run sidekiq with high concurrency values, setting it for the sake of test. \
The time difference for these samples is small-ish, however the memory consumption is less with the fibers. \
Since fibers have relatively small memory foot-print and context switching is also relatively cheap, it's possible to set concurrency to higher values within Jiggler without too much trade-offs.

| Job Processor    | Concurrency | Jobs  | Time to complete  | Start RSS | Finish RSS | %CPU |
|------------------|-------------|-------|-------------------|-----------|------------|------|
| Sidekiq 7.0.2    | 5           | 1_000 | 43.74 sec         | 30_444 kb | 45_124 kb  | 5.9 |
| Jiggler 0.1.0rc1 | 5           | 1_000 | 43.65 sec         | 33_476 kb | 34_144 kb  | 2.9 |
| -                |             |       |                   |           |            |      |
| Sidekiq 7.0.2    | 10          | 1_000 | 23.05 sec         | 30_604 kb | 50_292 kb  | 10.93 |
| Jiggler 0.1.0rc1 | 10          | 1_000 | 22.86 sec         | 32_416 kb | 34_128 kb  | 5.69 |
| -                |             |       |                   |           |            |      |
| Sidekiq 7.0.2    | 15          | 1_000 | 16.17 sec         | 30_636 kb | 55_144 kb  | 16.47 |
| Jiggler 0.1.0rc1 | 15          | 1_000 | 15.87 sec         | 33_328 kb | 34_548 kb  | 8.25 |

**NOTE**: Jiggler has more dependencies, so with small load `start RSS` takes more space.

##### PostgreSQL connection/queries

`pg` gem supports Ruby's `Fiber.scheduler` starting from 1.3.0 version. Make sure yours DB-adapter supports it.

```ruby
### global namespace
require "pg"

$pg_pool = ConnectionPool.new(size: CONCURRENCY) do
  PG.connect({ dbname: "test", password: "test", user: "test" })
end

### worker context
# a single job takes ~0.102s to perform
def perform
  $pg_pool.with do |conn|
    conn.exec("SELECT pg_sleep(0.1)")
  end
end
```

| Job Processor    | Concurrency | Jobs  | Time      | Start RSS | Finish RSS | %CPU |
|------------------|-------------|-------|-----------|-----------|------------|------|
| Sidekiq 7.0.2    | 5           | 1_000 | 23.44 sec | 31_436 kb | 48_856 kb  | 7.56 |
| Jiggler 0.1.0rc1 | 5           | 1_000 | 23.20 sec | 35_312 kb | 38_592 kb  | 2.91 |
| -                |             |       |           |           |            |      |
| Sidekiq 7.0.2    | 10          | 1_000 | 13.15 sec | 31_272 kb | 52_808 kb  | 13.76 |
| Jiggler 0.1.0rc1 | 10          | 1_000 | 12.65 sec | 35_296 kb | 38_784 kb  | 6.11 |
| -                |             |       |           |           |            |      |
| Sidekiq 7.0.2    | 15          | 1_000 | 9.63 sec  | 31_016 kb | 59_868 kb  | 20.32 |
| Jiggler 0.1.0rc1 | 15          | 1_000 | 9.17 sec  | 35_188 kb | 38_948 kb  | 9.26 |

##### File IO

```ruby
def perform(file_name, id)
  File.open(file_name, "a") { |f| f.write("#{id}\n") }
end
```

| Job Processor    | Concurrency | Jobs   | Time      | Start RSS    | Finish RSS | %CPU  |
|------------------|-------------|--------|-----------|--------------|------------|-------|
| Sidekiq 7.0.2    | 5           | 30_000 | 11.94 sec | 61_944 kb    | 71_948 kb  | 94.34 |
| Jiggler 0.1.0rc1 | 5           | 30_000 | 7.87 sec  | 50_140 kb    | 51_272 kb  | 61.7  |
| -                |             |        |           |              |            |       |
| Sidekiq 7.0.2    | 10          | 30_000 | 11.6 sec  | 62_020 kb    | 78_952 kb  | 94.44 |
| Jiggler 0.1.0rc1 | 10          | 30_000 | 7.17 sec  | 50_060 kb    | 51_464 kb  | 69.25 |
| -                |             |        |           |              |            |       |
| Sidekiq 7.0.2    | 15          | 30_000 | 11.24 sec | 62_016 kb    | 83_808 kb  | 94.16 |
| Jiggler 0.1.0rc1 | 15          | 30_000 | 7.02 sec  | 49_988 kb    | 51_428 kb  | 70.3  |


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

| Job Processor    | Concurrency | Jobs | Time     | Start RSS  | Finish RSS |
|------------------|-------------|------|----------|------------|------------|
| Sidekiq 7.0.2    | 5           | 100  | 5.81 sec | 27_792 kb  | 42_464 kb |
| Jiggler 0.1.0rc1 | 5           | 100  | 5.29 sec | 31_304 kb  | 32_320 kb |
| -                |             |      |          |            |           |
| Sidekiq 7.0.2    | 10          | 100  | 5.63 sec | 28_044 kb  | 47_640 kb |
| Jiggler 0.1.0rc1 | 10          | 100  | 5.43 sec | 32_316 kb  | 32_548 kb |

#### IO Event selector

`IO_EVENT_SELECTOR` is an env variable which allows to specify the event selector used by the Ruby scheduler. \
On default it uses `Epoll` (`IO_EVENT_SELECTOR=EPoll`). \
Another available option is `URing` (`IO_EVENT_SELECTOR=URing`). Underneath it uses `io_uring` library. It is a Linux kernel library that provides a high-performance interface for asynchronous I/O operations. It was introduced in Linux kernel version 5.1 and aims to address some of the limitations and scalability issues of the existing AIO (Asynchronous I/O) interface.
In the future it might bring a lot of performance boost into Ruby fibers world (once `async` project fully adopts it), but at the moment in the most cases its performance is similar to `EPoll`, yet it could give some boost with File IO.

#### Socketry stack

The gem allows to use libs from `socketry` stack (https://github.com/socketry) within workers. \
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

| Job Processor    | Concurrency | Jobs  | Time      | Start RSS | Finish RSS | %CPU |
|------------------|-------------|-------|-----------|-----------|------------|------|
| Jiggler 0.1.0rc1 | 5           | 1_000 | 43.23 sec | 34_340 kb | 38_488 kb  | 1.51 |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0rc1 | 10          | 1_000 | 22.67 sec | 34_552 kb | 38_600 kb  | 2.75 |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0rc1 | 15          | 1_000 | 15.88 sec | 34_332 kb | 38_544 kb  | 4.06 |

### Getting Started

Conceptually Jiggler consists of two parts: the `client` and the `server`. \
The `client` is responsible for pushing jobs to `Redis` and allows to read stats, while the `server` reads jobs from `Redis`, processes them, and writes stats.

The `server` uses async `Redis` connections. \
The `client` on default is `sync`. It's possible to configure the client to be async as well via setting `client_async` to `true`. More info below. \
Client settings are:
- `client_concurrency`
- `async_client`
- `redis_url` (this one is shared with the `server`)

The rest of the settings are `server` specific. 

**NOTE**: `require "jiggler"` loads only client classes. It doesn't include `async` lib, this dependency is being required only within the `server` part.

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
 "dead_jobs_count"=>0,
 "scheduled_jobs_count"=>0,
 "failures_count"=>6,
 "processed_count"=>0,
 "processes"=>
  {"jiggler:svr:3513d56f7ed2:10:25:default:1:1673875240:83568:JulijaA-MBP.local"=>
    {"heartbeat"=>1673875270.551845,
     "rss"=>32928,
     "current_jobs"=>{},
     "name"=>"jiggler:svr:3513d56f7ed2",
     "concurrency"=>"10",
     "timeout"=>"25",
     "queues"=>"default",
     "poller_enabled"=>true,
     "started_at"=>"1673875240",
     "pid"=>"83568",
     "hostname"=>"JulijaA-MBP.local"}},
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
