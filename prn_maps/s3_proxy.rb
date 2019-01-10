module PrnMaps
  class S3Proxy
    MANIFEST_PREFIX = 'manifests'.freeze
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
            name: event_name_from_manifest_path(obj.key),
            manifest_path: obj.key
          }
        end
      end
    end

    def event_manifest(manifest_id)
      manifest_path = "#{MANIFEST_PREFIX}/#{manifest_id}"
      obj = bucket.object(manifest_path)
      JSON.parse(obj.get.body.read)
    end

    private

    def bucket
      @bucket ||= s3.bucket(
        'planetary-response-network'
      )
    end

    def event_name_from_manifest_path(manifest_path)
      manifest_path.split("/").last
    end
  end
end
