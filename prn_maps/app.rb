require 'sinatra/base'
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
      cross_origin allow_origin: cors_origins, allowmethods: [:get, :post]

      content_type 'application/json'
    end

    private

    def cors_origins
      cors_origins = ENV["CORS_ORIGINS"] || '([a-z0-9-]+\.zooniverse\.org|prn-maps\.planetary-response-network\.org)'
      /^https?:\/\/#{cors_origins}(:\d+)?$/
    end

    def s3_proxy
      @s3_proxy ||= S3Proxy.new
    end
  end

  class Public < Api
    get '/events' do
      json(s3_proxy.events)
    end

    get '/manifests/:event_name' do
      json(s3_proxy.event_manifest(params[:event_name]))
    end

    get '/layers/:event_name' do
      json(s3_proxy.approved_event_layers(params[:event_name]))
    end

    get '/*' do
      json({ health: "ok", version: VERSION })
    end
  end

  class Pending < Api

    use Rack::Auth::Basic, "Protected Area" do |username, password|
      username == 'foo' && password == 'bar'
    end

    get '/layers/:event_name' do
      json(s3_proxy.pending_event_layers(params[:event_name]))
    end

    # This will approve all the pending layers
    # Find out if we need the ability to approve each one?
    post '/layers/:event_name/approve' do
      # TODO add s3 file move from pending to approved path
    end
  end
end
