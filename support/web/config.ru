require_relative '../../lib/jiggler/config'
require_relative '../../lib/jiggler/core'
require_relative '../../lib/jiggler/redis_store'
require_relative '../../lib/jiggler/support/component'
require_relative '../../lib/jiggler/stats/monitor'
require_relative '../../lib/jiggler/summary'
require_relative '../../lib/jiggler/web'

run Jiggler::Web.new
