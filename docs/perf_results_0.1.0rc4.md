### Performance results Jiggler 0.1.0rc4 (at most once delivery)

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
| Sidekiq 7.0.3    | 5           | 100_000   | 20.69 sec | 131_068 kb | 110_544 kb (GC) |
| Jiggler 0.1.0    | 5           | 100_000   | 14.53 sec | 82_020 kb  | 92_904 kb |
| -                |             |           |           |            |           |
| Sidekiq 7.0.3    | 10          | 100_000   | 20.70 sec | 132_048 kb | 122_660 kb (GC) |
| Jiggler 0.1.0    | 10          | 100_000   | 13.75 sec | 82_380 kb  | 93_108 kb |
| -                |             |           |           |            |           |
| Sidekiq 7.0.3    | 5           | 1_000_000 | 189.54 sec | 172_188 kb | 148_180 kb (GC) |
| Jiggler 0.1.0    | 5           | 1_000_000 | 123.13 sec | 91_028 kb  | 98_888 kb |
| -                |             |           |            |            |            |
| Sidekiq 7.0.3    | 10          | 1_000_000 | 184.26 sec | 175_048 kb | 161_744 kb (GC) |
| Jiggler 0.1.0    | 10          | 1_000_000 | 119.05 sec | 90_916 kb | 98_944 kb |

Fibers use little memory, so it is possible to create a lot of fibers without a huge memory footprint. \
It makes sense only with the tasks with a lot of I/O, and even for such tasks we're still limited by the connection pool, network throughput, etc, so extrimely increasing the number of fibers might not be beneficial, but for the sake of test let's try out relatively high concurrency numbers. \
I won't include sidekiq results with high concurrency setting, because it's a bit unfair to it.

| Job Processor    | Concurrency | Jobs      | Time      | Start RSS  | Finish RSS    |
|------------------|-------------|-----------|-----------|------------|---------------|
| Jiggler 0.1.0    | 50          | 100_000   | 13.55 sec | 82_052 kb  | 94_120 kb |
| -                |             |           |           |            |           |
| Jiggler 0.1.0    | 100         | 100_000   | 13.89 sec | 82_084 kb  | 63_284 kb (GC) |
| -                |             |           |           |            |           |
| Jiggler 0.1.0    | 50          | 1_000_000 | 118.11 sec | 89_532 kb | 77_084 kb (GC) |
| -                |             |           |           |            |           |
| Jiggler 0.1.0    | 100         | 1_000_000 | 118.05 sec | 89_702 kb | 77_528 kb (GC) |

The performance with concurrency set to 100 is almost the same or worse than with 50, meaning that the optimal number for the noop task lays somewhere below 100 (or even below 50).

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

It's not recommended to run sidekiq with high concurrency values, setting it (upto 15 for sidekiq) for the sake of test. \
The time difference for these samples is small-ish, however the memory consumption is less with the fibers. \
Since fibers have relatively small memory foot-print and context switching is also relatively cheap, it's possible to set concurrency to higher values within Jiggler without too much trade-offs.

| Job Processor    | Concurrency | Jobs  | Time to complete  | Start RSS | Finish RSS | %CPU |
|------------------|-------------|-------|-------------------|-----------|------------|------|
| Sidekiq 7.0.3    | 5           | 1_000 | 43.65 sec         | 30_632 kb | 45_436 kb  | 9.0 |
| Jiggler 0.1.0    | 5           | 1_000 | 43.58 sec         | 28_724 kb | 35_508 kb  | 6.34 |
| -                |             |       |                   |           |            |      |
| Sidekiq 7.0.3    | 10          | 1_000 | 23.12 sec         | 30_640 kb | 50_436 kb  | 13.26 |
| Jiggler 0.1.0    | 10          | 1_000 | 22.87 sec         | 28_644 kb | 35_788 kb  | 9.32 |
| -                |             |       |                   |           |            |      |
| Sidekiq 7.0.3    | 15          | 1_000 | 16.21 sec         | 30_384 kb | 55_420 kb  | 18.14 |
| Jiggler 0.1.0    | 15          | 1_000 | 16.02 sec         | 28_604 kb | 35_956 kb  | 11.97 |
| -                |             |       |                   |           |            |      |
| Jiggler 0.1.0    | 50          | 1_000 | 6.5 sec           | 28_744 kb | 38_700 kb  | 31.36 |
| -                |             |       |                   |           |            |      |
| Jiggler 0.1.0    | 100         | 1_000 | 4.52 sec          | 28_624 kb | 41_124 kb  | 47.85 |

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
| Sidekiq 7.0.3    | 5           | 1_000 | 23.32 sec | 31_564 kb | 49_112 kb  | 8.41 |
| Jiggler 0.1.0    | 5           | 1_000 | 23.28 sec | 28_672 kb | 39_748 kb  | 5.39 |
| -                |             |       |           |           |            |      |
| Sidekiq 7.0.3    | 10          | 1_000 | 13.15 sec | 31_272 kb | 52_808 kb  | 14.76 |
| Jiggler 0.1.0    | 10          | 1_000 | 12.82 sec | 28_992 kb | 38_784 kb  | 9.98 |
| -                |             |       |           |           |            |      |
| Sidekiq 7.0.3    | 15          | 1_000 | 9.63 sec  | 31_016 kb | 59_868 kb  | 20.45 |
| Jiggler 0.1.0    | 15          | 1_000 | 9.37 sec  | 28_704 kb | 39_960 kb  | 14.14 |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0    | 50          | 1_000 | 5.2 sec   | 28_808 kb | 42_012 kb  | 41.5 |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0    | 100         | 1_000 | 5.11 sec  | 28_884 kb | 46_636 kb  | 66.0 |

NOTE: check how many connections your postgresql server can accept at once (default is 100).

##### File IO

```ruby
def perform(file_name, id)
  File.open(file_name, "a") { |f| f.write("#{id}\n") }
end
```

| Job Processor    | Concurrency | Jobs   | Time      | Start RSS    | Finish RSS | %CPU  |
|------------------|-------------|--------|-----------|--------------|------------|-------|
| Sidekiq 7.0.3    | 5           | 50_000 | 19.77 sec | 83_244 kb    | 72_576 kb (GC) | 99.6 |
| Jiggler 0.1.0    | 5           | 50_000 | 10.51 sec | 56_348 kb    | 65_554 kb  | 92.06 |
| -                |             |        |           |              |            |       |
| Sidekiq 7.0.3    | 10          | 50_000 | 17.57 sec | 83_268 kb    | 81_204 kb (GC) | 95.15 |
| Jiggler 0.1.0    | 10          | 50_000 | 10.29 sec | 55_412 kb    | 64_558 kb  | 93.08 |
| -                |             |        |           |              |            |      |
| Sidekiq 7.0.3    | 15          | 50_000 | 17.03 sec | 83_312 kb    | 87_176 kb (GC) | 94.7 |
| Jiggler 0.1.0    | 15          | 50_000 | 10.7 sec  | 55_852 kb    | 65_716 kb  | 94.64 |
| -                |             |        |           |              |            |      |
| Jiggler 0.1.0    | 50          | 50_000 | 10.9 sec  | 55_680 kb    | 65_888 kb  | 92.9 |
| -                |             |        |           |              |            |      |
| Jiggler 0.1.0    | 100         | 50_000 | 10.71 sec | 56_500 kb    | 52_768 kb (GC) | 94.6 |

For this test 15-50-100 concurrency didn't provide much benefits, so the optimal number lays somewhere below this.

#### Simulate CPU-only job

Jiggler is effective only for tasks with a lot of IO. You must test the concurrency setting with your jobs to find out what configuration works best for your payload. With CPU-heavy jobs both Sidekiq and Jiggler do not provide performance boost compared to sequental execution. Yet Jiggler has a tiny bit better results compared to the thread-based approach, because of lightweight fiber context-switches. Test with CPU-only payload:

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
| Sidekiq 7.0.3    | 5           | 100  | 5.81 sec | 27_792 kb  | 42_464 kb |
| Jiggler 0.1.0    | 5           | 100  | 5.53 sec | 27_020 kb  | 33_660 kb |
| -                |             |      |          |            |           |
| Sidekiq 7.0.3    | 10          | 100  | 5.63 sec | 28_044 kb  | 47_640 kb |
| Jiggler 0.1.0    | 10          | 100  | 5.43 sec | 27_136 kb  | 33_856 kb |

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
| Jiggler 0.1.0    | 5           | 1_000 | 43.31 sec | 30_548 kb | 38_512 kb  | 2.17 |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0    | 10          | 1_000 | 22.75 sec | 30_584 kb | 38_460 kb  | 4.1  |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0    | 15          | 1_000 | 15.88 sec | 30_536 kb | 38_580 kb  | 5.74 |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0    | 50          | 1_000 | 6.3 sec   | 30_608 kb | 40_900 kb  | 16.83 |
| -                |             |       |           |           |            |      |
| Jiggler 0.1.0    | 100         | 1_000 | 4.31 sec  | 30_828 kb | 43_296 kb  | 27.25 |

#### Idle

3 minutes of idle work.

| Job Processor    | Concurrency | Start RSS | Finish RSS | %CPU |
|------------------|-------------|-----------|------------|------|
| Sidekiq 7.0.3    | 5           | 27_508 kb | 42_680 kb  | 0.73 |
| Jiggler 0.1.0    | 5           | 26_640 kb | 34_848 kb  | 0.42 |
| -                |             |           |            |      |
| Sidekiq 7.0.3    | 10          | 28_312 kb | 47_856 kb  | 0.85 |
| Jiggler 0.1.0    | 10          | 26_576 kb | 34_388 kb  | 0.45 |
| -                |             |           |            |      |
| Sidekiq 7.0.3    | 15          | 28_472 kb | 53_236 kb  | 0.9  |
| Jiggler 0.1.0    | 15          | 26_584 kb | 34_336 kb  | 0.5  |
| -                |             |           |            |      |
| Jiggler 0.1.0    | 50          | 26_740 kb | 35_556 kb  | 0.72 |
| -                |             |           |            |      |
| Jiggler 0.1.0    | 100         | 26_648 kb | 37_404 kb  | 1.03 |
