# frozen_string_literal: true

require_relative 'api'
require_relative 'options_basic_auth'

module PrnMaps
  class Pending < Api
    use OptionsBasicAuth, 'Protected Area' do |username, password|
      username == ENV.fetch('BASIC_AUTH_USERNAME', 'prn') &&
        password == ENV.fetch('BASIC_AUTH_PASSWORD', 'api')
    end

    options '/layers/:event_name' do
      options_req
    end

    get '/layers/:event_name' do
      json(s3_proxy.pending_event_layers(params[:event_name]))
    end

    options '/layers/:event_name/approve' do
      options_req
    end

    # This moves all the pending layers to approve event bucket path
    post '/layers/:event_name/approve/:version' do
      json(
        s3_proxy.approve_pending_event_layers(
          params[:event_name],
          params[:version]
        )
      )
    end
  end
end
