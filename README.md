# jiggler
[![Gem Version](https://badge.fury.io/rb/jiggler.svg)](https://badge.fury.io/rb/jiggler)

Background job processor based on Socketry Async

Jiggler is a [Sidekiq](https://github.com/mperham/sidekiq)-inspired background job processor using [Socketry Async](https://github.com/socketry/async) and [Optimized JSON](https://github.com/ohler55/oj). It uses fibers to processes jobs, making context switching lightweight. Requires Ruby 3+, Redis 6+.

*Jiggler is based on Sidekiq implementation, and re-uses most of its concepts and ideas.*

**NOTE**: Jiggler is a small gem made purely for fun and to gain some hand-on experience with async and fibers. It isn't tested with production projects and might have not-yet-discovered issues. Use at your own risk. \
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

[Jiggler 0.1.0rc4 performance results (at most once delivery) against sidekiq 7.0.3](/docs/perf_results_0.1.0rc4.md) \
[Jiggler 0.1.0 performance results (at least once delivery) against (at most once delivery)](/docs/perf_results_0.1.0.md)

### Getting Started

Conceptually Jiggler consists of two parts: the `client` and the `server`. \
The `client` is responsible for pushing jobs to `Redis` and allows to read stats, while the `server` reads jobs from `Redis`, processes them, and writes stats.

The `server` uses async `Redis` connections. \
The `client` on default is `sync`. It's possible to configure the client to be async as well via setting `client_async` to `true`. \
Client settings are:
- `client_concurrency`
- `client_async`
- `redis_url` (this one is shared with the `server`)

The rest of the settings are `server` specific. 

**NOTE**: `require "jiggler"` loads only client classes. It doesn't include `async` lib, this dependency is being required only within the `server` part.

```ruby
require "jiggler"

Jiggler.configure do |config|
  config[:client_concurrency] = 12        # Should equal to the number of threads/fibers in the client app. Defaults to 10
  config[:concurrency] = 12               # The number of running workers on the server. Defaults to 10
  config[:timeout]     = 12               # Seconds Jiggler wait for jobs to finish before shutdown. Defaults to 25
  config[:environment] = "myenv"          # On default fetches the value ENV["APP_ENV"] and fallbacks to "development"
  config[:require]     = "./jobs.rb"      # Path to file with jobs/app initializer
  config[:redis_url]   = ENV["REDIS_URL"] # On default fetches the value from ENV["REDIS_URL"]
  config[:queues]      = ["shippers"]     # An array of queue names the server is going to listen to. On default uses ["default"]
  config[:config_file] = "./jiggler.yml"  # .yml file with Jiggler settings
  config[:mode]        = :at_most_once    # at_most_once and at_least_once modes supported. Defaults to :at_least_once
end
```

`at_least_once` mode grants reliability for the regular enqueued jobs which are going to be executed by workers. The scheduled jobs (the ones planned to be executed at a specific time, or which failed and going to be retried) still support only `at_most_once` strategy. The support for them is going to be added in the upcoming versions.

On default all queues have the same priority (equals to 0). Higher number means higher prio. \
It's possible to specify custom priorities as follows:

```ruby
Jiggler.configure do |config|
  config[:queues] = [["shippers", 0], ["shipments", 1], ["delivery", 2]]
end
```

#### IO Event selector

`IO_EVENT_SELECTOR` is an env variable which allows to specify the event selector used by the Ruby scheduler. \
On default it uses `Epoll` (`IO_EVENT_SELECTOR=EPoll`). \
Another available option is `URing` (`IO_EVENT_SELECTOR=URing`). Underneath it uses `io_uring` library. It is a Linux kernel library that provides a high-performance interface for asynchronous I/O operations. It was introduced in Linux kernel version 5.1 and aims to address some of the limitations and scalability issues of the existing AIO (Asynchronous I/O) interface.
In the future it might bring a lot of performance boost into Ruby fibers world (once `async` project fully adopts it), but at the moment in the most cases its performance is similar to `EPoll`, yet it could give some boost with File IO.

#### Socketry stack

The gem allows to use libs/calls from `socketry` stack (https://github.com/socketry) within workers. \
Sample:

```ruby
def perform(ids)
  resources = Resource.where(id: ids)
  Async do
    resources.each do |resource|
      Async do
        result = api_client.get(resource)
        resource.update(data: result) if result
      rescue => err
        logger.error(err)
      end
    end
  end
end
```

#### Core components

Internally Jiggler `server` among others includes the next entities: `Manager`, `Poller`, `Monitor`. \
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

# or use built-in async pool with
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

### Contributing

Fork & Pull Request.
