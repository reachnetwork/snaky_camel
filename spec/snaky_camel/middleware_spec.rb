require 'spec_helper'

describe SnakyCamel::Middleware do
  describe 'converting request' do
    context 'when it is a GET request' do
      it 'snake-cases it' do
        params_hash = nil
        app = -> (env) do
          params_hash = env['rack.request.query_hash']
          [200, {}, ["{}"]]
        end
        env = Rack::MockRequest.env_for('/', method: :get, params: { pageName: 'ACxDC' })
        described_class.new(app).call(env)
        expect(params_hash['page_name']).not_to be_nil
      end
    end

    context 'when it is a POST request' do
      it 'snake-cases it' do
        params_hash = nil
        app = -> (env) do
          params_hash = env['rack.request.form_hash']
          [200, {}, ["{}"]]
        end
        env = Rack::MockRequest.env_for('/', method: :post, params: { pageName: 'ACxDC' })
        described_class.new(app).call(env)
        expect(params_hash['page_name']).not_to be_nil
      end
    end

    # Regression: Rails 8.1 / Rack 3 builds ActionDispatch::Request#params from
    # rack.request.form_pairs instead of the form_hash mutated above, so
    # camelCase POST bodies reached controllers untransformed.
    context 'when it is a POST request under Rack 3' do
      it 'snake-cases rack.request.form_pairs' do
        env = Rack::MockRequest.env_for('/', method: :post,
          'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
          input: 'collegeId=purdue-global&collegeName=Purdue+Global')
        described_class.new(->(e) { [200, {}, ['{}']] }).call(env)

        pairs = env['rack.request.form_pairs']
        skip 'Rack 2 has no rack.request.form_pairs (params come from form_hash)' unless pairs
        expect(pairs).to contain_exactly(
          ['college_id', 'purdue-global'], ['college_name', 'Purdue Global'])
      end
    end

    context 'when pair lists are absent' do
      it 'does not raise' do
        env = Rack::MockRequest.env_for('/', method: :post,
          'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
          input: 'collegeId=purdue-global')
        env.delete('rack.request.form_pairs')
        expect { described_class.new(->(e) { [200, {}, ['{}']] }).call(env) }.not_to raise_error
      end
    end
  end

  describe 'converting response' do
    context 'when the JSON is correct' do
      it 'camel-cases response if top level object is a Hash' do
        app = -> (env) do
          [200, {'Content-Type' => 'application/json'}, ['{"post":{"page_name":"ACxDC"}}']]
        end
        request = Rack::MockRequest.new(described_class.new(app))
        response = request.get('/').body
        expect(JSON.parse(response)['post']['pageName']).not_to be_nil
      end

      it 'camel-cases response if top level object is an Array' do
        app = -> (env) do
          [200, {'Content-Type' => 'application/json'}, ['[{"post":{"page_name":"ACxDC"}}]']]
        end
        request = Rack::MockRequest.new(described_class.new(app))
        response = request.get('/').body
        expect(JSON.parse(response).first['post']['pageName']).not_to be_nil
      end
    end

    context 'when the response is not of Content-Type json' do
      it 'does nothing' do
        app = -> (env) do
          [200, {'Content-Type' => 'text/html'}, ['{"post":{"page_name":"ACxDC"}}']]
        end
        request = Rack::MockRequest.new(described_class.new(app))
        response = request.get('/').body
        expect(JSON.parse(response)['post']['pageName']).to be_nil
      end
    end

    context 'when response is invalid JSON' do
      it 'throws a BadResponseFormat exception' do
        app = -> (env) do
          [200, {'Content-Type' => 'application/json'}, ['{"post":{"page_name":"ACxDC"}']]
        end
        request = Rack::MockRequest.new(described_class.new(app))
        expect{ request.get('/') }.to raise_error(SnakyCamel::Exception::BadResponseFormat)
      end
    end
  end
end

