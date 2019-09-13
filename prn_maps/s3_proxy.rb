# frozen_string_literal: true

require 'aws-sdk-s3'

module PrnMaps
  class S3Proxy
    BUCKET = 'planetary-response-network'
    MANIFEST_PREFIX = 'manifests'
    MANIFEST_NAME_REGEX = %r{.+/(.+).json}.freeze
    LAYER_NAME_REGEX = %r{.+/(.+)\.(.+)}.freeze
    LAYER_VERSION_REGEX = %r{.+\/(v\d+)\/.+\..+}.freeze
    METADATA_LAYER_REGEX = %r{.+\/.+metadata.?\.json}.freeze
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
      get_event_layers(event_name, 'approved/v')
    end

    def filter_approved_event_layers(event_name, version, name)
      get_event_layers(event_name, "approved/#{version}") do |layer_objects|
        layer_objects.select do |layer_obj|
          name == layer_name_with_extension(layer_obj.key) ||
            metadata_layer?(layer_obj.key)
        end
      end
    end

    def pending_event_layers(event_name)
      get_event_layers(event_name, 'pending/v')
    end

    def approve_pending_event_layers(event_name, version)
      bucket_path_prefix = "events/#{event_name}/layers"
      approved_bucket_path_prefix = "#{bucket_path_prefix}/approved/#{version}"
      [].tap do |layers|
        pending_version_objects = find_version_objects(
          "#{pending_bucket_path_prefix(event_name)}/#{version}/"
        )
        pending_version_objects.each do |obj|
          moved_obj_path = move_s3_object(obj, approved_bucket_path_prefix)
          layers << {
            name: layer_name(moved_obj_path),
            url: bucket_url_generator(moved_obj_path)
          }
        end
      end
    end

    def revert_approved_event_layers(event_name, version)
      bucket_path_prefix = "events/#{event_name}/layers"
      pending_bucket_path_prefix = "#{pending_bucket_path_prefix(event_name)}/#{version}"
      [].tap do |layers|
        approved_version_objects = find_version_objects(
          "#{bucket_path_prefix}/approved/#{version}"
        )
        approved_version_objects.each do |obj|
          moved_obj_path = move_s3_object(obj, pending_bucket_path_prefix)
          layers << {
            name: layer_name(moved_obj_path),
            url: bucket_url_generator(moved_obj_path)
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

    def layer_version(path)
      LAYER_VERSION_REGEX.match(path)[1]
    end

    def metadata_layer?(path)
      !!METADATA_LAYER_REGEX.match(path)
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
      layer_prefix = "events/#{event_name}/layers/#{path_suffix}"
      layer_objects = bucket.objects(prefix: layer_prefix, delimiter: '')

      layer_objects = yield layer_objects if block_given?

      version_data = build_event_layer_version_data(layer_objects)
      sorted_version_data = sorted_version_data(version_data)
      version_event_layers(sorted_version_data, version_data)
    end

    # these formatting methods below look like a class to extract
    def build_event_layer_version_data(layer_objects)
      {}.tap do |version_data|
        layer_objects.each do |obj|
          version_num = layer_version(obj.key)
          version_num_data = version_data[version_num] ||= { layers: [] }
          if metadata_layer?(obj.key)
            version_num_data[:metadata_url] = bucket_url_generator(obj.key)
            next
          end
          version_num_data[:layers] << {
            name: layer_name(obj.key),
            url: bucket_url_generator(obj.key)
          }
        end
      end
    end

    # client request to have the lastest version data first
    def sorted_version_data(version_data)
      version_data.keys.sort do |x, y|
        y[1..-1].to_i <=> x[1..-1].to_i
      end
    end

    def version_event_layers(version_keys, version_data)
      [].tap do |result_layers|
        version_keys.each do |ver_key|
          result_layers << {
            version: ver_key,
            metadata_url: version_data[ver_key][:metadata_url],
            layers: version_data[ver_key][:layers]
          }
        end
      end
    end

    def find_version_objects(versions_prefix)
      bucket.objects(prefix: versions_prefix, delimiter: '/')
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

    # move the object to the target path prefix
    # and return the path the object was moved to
    def move_s3_object(obj, target_path_prefix)
      move_target_key = "#{target_path_prefix}/#{layer_name_with_extension(obj.key)}"
      obj.move_to(
        bucket: BUCKET,
        key: move_target_key
      )

      move_target_key
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
