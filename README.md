# jiggler
Background job processor based on Socketry Async

Jiggler is a Sidekiq-inspired background job processor based on Socketry Async.
It uses fibers to processes jobs, making the processing lightweight and efficient.

### Installation

TODO

### Getting Started

TODO

### Local development

Docker is supported.

Start & build:
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
