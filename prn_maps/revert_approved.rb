# frozen_string_literal: true

require_relative 'api'
require_relative 'options_basic_auth'

module PrnMaps
  class RevertApproved < Api
    use OptionsBasicAuth, 'Protected Area' do |username, password|
      username == ENV.fetch('BASIC_AUTH_USERNAME', 'prn') &&
        password == ENV.fetch('BASIC_AUTH_PASSWORD', 'api')
    end

    options '/layers/:event_name/revert_approved/:version' do
      options_req
    end

    # This moves all the event version's approved layers
    # to the versions pending bucket path
    post '/layers/:event_name/revert_approved/:version' do
      [
        201,
        json(
          s3_proxy.revert_approved_event_layers(
            params[:event_name],
            params[:version]
          )
        )
      ]
    end
  end
end
