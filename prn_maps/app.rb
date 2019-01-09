require 'sinatra'
require "sinatra/json"
require 'sinatra/cross_origin'
require 'rollbar/middleware/sinatra'

module PrnMaps
  class Api < Sinatra::Base
    VERSION = '0.0.1'.freeze

    use Rollbar::Middleware::Sinatra

    register Sinatra::CrossOrigin

    get '/events' do
      cross_origin :allow_origin => cors_origins, allowmethods: [:get]
      json []
    end

    get '/*' do
      json({ health: "ok", version: VERSION })
    end

    def cors_origins
      cors_origins = ENV["CORS_ORIGINS"] || '([a-z0-9-]+\.zooniverse\.org)'
      /^https?:\/\/#{cors_origins}(:\d+)?$/
    end
  end
end
