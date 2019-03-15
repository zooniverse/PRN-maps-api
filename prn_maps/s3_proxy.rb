# frozen_string_literal: true
require 'aws-sdk-s3'

module PrnMaps
  class S3Proxy
    BUCKET = 'planetary-response-network'
    MANIFEST_PREFIX = 'manifests'
    MANIFEST_NAME_REGEX = %r{.+/(.+).json}.freeze
    LAYER_NAME_REGEX = %r{.+/(.+)\.(.+)}.freeze
    S3_URL_SUFFIX = 's3.amazonaws.com'

    attr_reader :s3

    def initialize
      @s3 = ::Aws::S3::Resource.new
    end

    # TODO: these lists will be pretty static,
    # Look into adding a cache layer
    # to avoid hitting s3 all the time
    def events
      [].tap do |events|
        manifest_objects = bucket.objects(prefix: MANIFEST_PREFIX)
        manifest_objects.each do |obj|
          events << {
            name: manifest_name(obj.key),
            url: bucket_url_generator(obj.key)
          }
        end
      end
    end

    def event_manifest(event_name)
      manifest_path = "#{MANIFEST_PREFIX}/#{event_name}.json"
      begin
        obj = bucket.object(manifest_path)
        result = JSON.parse(obj.get.body.read)
      rescue Aws::S3::Errors::NoSuchKey
        result = { error: 'Failed to find the event name manifest' }
      end
      result
    end

    def approved_event_layers(event_name)
      get_event_layers(event_name, 'approved')
    end

    def pending_event_layers(event_name)
      get_event_layers(event_name, 'pending')
    end

    def approve_pending_event_layers(event_name)
      bucket_path_prefix = "events/#{event_name}/layers"
      approved_bucket_path_prefix = "#{bucket_path_prefix}/approved"
      [].tap do |layers|
        pending_objects = bucket.objects(
          prefix: "#{bucket_path_prefix}/pending/",
          delimiter: '/'
        )
        pending_objects.each do |obj|
          move_target_key = "#{approved_bucket_path_prefix}/#{layer_name_with_extension(obj.key)}"
          obj.move_to(
            bucket: BUCKET,
            key: move_target_key
          )
          layers << {
            name: layer_name(move_target_key),
            url: bucket_url_generator(move_target_key)
          }
        end
      end
    end

    def upload_pending_event_file(event_name, version_num, file_name, temp_file)
      bucket_path_prefix = pending_bucket_path_prefix(event_name)

      # write the upload layer file to s3 event's pending area
      # with a version prefix to track different batch uploads
      # e.g. /pending/v1/*, pending/v2/*
      s3_file_path = "#{bucket_path_prefix}/v#{version_num}/#{file_name}"
      obj = bucket.object(s3_file_path)
      obj.upload_file(temp_file)

      # return the filename that we've uploaded
      file_name
    end

    def next_version(event_name)
      upload_version(event_name).next_version
    end

    def update_pending_upload_version(event_name, version_num)
      upload_version(event_name).update_known_version(version_num)
    end

    private

    def bucket
      @bucket ||= s3.bucket(BUCKET)
    end

    def manifest_name(path)
      MANIFEST_NAME_REGEX.match(path)[1]
    end

    def layer_name(path)
      LAYER_NAME_REGEX.match(path)[1]
    end

    def layer_name_with_extension(path)
      layer_name_match = LAYER_NAME_REGEX.match(path)
      "#{layer_name_match[1]}.#{layer_name_match[2]}"
    end

    def bucket_url_generator(key)
      "https://#{BUCKET}.#{S3_URL_SUFFIX}/#{key}"
    end

    # TODO: add fragment caching here to avoid hitting s3 all the time
    def get_event_layers(event_name, path_suffix)
      [].tap do |layers|
        layer_objects = bucket.objects(
          prefix: "events/#{event_name}/layers/#{path_suffix}/",
          delimiter: '/'
        )
        layer_objects.each do |obj|
          layers << {
            version: 1,
            name: layer_name(obj.key),
            url: bucket_url_generator(obj.key)
          }
        end
      end
    end

    def pending_bucket_path_prefix(event_name)
      "events/#{event_name}/layers/pending"
    end

    def upload_version(event_name)
      @upload_version ||= UploadVersion.new(
        bucket,
        pending_bucket_path_prefix(event_name)
      )
    end

    class UploadVersion
      attr_reader :bucket, :pending_path

      def initialize(bucket, pending_path)
        @bucket = bucket
        @pending_path = pending_path
      end

      def next_version
        begin
          last_known_version = version_file.get.body.read.chomp
        rescue Aws::S3::Errors::NoSuchKey
          last_known_version = 0
        end
        last_known_version.to_i + 1
      end

      def update_known_version(curr_version)
        version_file.put(body: curr_version.to_s)
        curr_version
      end

      private

      def version_file_path
        @version_file_path ||= "#{pending_path}/last_known_version.txt"
      end

      def version_file
        bucket.object(version_file_path)
      end
    end
  end
end
