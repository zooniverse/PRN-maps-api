# frozen_string_literal: true

require_relative 'api'
require_relative 'options_basic_auth'

module PrnMaps
  class Upload < Api
    use OptionsBasicAuth, 'Protected Area' do |username, password|
      username == ENV.fetch('BASIC_AUTH_USERNAME', 'prn') &&
        password == ENV.fetch('BASIC_AUTH_PASSWORD', 'api')
    end

    def self.accepted_types
      @accepted_types ||= {
        layer: 'text/csv',
        metadata: 'application/json'
      }
    end

    def self.required_metadata_keys
      @required_metadata_keys ||= %w[file_name created_at]
    end

    options '/layers/:event_name' do
      options_req
    end

    # upload the submitted layer files to s3
    post '/layers/:event_name' do
      errors = validate_correct_files
      return [400, json(errors: errors)] unless errors.empty?

      # TODO: do some validation checking on the uploaded files
      # does the metadata file correlate correctly to the
      # uploaded layer files
      errors = validate_metadata_file
      return [422, json(errors: errors)] unless errors.empty?

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
          errors << 'You must specify a metadata file'
        end

        layer_uploads = params.fetch(:layers, [])
        if layer_uploads.empty?
          errors << 'You must specify at least one layer file'
        end
      end
    end

    def validate_metadata_file
      [].tap do |errors|
        metadata_json['layers'].each_with_index do |layer_upload, layer_num|
          if (layer_error = validate_layer_metadata(layer_upload, layer_num))
            errors << layer_error
          end
        end
      rescue JSON::ParserError => e
        errors << e.message
      end
    end

    def metadata_json
      @metadata_json ||= JSON.parse(params[:metadata][:tempfile].read)
    end

    def validate_layer_metadata(layer_upload, layer_num)
      missing_metadata = self.class.required_metadata_keys - layer_upload.keys
      return if missing_metadata.empty?

      "Layer: #{layer_num}, missing attributes: #{missing_metadata.join(',')}"
    end
  end
end
