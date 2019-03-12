require 'minitest/autorun'
require_relative 'test_helper'

include Rack::Test::Methods

def app
  PrnMaps::Upload
end

describe "uploading layer files" do
  it "should request authentication" do
    get '/'
    last_response.body.must_include 'Welcome to my page!'
  end
end
