# frozen_string_literal: true

require_relative 'spec_helper'

describe 'approving pending layer files' do
  include Rack::Test::Methods

  def app
    PrnMaps::Pending
  end

  # http://docs.seattlerb.org/minitest/Minitest/Mock.html
  # can't stub the behaviour due to the number
  # of times the method is called, 1 for each layer
  def mock_s3_proxy(event_name, version)
    s3_proxy = Minitest::Mock.new
    approved_response_obj = [{name: "layer_name", url: "url"}]
    s3_proxy.expect(
      :approve_pending_event_layers,
      approved_response_obj,
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
      post "/layers/#{event_name}/approve/#{version_num}", {}
      last_response.status.must_equal(401)
    end
  end

  describe 'with invalid credentials' do
    it 'should request authentication' do
      authorize 'prn', 'invalid'
      post "/layers/#{event_name}/approve/#{version_num}", {}
      last_response.status.must_equal(401)
    end
  end

  describe 'with valid credentials' do
    before { authorize 'prn', 'api' }

    it "should approved the layers files to event's approved s3 path" do
      mock_s3_proxy(event_name, version_num) do |s3_proxy|
        post "/layers/#{event_name}/approve/#{version_num}", {}
        s3_proxy.verify.must_equal(true)
      end
    end
  end
end
