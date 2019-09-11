# frozen_string_literal: true

require_relative 'api'
require_relative 'options_basic_auth'

module PrnMaps
  class Upload < Api
    use OptionsBasicAuth, 'Protected Area' do |username, password|
      username == ENV.fetch('BASIC_AUTH_USERNAME', 'prn') &&
        password == ENV.fetch('BASIC_AUTH_PASSWORD', 'api')
    end

    options '/layers/:event_name' do
      options_req
    end

    # upload the submitted layer files to s3
    post '/layers/:event_name' do
      event_name = params[:event_name]
      errors = validate_correct_files_exist
      return [400, json(errors: errors)] unless errors.empty?

      validator = UploadValidator.new(params[:metadata], params[:layers])
      unless validator.valid?
        return [422, json(errors: validator.errors)]
      end

      # get the known upload version state for this event
      upload_version_num = s3_proxy.next_version(event_name)

      # seems like uploading lots of files may be a bottle neck
      # will have to look at optimizing these s3 calls
      # maybe? https://github.com/grosser/parallel

      # add uploaded_at data to the temp file, urgh, i'm a bad person
      # adding an s3_proxy method to upload data object vs file input
      # would be the better solution
      tmp_metadata_file = params[:metadata]['tempfile']
      # rewind the file so it can be read...again
      tmp_metadata_file.rewind
      tmp_metadata = tmp_metadata_file.read
      # add the uploaded_at attribute to the json
      metadata_json = JSON.parse(tmp_metadata)
      uploaded_at_time_stamp = Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
      metadata_json['uploaded_at'] = uploaded_at_time_stamp

      # create a new temp file for the modified metadata json
      tmp_metadata_file = Tempfile.new('upload_metadata')
      tmp_metadata_file.write(
        JSON.pretty_generate(metadata_json)
      )
      # ensure we rewind the file here to flush buffered output
      # and an unwound file causes very slow s3 upload speeds
      tmp_metadata_file.rewind

      uploaded_metadata = s3_proxy.upload_pending_event_file(
        event_name,
        upload_version_num,
        params[:metadata]['filename'],
        tmp_metadata_file
      )

      # does the metadata file have to conform to a set schema?
      uploaded_layers = []
      params[:layers].each do |layer|
        uploaded_file = s3_proxy.upload_pending_event_file(
          event_name,
          upload_version_num,
          layer['filename'],
          layer['tempfile']
        )
        uploaded_layers << uploaded_file
      end

      # after successful file upload, make sure we update the known version
      # so the next upload can prefix properly
      s3_proxy.update_pending_upload_version(event_name, upload_version_num)

      result = { layers: uploaded_layers, metadata: uploaded_metadata }
      [201, json(result)]
    end

    private

    def validate_correct_files_exist
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

    class UploadValidator
      attr_reader :metadata_upload, :layers_upload

      def self.required_layer_keys
        @required_layer_keys ||= %w[file_name description legend]
      end

      def self.required_metadata
        @required_metadata ||= {
          'AOI' => 'supply an AOI attribute value that describes the layer data geographically (Area Of Interest)',
          'created_at' => 'supply a created_at attribute value that describes the upload creation time'
        }
      end

      def self.metadata_file_type
        @metadata_file_type ||= 'application/json'
      end

      def self.layer_file_type
        @layer_file_type ||= 'text/csv'
      end

      def initialize(metadata_upload, layers_upload)
        @metadata_upload = metadata_upload
        @layers_upload = layers_upload
        @errors = []
      end

      def valid?
        validate_upload_file_types
        return false if @errors.length.positive? # fail as fast as we can

        begin
          metadata_layers
        rescue JSON::ParserError
          @errors << 'please lint your JSON file'
          return false
        end

        validate_uploaded_counts
        return false if @errors.length.positive? # fail as fast as we can

        validate_upload_metadata
        return false if @errors.length.positive? # fail as fast as we can

        validate_uploaded_layers

        @errors.empty?
      end

      def errors
        @errors.map { |error| "Invalid metadata - #{error}" }
      end

      private

      def metadata_layers
        @metadata_layers ||= metadata_json['layers']
      end

      def metadata_json
        @metadata_json ||= JSON.parse(
          metadata_upload[:tempfile].read
        )
      end

      def validate_upload_file_types
        valid_metadata_file? && valid_layer_files?
      end

      def valid_metadata_file?
        valid_file = true
        invalid_file_type = metadata_upload['type'] != self.class.metadata_file_type
        invalid_file_name = !metadata_upload['filename'].include?('metadata')

        if invalid_file_type
          valid_file = false
          @errors << "file type must be #{self.class.metadata_file_type}"
        elsif invalid_file_name
          valid_file = false
          @errors << 'file name must contain metadata'
        end

        valid_file
      end

      def valid_layer_files?
        layers_upload.all? do |layer_upload|
          valid_file = layer_upload['type'] == self.class.layer_file_type
          unless valid_file
            @errors << "file type must be #{self.class.layer_file_type}"
          end
          valid_file
        end
      end

      def validate_uploaded_counts
        if metadata_layers.length != layers_upload.length
          @errors << 'number of entries does not match the number of uploaded files'
          return # fail fast
        end

        uniq_files_match = uniq_metadata_file_names.length == metadata_layers.length
        return if uniq_files_match

        @errors << 'file contains non unique entries'
      end

      def validate_upload_metadata
        self.class.required_metadata.each do |metadata_key, error_message|
          unless metadata_json.key?(metadata_key)
            @errors << error_message
          end
        end
      end

      def validate_uploaded_layers
        metadata_layers.each_with_index do |layer_metadata, layer_num|
          validate_layer_metadata(layer_metadata, layer_num)

          layer_filename = layer_metadata['file_name']
          next unless layer_filename

          validate_layer_files(layer_filename, layer_num)
        end
      end

      # validate the metadata has the required schema
      def validate_layer_metadata(layer_metadata, layer_num)
        missing_metadata = self.class.required_layer_keys - layer_metadata.keys
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

      def uniq_metadata_file_names
        metadata_layers.map { |metadata| metadata['file_name'] }.uniq
      end
    end
  end
end
