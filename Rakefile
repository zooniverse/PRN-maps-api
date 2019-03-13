# frozen_string_literal: true

require 'rollbar/rake_tasks'
require_relative 'prn_maps/config'

task :environment do
  Rollbar.configure do |config|
    config.access_token = PrnMaps::Config.rollbar_token
  end
end
