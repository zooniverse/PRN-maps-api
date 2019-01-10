module PrnMaps
  class S3Proxy
    attr_reader :s3

    def initialize
      @s3 ||= Aws::S3::Resource.new
    end

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

    private

    def bucket
      @bucket ||= s3.bucket(
        'planetary-response-network'
      )
    end
  end
end
