# frozen_string_literal: true

require_relative 'spec_helper'

describe 'approving pending layer files' do
  include Rack::Test::Methods

  def app
    PrnMaps::Revert
  end

  def mock_s3_proxy(event_name, version)
    s3_proxy = Minitest::Mock.new
    revert_approved_response_obj = [{name: "layer_name", url: "url"}]
    s3_proxy.expect(
      :revert_approved_event_layers,
      revert_approved_response_obj,
      [event_name, version]
    )
    PrnMaps::S3Proxy.stub(:new, s3_proxy) do
      yield(s3_proxy)
    end
  end

  def version_num
    '1'
  end

  def event_name
    'test_event'
  end

  describe 'without credentials' do
    it 'should request authentication' do
      post "/layers/#{event_name}/revert/#{version_num}", {}
      expect(last_response.status).must_equal(401)
    end
  end

  describe 'with invalid credentials' do
    it 'should request authentication' do
      authorize 'prn', 'invalid'
      post "/layers/#{event_name}/revert/#{version_num}", {}
      expect(last_response.status).must_equal(401)
    end
  end

  describe 'with valid credentials' do
    before { authorize 'prn', 'api' }

    it "should move the approved layer files to event's pending s3 path" do
      mock_s3_proxy(event_name, version_num) do |s3_proxy|
        post "/layers/#{event_name}/revert/#{version_num}", {}
        expect(s3_proxy.verify).must_equal(true)
      end
    end
  end
end
