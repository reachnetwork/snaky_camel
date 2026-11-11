module SnakyCamel
  require 'snaky_camel/exception'

  # Rack 3 / Rails 8.1: Rails no longer reads request parameters from the
  # hashes returned by Rack::Request#GET / #POST — it builds them lazily from
  # the parsed pair lists in the env. Mutating the GET/POST hashes alone is
  # therefore not enough, so keep the pair lists in sync as well.
  PAIR_ENV_KEYS = [
    'rack.request.form_pairs',
    'rack.request.query_pairs'
  ].freeze

  class Middleware
    def initialize(app)
      @app = app
    end

    # Errors Rack raises when the request body cannot be parsed as a form.
    # EmptyContentError does not exist on Rack < 2.2, hence the guard.
    PARSE_ERRORS = [
      defined?(Rack::Multipart::EmptyContentError) ? Rack::Multipart::EmptyContentError : nil,
      EOFError
    ].compact.freeze

    def call(env)
      # Transforming request
      request = Rack::Request.new(env)

      request.GET.deep_transform_keys!{ |k| k.is_a?(String) ? k.underscore : k }
      # request.POST forces a full body parse. Bot traffic sends GETs with a
      # multipart Content-Type and a truncated/empty body (aiohttp CVE
      # scanners), and Rack raises EOFError / Rack::Multipart::EmptyContentError
      # out of the middleware instead of returning a 4xx (ou HB 132640981).
      # There is nothing to transform in a body we cannot parse: skip it.
      begin
        request.POST.deep_transform_keys!{ |k| k.is_a?(String) ? k.underscore : k }
      rescue *PARSE_ERRORS
        # fall through: pass the request on untransformed
      end

      sync_rack3_pair_lists(env)

      # Transforming response
      @app.call(env).tap do |status, headers, response|
        if headers['Content-Type'] =~ /application\/json/
          response.each do |res|
            begin
              new_response = JSON.parse(res)
            rescue JSON::ParserError => e
              message = e.to_s.gsub(/^\d+:\s/, '') # trim numeric code at the beginning of string
              raise Exception::BadResponseFormat.new(message)
            end
            if new_response.is_a?(Array)
              new_response.map!{ |h| h.deep_transform_keys!{ |k| k.include?('-') ? k : k.camelize(:lower) } }
            else
              new_response.deep_transform_keys!{ |k| k.include?('-') ? k : k.camelize(:lower) }
            end
            res.replace(new_response.to_json)
          end
        end
      end
    end

    private

    def sync_rack3_pair_lists(env)
      PAIR_ENV_KEYS.each do |key|
        pairs = env[key]
        next unless pairs.is_a?(Array)

        env[key] = pairs.map do |pair|
          [pair.first.is_a?(String) ? pair.first.underscore : pair.first, pair.last]
        end
      end
    end
  end
end
