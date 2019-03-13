require 'sinatra/base'
require "sinatra/json"
require 'sinatra/cross_origin'
require 'rollbar/middleware/sinatra'
require_relative 's3_proxy'
require_relative 'options_basic_auth'

module PrnMaps
  class Api < Sinatra::Base
    VERSION = '0.0.1'.freeze
    CORS_DEFAULTS = '([a-z0-9\-\.]+\.zooniverse\.org|prn-maps\.planetaryresponsenetwork\.org)'

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
      json({ health: "ok", version: VERSION, commit_id: commit_id })
    end

    private

    def commit_id
      @commit_id ||= File.read('public/commit_id.txt')
    end
  end

  class Pending < Api
    use OptionsBasicAuth, "Protected Area" do |username, password|
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

    # This moves all the pending layers to approve event bucket path
    post '/layers/:event_name/approve' do
      json(s3_proxy.approve_pending_event_layers(params[:event_name]))
    end
  end

  class Upload < Api
    use OptionsBasicAuth, "Protected Area" do |username, password|
      username == ENV.fetch("BASIC_AUTH_USERNAME", 'prn') &&
      password == ENV.fetch("BASIC_AUTH_PASSWORD", 'api')
    end

    def self.accepted_types
      @accepted_types ||= {
        layer: "text/csv",
        metadata: 'application/json'
      }
    end

    def self.required_metadata_keys
      @required_metadata_keys ||= %w(file_name created_at)
    end

    options '/layers/:event_name' do
      options_req
    end

    # upload the submitted layer files to s3
    post '/layers/:event_name' do
      errors = validate_correct_files
      if errors.length > 0
        return [400, json({ errors: errors })]
      end

      # TODO: do some validation checking on the uploaded files
      # does the metadata file correlate correctly to the
      # uploaded layer files
      errors = validate_metadata_file
      if errors.length > 0
        return [422, json({ errors: errors })]
      end

      if params[:metadata]['type'] == self.class.accepted_types[:metadata]
        # TODO: actually put this files using S3 Proxy
        uploaded_metadata = params[:metadata]['filename']
      end

      # does the metadata file have to conform to a set schema?
      uploaded_layers = []
      params[:layers].each do |layer|
        if layer['type'] == self.class.accepted_types[:layer]
          # TODO: actually put these files using S3 Proxy
          uploaded_layers << layer['filename']
        end
      end

      result = { layers: uploaded_layers, metadata: uploaded_metadata }
      [201, json(result)]
    end

    private

    def validate_correct_files
      [].tap do |errors|
        metadata_upload = params[:metadata]
        unless metadata_upload.is_a?(Sinatra::IndifferentHash)
          errors << "You must specify a metadata file"
        end

        layer_uploads = params.fetch(:layers, [])
        if layer_uploads.empty?
          errors << "You must specify at least one layer file"
        end
      end
    end

    def validate_metadata_file
      [].tap do |errors|
        begin
          metadata_json = JSON.parse(params[:metadata][:tempfile].read)

          metadata_json['layers'].each_with_index do |layer_upload, layer_num|
            missing_metadata = self.class.required_metadata_keys - layer_upload.keys
            if missing_metadata.length > 0
              errors << "Layer: #{layer_num}, missing attributes: #{missing_metadata.join(",")}"
            end
          end
        rescue JSON::ParserError => e
          errors << e.message
        end
      end
    end
  end
end
