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

  describe 'without credentials' do
    it 'should request authentication' do
      post '/layers/test_layer', {}
      last_response.status.must_equal(401)
    end
  end

  describe 'with credentials' do
    before { authorize 'prn', 'api' }

    def error_formatting(*errors)
      { errors: errors }.to_json
    end

    it 'should accept one layer file' do
      payload = files_payload(
        ['spec/test_files/layer_1.csv'],
        'spec/test_files/layer_1_metadata.json'
      )
      post '/layers/test_layer', payload
      last_response.status.must_equal(201)
      result = { layers: ['layer_1.csv'], metadata: 'layer_1_metadata.json' }
      last_response.body.must_equal(result.to_json)
    end

    it 'should accept one multiple layer files' do
      payload = files_payload(
        ['spec/test_files/layer_1.csv', 'spec/test_files/layer_2.csv'],
        'spec/test_files/layer_1_and_2_metadata.json'
      )
      post '/layers/test_layer', payload
      last_response.status.must_equal(201)
      result = {
        layers: ['layer_1.csv', 'layer_2.csv'],
        metadata: 'layer_1_and_2_metadata.json'
      }
      last_response.body.must_equal(result.to_json)
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

    describe 'when metadata upload is an invalid' do
      it 'should respond with useful schema errors' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/invalid_schema_metadata.json'
        )
        post '/layers/test_layer', payload
        last_response.status.must_equal(422)
        last_response.body.must_equal(
          error_formatting(
            'Invalid metadata - Layer: 0 missing attributes: file_name'
          )
        )
      end

      it 'should handle an invalid json file' do
        payload = files_payload(
          ['spec/test_files/layer_1.csv'],
          'spec/test_files/layer_1.csv'
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

    it "should upload the files to event's pending s3 path" do
      # all files should have the
      skip('Add S3 pending upload!')
    end
  end
end
