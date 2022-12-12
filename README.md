# jiggler
Pet Project &lt;3

jiggle jiggle

Entities:
Launcher - starts a manager and a scheduler, once receives :done should gracefully shut down the manager and the scheduler
Manager - starts, monitors and restart processors, waits for processors to finish or shut down after timeout when :done is received
Processor - polls a single job from redis, inits and runs it, then repeats, once receives :done waits for the job to complete and invokes manager's callback, if an exception happens - invokes manager's callback and retries the job
Scheduler - reads scheduled and retried jobs (sorted set in redis) and puts them back into appropriate queues
Runner - traps system signals, inits launcher

docker-compose up -d && docker attach jiggler_app
docker-compose exec app bundle exec irb
docker-compose run --rm web -- bundle exec rspec
