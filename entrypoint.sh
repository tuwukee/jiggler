#!/bin/bash
# Interpreter identifier

# Exit on fail
set -e

rm -f $ROOT_DIR/tmp/pids/server.pid

exec "$@"
