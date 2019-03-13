require_relative 'spec_helper'

include Rack::Test::Methods

describe "uploading layer files" do

  def app
    PrnMaps::Upload
  end

  describe "without credentials" do
    it "should request authentication" do
      post '/layers/test_layer', {}
      last_response.status.must_equal(401)
    end
  end

  describe "with credentials" do
    before { authorize 'prn', 'api' }

    def error_formatting(*errors)
      {errors: errors}.to_json
    end

    it "should reject empty payloads" do
      post '/layers/test_layer', {}
      last_response.status.must_equal(400)
      last_response.body.must_equal(
        error_formatting(
          "You must specify a metadata file",
          "You must specify at least one layer file"
        )
      )
    end

    it "should reject missing metadata files" do
      payload = {
        layers: [
          Rack::Test::UploadedFile.new("spec/test_files/layer_1.csv", "text/csv"),
        ]
      }
      post '/layers/test_layer', payload
      last_response.status.must_equal(400)
      last_response.body.must_equal(
        error_formatting("You must specify a metadata file")
      )
    end

    it "should reject missing layer files" do
      payload = {
        metadata: Rack::Test::UploadedFile.new("spec/test_files/layer_1_metadata.json", "application/json")
      }
      post '/layers/test_layer', payload
      last_response.status.must_equal(400)
      last_response.body.must_equal(
        error_formatting("You must specify at least one layer file")
      )
    end

    it "should accept one layer file" do
      payload = {
        layers: [
          Rack::Test::UploadedFile.new("spec/test_files/layer_1.csv", "text/csv"),
        ],
        metadata: Rack::Test::UploadedFile.new("spec/test_files/layer_1_metadata.json", "application/json")
      }
      post '/layers/test_layer', payload
      last_response.status.must_equal(201)
      result = { layers: ["layer_1.csv"], metadata: "layer_1_metadata.json" }
      last_response.body.must_equal(result.to_json)
    end

    focus
    it "should respond with useful error when metadata upload is an invalid schema" do
      payload = {
        layers: [
          Rack::Test::UploadedFile.new("spec/test_files/layer_1.csv", "text/csv"),
        ],
        metadata: Rack::Test::UploadedFile.new("spec/test_files/invalid_layer_1_metadata.json", "application/json")
      }
      post '/layers/test_layer', payload
      last_response.status.must_equal(422)
      last_response.body.must_equal(
        error_formatting("Layer: 0, missing attributes: file_name")
      )
    end

    it "should correlate the metadata contents to the layers" do
      skip("Add metadata -> layer files correlation ")
    end

    it "should upload the files to event's pending s3 path" do
      skip("Add S3 pending upload!")
    end
  end
end
