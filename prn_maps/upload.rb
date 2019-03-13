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
      validator = MetadataValidator.new(params[:metadata], params[:layers])
      unless validator.valid?
        return [422, json(errors: validator.errors)]
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
          errors << 'You must specify a metadata file'
        end

        layer_uploads = params.fetch(:layers, [])
        if layer_uploads.empty?
          errors << 'You must specify at least one layer file'
        end
      end
    end

    class MetadataValidator
      attr_reader :metadata_upload, :layers_upload

      def self.required_keys
        @required_keys ||= %w[file_name created_at]
      end

      def initialize(metadata_upload, layers_upload)
        @metadata_upload = metadata_upload
        @layers_upload = layers_upload
        @errors = []
      end

      def valid?
        # validate_layer_counts(layer_metadata, layer_num)

        metadata_layers.each_with_index do |layer_metadata, layer_num|
          validate_layer_metadata(layer_metadata, layer_num)

          layer_filename = layer_metadata['file_name']
          next unless layer_filename

          validate_layer_files(layer_filename, layer_num)
        end

        @errors.empty?
      end

      def errors
        @errors.map { |error| "Invalid metadata - #{error}" }
      end

      private

      def metadata_layers
        @metadata_layers ||= metadata_json.fetch('layers', [])
      end

      def metadata_json
        JSON.parse(metadata_upload[:tempfile].read)
      rescue JSON::ParserError
        @errors << 'please lint your JSON file'
        {}
      end

      # validate the metadata has the required schema
      def validate_layer_metadata(layer_metadata, layer_num)
        missing_metadata = self.class.required_keys - layer_metadata.keys
        return if missing_metadata.empty?

        @errors << layer_error_msg(
          layer_num,
          "missing attributes: #{missing_metadata.join(',')}"
        )
      end

      # validate the layer metadata describes an uploaded layer file
      def validate_layer_files(layer_filename, layer_num)
        found_layer_file = layers_upload.detect do |layer_upload|
          layer_upload['filename'] == layer_filename
        end
        return if found_layer_file

        @errors << layer_error_msg(
          layer_num,
          "lists missing layer file: #{layer_filename}"
        )
      end

      def layer_error_msg(layer_num, msg)
        "Layer: #{layer_num} #{msg}"
      end
    end
  end
end
