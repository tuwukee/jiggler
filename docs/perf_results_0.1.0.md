### Performance results Jiggler 0.1.0

The tests were run on local (Ubuntu 22.04, Intel(R) Core(TM) i7 6700HQ 2.60GHz). \

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

AMO - at most once
ALO - at least once

| Job Processor       | Concurrency | Jobs      | Time      | Start RSS  | Finish RSS    |
|---------------------|-------------|-----------|-----------|------------|---------------|
| Jiggler 0.1.0 (AMO) | 10          | 100_000   | 14.17 sec | 82_152 kb  | 100_160 kb |
| Jiggler 0.1.0 (ALO) | 10          | 100_000   | 26.56 sec | 82_212 kb  | 103_420 kb |
| -                   |             |           |           |            |            |
| Jiggler 0.1.0 (AMO) | 50          | 100_000   | 13.96 sec | 82_060 kb  | 101_480 kb |
| Jiggler 0.1.0 (ALO) | 50          | 100_000   | 26.19 sec | 82_204 kb  | 75_068 kb (GC) |

Note: noop task isn't really representative though, it's best to measure performance on some real tasks, to see how much context switching affects specific payload depending on CPU/IO balance.

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

| Job Processor       | Concurrency | Jobs      | Time      | Start RSS  | Finish RSS | %CPU  |
|---------------------|-------------|-----------|-----------|------------|------------|-------|
| Jiggler 0.1.0 (AMO) | 10          | 1_000     | 23.25 sec | 28_872 kb  | 44_896 kb  | 10.8% |
| Jiggler 0.1.0 (ALO) | 10          | 1_000     | 22.86 sec | 28_868 kb  | 45_524 kb  | 11.3% |
| -                   |             |           |           |            |            |       |
| Jiggler 0.1.0 (AMO) | 50          | 1_000     | 6.78 sec  | 28_804 kb  | 46_740 kb  | 36.9% |
| Jiggler 0.1.0 (ALO) | 50          | 1_000     | 6.45 sec  | 28_948 kb  | 47_624 kb  | 38.1% |
| -                   |             |           |           |            |            |       |
| Jiggler 0.1.0 (AMO) | 100         | 1_000     | 4.71 sec  | 29_464 kb  | 49_040 kb  | 55.7% |
| Jiggler 0.1.0 (ALO) | 100         | 1_000     | 4.49 sec  | 28_948 kb  | 47_624 kb  | 60.0% |

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

| Job Processor       | Concurrency | Jobs      | Time      | Start RSS  | Finish RSS | %CPU  |
|---------------------|-------------|-----------|-----------|------------|------------|-------|
| Jiggler 0.1.0 (AMO) | 10          | 1_000     | 12.95 sec | 28_872 kb  | 50_016 kb  | 12.4% |
| Jiggler 0.1.0 (ALO) | 10          | 1_000     | 12.99 sec | 28_868 kb  | 50_076 kb  | 12.6% |
| -                   |             |           |           |            |            |       |
| Jiggler 0.1.0 (AMO) | 50          | 1_000     | 5.38 sec  | 28_724 kb  | 51_904 kb  | 47.0% |
| Jiggler 0.1.0 (ALO) | 50          | 1_000     | 5.37 sec  | 28_908 kb  | 52_516 kb  | 50.7% |
| -                   |             |           |           |            |            |       |
| Jiggler 0.1.0 (AMO) | 100         | 1_000     | 5.39 sec  | 29_464 kb  | 54_644 kb  | 69.8% |
| Jiggler 0.1.0 (ALO) | 100         | 1_000     | 5.17 sec  | 28_896 kb  | 56_148 kb  | 70.3% |

##### File IO

```ruby
def perform(file_name, id)
  File.open(file_name, "a") { |f| f.write("#{id}\n") }
end
```

| Job Processor       | Concurrency | Jobs      | Time      | Start RSS  | Finish RSS | %CPU  |
|---------------------|-------------|-----------|-----------|------------|------------|-------|
| Jiggler 0.1.0 (AMO) | 10          | 50_000    | 11.95 sec | 54_760 kb  | 56_304 kb  | 91.0% |
| Jiggler 0.1.0 (ALO) | 10          | 50_000    | 18.07 sec | 54_780 kb  | 58_128 kb  | 91.6% |
| -                   |             |           |           |            |            |       |
| Jiggler 0.1.0 (AMO) | 50          | 50_000    | 10.9 sec  | 54_608 kb  | 57_432 kb  | 91.5% |
| Jiggler 0.1.0 (ALO) | 50          | 50_000    | 17.18 sec | 54_748 kb  | 60_128 kb  | 96.8% |


#### CPU-only job

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

| Job Processor       | Concurrency | Jobs      | Time      | Start RSS  | Finish RSS | %CPU  |
|---------------------|-------------|-----------|-----------|------------|------------|-------|
| Jiggler 0.1.0 (AMO) | 10          | 1_000     | 35.48 sec | 26_916 kb  | 43_460 kb  | 98.1% |
| Jiggler 0.1.0 (ALO) | 10          | 1_000     | 35.45 sec | 27_100 kb  | 43_860 kb  | 94.5% |
| -                   |             |           |           |            |            |       |
| Jiggler 0.1.0 (AMO) | 50          | 1_000     | 35.77 sec | 27_188 kb  | 44_532 kb  | 98.3% |
| Jiggler 0.1.0 (ALO) | 50          | 1_000     | 35.93 sec | 27_020 kb  | 45_816 kb  | 99.7% |

#### Idle

3 minutes of idle work.

| Job Processor       | Concurrency | Start RSS | Finish RSS | %CPU |
|---------------------|-------------|-----------|------------|------|
| Jiggler 0.1.0 (AMO) | 10          | 27_508 kb | 44_568 kb  | 1.0% |
| Jiggler 0.1.0 (ALO) | 10          | 27_404 kb | 43_224 kb  | 1.0% |
| -                   |             |           |            |      |
| Jiggler 0.1.0 (AMO) | 50          | 27_184 kb | 44_952 kb  | 1.3% |
| Jiggler 0.1.0 (ALO) | 50          | 27_180 kb | 44_924 kb  | 1.0% |
| -                   |             |           |            |      |
| Jiggler 0.1.0 (AMO) | 100         | 27_508 kb | 46_352 kb  | 1.6% |
| Jiggler 0.1.0 (ALO) | 100         | 26_640 kb | 47_172 kb  | 1.0% |
