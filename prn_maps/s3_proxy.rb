module PrnMaps
  class S3Proxy
    BUCKET = 'planetary-response-network'.freeze
    MANIFEST_PREFIX = 'manifests'.freeze
    MANIFEST_NAME_REGEX = /.+\/(.+).json/

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
            name: manifest_path(obj.key),
            manifest_s3_path: "#{BUCKET}/#{obj.key}"
          }
        end
      end
    end

    def event_manifest(event_name)
      manifest_path = "#{MANIFEST_PREFIX}/#{event_name}.json"
      obj = bucket.object(manifest_path)
      JSON.parse(obj.get.body.read)
    end

    private

    def bucket
      @bucket ||= s3.bucket(BUCKET)
    end

    def manifest_path(path)
      MANIFEST_NAME_REGEX.match(path)[1]
    end
  end
end
