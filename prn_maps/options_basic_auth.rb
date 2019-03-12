module PrnMaps
  class OptionsBasicAuth < Rack::Auth::Basic
    def call(env)
      request = Rack::Request.new(env)
      if request.options?
        @app.call(env)
      else
        super # perform auth
      end
    end
  end
end
