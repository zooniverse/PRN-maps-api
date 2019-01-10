# frozen_string_literal: true
module PrnMaps
  class S3Proxy
    BUCKET = 'planetary-response-network'
    MANIFEST_PREFIX = 'manifests'
    MANIFEST_NAME_REGEX = /.+\/(.+).json/
    LAYER_NAME_REGEX = /.+\/(.+)\..+/
    S3_URL_SUFFIX = 's3.amazonaws.com'

    attr_reader :s3

    def initialize
      @s3 ||= Aws::S3::Resource.new
    end

    # THOUGHT?? could we use the bucket to be a web server
    # for only the manifests files? (probably need an index listing...)
    # might save on costs / code with ruby

    # TODO: these lists will be pretty static,
    # Look into adding a cache layer
    # to avoid hitting s3 all the time
    def events
      [].tap do |events|
        manifest_objects = bucket.objects(prefix: MANIFEST_PREFIX)
        manifest_objects.each do |obj|
          events << {
            name: manifest_name(obj.key),
            manifest_s3_path: "#{BUCKET}/#{obj.key}"
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

    def event_layers(event_name)
      [].tap do |layers|
        layer_objects = bucket.objects(
          prefix: "events/#{event_name}/layers/",
          delimiter: '/'
        )
        layer_objects.each do |obj|
          layers << {
            name: layer_name(obj.key),
            manifest_s3_path: "#{BUCKET}/#{obj.key}"
          }
        end
      end
    end

    def event_layers(event_name)
      [].tap do |layers|
        layer_objects = bucket.objects(
          prefix: "events/#{event_name}/layers/",
          delimiter: '/'
        )
        layer_objects.each do |obj|
          layers << {
            name: layer_name(obj.key),
            layer_s3_path: "#{BUCKET}/#{obj.key}",
            url: "https://#{BUCKET}.#{S3_URL_SUFFIX}/#{obj.key}"
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
  end
end
