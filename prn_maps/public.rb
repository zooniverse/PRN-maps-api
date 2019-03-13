# frozen_string_literal: true

require_relative 'api'

module PrnMaps
  class Public < Api
    options '/events' do
      options_req
    end

    get '/events' do
      json(s3_proxy.events)
    end

    options '/manifests/:event_name' do
      options_req
    end

    get '/manifests/:event_name' do
      json(s3_proxy.event_manifest(params[:event_name]))
    end

    options '/layers/:event_name' do
      options_req
    end

    get '/layers/:event_name' do
      json(s3_proxy.approved_event_layers(params[:event_name]))
    end

    get '/*' do
      json(health: 'ok', version: self.class.version, commit_id: commit_id)
    end

    private

    def commit_id
      @commit_id ||= File.read('public/commit_id.txt').strip
    end
  end
end