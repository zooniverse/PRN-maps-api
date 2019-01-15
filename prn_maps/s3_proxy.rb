# frozen_string_literal: true
module PrnMaps
  class S3Proxy
    BUCKET = 'planetary-response-network'
    MANIFEST_PREFIX = 'manifests'
    MANIFEST_NAME_REGEX = /.+\/(.+).json/
    LAYER_NAME_REGEX = /.+\/(.+)\.(.+)/
    S3_URL_SUFFIX = 's3.amazonaws.com'

    attr_reader :s3

    def initialize
      @s3 ||= Aws::S3::Resource.new
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
        result = { error: "Failed to find the event name manifest"}
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
            name: layer_name(obj.key),
            url: bucket_url_generator(obj.key)
          }
        end
      end
    end
  end
end
