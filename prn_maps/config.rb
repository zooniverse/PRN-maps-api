# frozen_string_literal: true

module PrnMaps
  class Config
    ERROR_REPORTING_ENVS = %w[staging production].freeze

    def self.enable_error_reports?
      ERROR_REPORTING_ENVS.include?(environment)
    end

    def self.environment
      ENV.fetch('RACK_ENV') || 'development'
    end

    def self.local?
      environment == 'development'
    end

    def self.rollbar_token
      ENV['ROLLBAR_ACCESS_TOKEN']
    end
  end
end
