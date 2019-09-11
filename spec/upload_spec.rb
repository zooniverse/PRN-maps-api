# frozen_string_literal: true

require_relative 'spec_helper'

describe 'uploading layer files' do
  include Rack::Test::Methods

  def app
    PrnMaps::Upload
  end

  def files_payload(layers, metadata)
    layer_files = layers.map do |layer|
      Rack::Test::UploadedFile.new(layer, 'text/csv')
    end
    {
      layers: layer_files,
      metadata: Rack::Test::UploadedFile.new(
        metadata,
        'application/json'
      )
    }
  end

  # http://docs.seattlerb.org/minitest/Minitest/Mock.html
  # can't stub the behaviour due to the number
  # of times the method is called, 1 for each layer
  def mock_s3_proxy(metadata, layers, upload_args=[String, Integer, String, Tempfile])
    s3_proxy = Minitest::Mock.new
    s3_proxy.expect(:upload_pending_event_file, File.basename(metadata), upload_args)
    s3_proxy.expect(:next_version, 1, [String])
    s3_proxy.expect(:update_pending_upload_version, 1, [String, Integer])
    PrnMaps::S3Proxy.stub(:new, s3_proxy) do
      layers.map do |l|
        s3_proxy.expect(:upload_pending_event_file, File.basename(l), upload_args)
      end
      yield(s3_proxy)
    end
  end

  describe 'without credentials' do
    it 'should request authentication' do
      post '/layers/test_layer', {}
      last_response.status.must_equal(401)
    end
  end

  describe 'with invalid credentials' do
    it 'should request authentication' do
      authorize 'prn', 'invalid'
      post '/layers/test_layer', {}
      last_response.status.must_equal(401)
    end
  end

  describe 'with valid credentials' do
    before { authorize 'prn', 'api' }

    def error_formatting(*errors)
      { errors: errors }.to_json
    end

    it 'should accept one layer file' do
      layers = ['spec/test_files/layer_1.csv']
      metadata = 'spec/test_files/layer_1_metadata.json'
      payload = files_payload(layers, metadata)
      mock_s3_proxy(metadata, layers) do
        post '/layers/test_layer', payload
      end
      last_response.status.must_equal(201)
      result = { layers: ['layer_1.csv'], metadata: 'layer_1_metadata.json' }
      last_response.body.must_equal(result.to_json)
    end

    it 'should accept one multiple layer files' do
      layers = ['spec/test_files/layer_1.csv', 'spec/test_files/layer_2.csv']
      metadata = 'spec/test_files/layer_1_and_2_metadata.json'
      payload = files_payload(layers, metadata)
      mock_s3_proxy(metadata, layers) do
        post '/layers/test_layer', payload
      end
      last_response.status.must_equal(201)
      result = {
        layers: ['layer_1.csv', 'layer_2.csv'],
        metadata: 'layer_1_and_2_metadata.json'
      }
      last_response.body.must_equal(result.to_json)
    end

    it "should upload the files to event's pending s3 path" do
      upload_layers = ['spec/test_files/layer_1.csv', 'spec/test_files/layer_2.csv']
      metadata = 'spec/test_files/layer_1_and_2_metadata.json'
      payload = files_payload(upload_layers, metadata)
      upload_args = ['test_layer', Integer, String, Tempfile]
      mock_s3_proxy(metadata, upload_layers, upload_args) do |s3_proxy|
        post '/layers/test_layer', payload
        s3_proxy.verify.must_equal(true)
      end
    end

    describe "with invalid file types" do

      it "should reject non csv layers files" do
        layer_files = ['spec/test_files/invalid_layer_type.txt'].map do |layer|
          Rack::Test::UploadedFile.new(layer, 'text/plain')
        end

        post '/layers/test_layer', {
          layers: layer_files,
          metadata: Rack::Test::UploadedFile.new(
            'spec/test_files/invalid_layer_type_metadata.json',
            'application/json'
          )
        }

        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting('Invalid metadata - file type must be text/csv')
        )
      end

      it "should reject non json metadata files" do
        layer_files = ['spec/test_files/layer_1.csv'].map do |layer|
          Rack::Test::UploadedFile.new(layer, 'text/csv')
        end

        post '/layers/test_layer', {
          layers: layer_files,
          metadata: Rack::Test::UploadedFile.new(
            'spec/test_files/invalid_layer_1_metadata.csv',
            'text/csv'
          )
        }

        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting('Invalid metadata - file type must be application/json')
        )
      end
    end

    describe 'missing file paylaods' do
      it 'should reject empty payloads' do
        post '/layers/test_layer', {}
        last_response.status.must_equal(400)
        last_response.body.must_equal(
          error_formatting(
            'You must specify a metadata file',
            'You must specify at least one layer file'
          )
        )
      end

      it 'should reject missing metadata files' do
        payload = {
          layers: [
            Rack::Test::UploadedFile.new(
              'spec/test_files/layer_1.csv',
              'text/csv'
            )
          ]
        }
        post '/layers/test_layer', payload
        last_response.status.must_equal(400)
        last_response.body.must_equal(
          error_formatting('You must specify a metadata file')
        )
      end

      it 'should reject missing layer files' do
        payload = {
          metadata: Rack::Test::UploadedFile.new(
            'spec/test_files/layer_1_metadata.json',
            'application/json'
          )
        }
        post '/layers/test_layer', payload
        last_response.status.must_equal(400)
        last_response.body.must_equal(
          error_formatting('You must specify at least one layer file')
        )
      end
    end

    describe 'when metadata upload is invalid' do
      it 'should ensure the metadata file is appropriately named' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/incorrectly_named_meta_data.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)

        last_response.body.must_equal(
          error_formatting('Invalid metadata - file name must contain metadata')
        )
      end

      it 'should have a top level AOI key' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/missing_aoi_metadata.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting(
            'Invalid metadata - supply an AOI attribute value that describes the layer data geographically (Area Of Interest)'
          )
        )
      end

      it 'should have a top level created_at key' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/missing_created_at_metadata.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting(
            'Invalid metadata - supply a created_at attribute value that describes the upload creation time'
          )
        )
      end

      it 'should respond with useful schema errors' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/invalid_schema_metadata.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting(
            'Invalid metadata - Layer: 0 missing attributes: file_name,description,legend'
          )
        )
      end

      it 'should handle an invalid json file' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/invalid_layer_1_metadata.csv'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting('Invalid metadata - please lint your JSON file')
        )
      end

      it 'should ensure the metadata file describes the layers' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/invalid_layer_metadata.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting(
            'Invalid metadata - ' \
            'Layer: 0 lists missing layer file: incorret_layer.csv'
          )
        )
      end

      it 'should ensure the metadata file describes only known layers' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/unknown_layers_metadata.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting(
            'Invalid metadata - number of entries does not match the number of uploaded files'
          )
        )
      end

      it 'should ensure the metadata file uniquely describes the layers' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv', 'spec/test_files/layer_1.csv'],
          'spec/test_files/invalid_layers_metadata.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)

        last_response.body.must_equal(
          error_formatting('Invalid metadata - file contains non unique entries')
        )
      end
    end
  end
end
