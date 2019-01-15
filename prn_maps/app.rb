require 'sinatra/base'
require "sinatra/json"
require 'sinatra/cross_origin'
require 'rollbar/middleware/sinatra'
require_relative 's3_proxy'

module PrnMaps
  class Api < Sinatra::Base
    VERSION = '0.0.1'.freeze
    CORS_DEFAULTS = '([a-z0-9-\.]+\.zooniverse\.org|prn-maps\.planetaryresponsenetwork\.org)'

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
      # not allowed a regex in CORS_ORIGINS as is
      if env_cors = ENV["CORS_ORIGINS"]
        env_cors
      else
        /^https?:\/\/#{CORS_DEFAULTS}(:\d+)?$/
      end
    end

    def options_req
      cors_origin = request.env.key?('HTTP_ORIGIN')
      cors_method = request.env.key?('HTTP_ACCESS_CONTROL_REQUEST_METHOD')
      cors_headers = request.env.key?('HTTP_ACCESS_CONTROL_REQUEST_HEADERS')
      valid_preflight = cors_origin && cors_method && cors_headers

      if valid_preflight
        headers
        200
      else
        # https://github.com/hapijs/hapi/issues/2868#issuecomment-150315812
        # seems to be a take on the spec i agree with
        404
      end
    end

    def s3_proxy
      @s3_proxy ||= S3Proxy.new
    end
  end

  class Public < Api
    options '/events' do
      options_req
    end

    get '/events' do
      json(s3_proxy.events)
    end

    options '/manifests/:event_name' do
      options_req
    end

    get '/manifests/:event_name' do
      json(s3_proxy.event_manifest(params[:event_name]))
    end

    options '/layers/:event_name' do
      options_req
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
      username == ENV.fetch("BASIC_AUTH_USERNAME", 'prn') &&
      password == ENV.fetch("BASIC_AUTH_PASSWORD", 'api')
    end

    options '/layers/:event_name' do
      options_req
    end

    get '/layers/:event_name' do
      json(s3_proxy.pending_event_layers(params[:event_name]))
    end

    options '/layers/:event_name/approve' do
      options_req
    end

    # This will approve all the pending layers
    # Find out if we need the ability to approve each one?
    post '/layers/:event_name/approve' do
      # TODO add s3 file move from pending to approved path
    end
  end
end
