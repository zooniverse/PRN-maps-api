# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
require 'minitest/autorun'
require 'minitest/focus'
require 'rack/test'
require 'pry'

require_relative '../prn_maps/upload.rb'
require_relative '../prn_maps/pending.rb'
require_relative '../prn_maps/revert_approved.rb'
