Bundler.require

require './prn_maps/app.rb'
require './prn_maps/config.rb'

require 'pry' if PrnMaps::Config.local?

Rollbar.configure do |config|
  enabled = use_async = PrnMaps::Config.enable_error_reports?
  config.access_token = PrnMaps::Config.rollbar_token
  config.environment  = PrnMaps::Config.environment
  config.enabled      = enabled
  config.use_async    = use_async
end

run PrnMaps::Api
