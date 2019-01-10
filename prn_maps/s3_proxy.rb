module PrnMaps
  class S3Proxy
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
    def known_events
      [].tap do |events|
        manifest_objects = bucket.objects(prefix: 'manifests')
        manifest_objects.each do |obj|
          events << {
            name: obj.key,
            etag: obj.etag
          }
        end
      end
    end

    def known_event(manifest_bucket_path)
      obj = bucket.object(manifest_bucket_path)
      JSON.parse(obj.get.body.read)
    end

    private

    def bucket
      @bucket ||= s3.bucket(
        'planetary-response-network'
      )
    end
  end
end
