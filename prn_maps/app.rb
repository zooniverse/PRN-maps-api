require 'sinatra'
require "sinatra/json"
require 'sinatra/cross_origin'
require 'rollbar/middleware/sinatra'
require_relative 's3_proxy'

module PrnMaps
  class Api < Sinatra::Base
    VERSION = '0.0.1'.freeze

    use Rollbar::Middleware::Sinatra
    register Sinatra::CrossOrigin

    configure :production, :staging, :development do
      enable :logging
    end

    before do
      cross_origin allow_origin: cors_origins, allowmethods: [:get]

      content_type 'application/json'

      # other before actions here like auth
    end

    get '/events' do
      json(S3Proxy.new.known_events)
    end

    get '/events/manifests/:id' do
      manifest_path = "manifests/#{params[:id]}"
      json(S3Proxy.new.known_event(manifest_path))
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
