# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/cross_origin'
require 'rollbar/middleware/sinatra'
require_relative 's3_proxy'

module PrnMaps
  class Api < Sinatra::Base
    use Rollbar::Middleware::Sinatra
    register Sinatra::CrossOrigin

    configure :production, :staging, :development do
      enable :logging
    end

    before do
      cross_origin allow_origin: cors_origins, allowmethods: %i[get post]

      content_type 'application/json'
    end

    def self.version
      '0.0.1'
    end

    def self.cors_defaults
      '([a-z0-9\-\.]+\.zooniverse\.org|prn-maps\.planetaryresponsenetwork\.org)'
    end

    private

    def cors_origins
      # not allowed a regex in CORS_ORIGINS as is
      if (env_cors = ENV['CORS_ORIGINS'])
        env_cors
      else
        %r{^https?://#{self.class.cors_defaults}(:\d+)?$}
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
end
