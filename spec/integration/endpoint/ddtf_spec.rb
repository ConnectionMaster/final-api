require 'final-api/app'

describe 'DDTF' do
  include Rack::Test::Methods

  def app
    FinalAPI::App
  end

  let(:post_payload) { { file: { source: {} }.to_json }.to_json }
  let!(:user) { Factory(:user) }

  let(:headers) do
    {
      'HTTP_ACCEPT' => 'application/json',
      'HTTP_USERNAME' => user.login,
      'HTTP_NAME' => user.login,
      'HTTP_AUTHENTICATIONTOKEN' => 'secret'
    }
  end

  before do
    allow_any_instance_of(TsdUtils::EnqueueData).to receive(:build_all)
    allow_any_instance_of(TsdUtils::EnqueueData).to receive(:tsd) { { 'source' => {} } }
    allow_any_instance_of(Travis::Amqp::Publisher).to receive(:publish)

    allow(FinalAPI.config).to receive_message_chain(:tsd_utils, :clusters) { {} }
    allow(FinalAPI.config.ddtf).to receive(:email_domain) { 'mail.com' }
  end

  context 'POST /ddtf/builds' do
    let(:repository) { Factory(:repository) }
    let(:config) do
      {
        language: 'tsd',
        env: ['MACHINE=x764 PART=1', 'MACHINE=8x64 PART=1'],
        os: 'windows'
      }
    end
    let(:payload) do
      {
        user_id: user.id,
        repository_id: repository.id,
        config: config
      }
    end

    it "always returns pseudo-build with id: 1" do
      post '/ddtf/builds', payload, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response['id']).to eq(1)
    end
  end

  context 'POST /ddtf/builds/:build_id/jobs' do
    let(:build) { Factory(:build) }
    let(:repository) { Factory(:repository) }
    let(:config) do
      {
        language: 'tsd',
        env: 'MACHINE=x764 PART=1',
        os: 'windows'
      }
    end
    it "creates job and returns its json" do
      post "/ddtf/builds/#{build.id}/jobs", { config: config }, headers
      expect(last_response.status).to eq(200)
      result = MultiJson.load(last_response.body)
      expect(result['config']['env']).to eq('MACHINE=x764 PART=1')
      expect(result['config']['os']).to eq('windows')
    end

    it "set job to 'received' state" do
      post "/ddtf/builds/#{build.id}/jobs", { config: config }, headers
      expect(last_response.status).to eq(200)
      result = MultiJson.load(last_response.body)
      expect(result['state']).to eq('received')
    end

    it 'returns 404 when build does not exists' do
      post '/ddtf/builds/1000/jobs', {}, headers
      expect(last_response.status).to eq(404)
    end
  end

  context 'GET /ddtf/tests' do
    let(:fake_config) do
      double('fakeconf',default_limit: 10, default_offset: 0, max_limit: 1000)
    end

    let(:fake_config_offset) do
      double('fakeconf',default_limit: 100, default_offset: 10, max_limit: 1000)
    end

    let(:fake_config_limit) do
      double('fakeconf',default_limit: 2, default_offset: 10, max_limit: 10)
    end

    it 'returns last 20 builds by default' do
      1.upto(22) do |idx|
        Factory(:build, name: idx.to_s)
      end
      get '/ddtf/tests', {}, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.last['name']).to eq '3'
      expect(response.first['name']).to eq '22'
      expect(response.size).to eq 20
    end

    it 'returns last builds, number of elements is configurable via config' do
      1.upto(22) do |idx|
        Factory(:build, name: idx.to_s)
      end
      allow(FinalAPI.config.api).to receive(:tests).and_return(fake_config)

      get '/ddtf/tests', {}, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.size).to eq 10
    end

    it 'returns last builds, elements offset is configurable via config' do
      1.upto(22) do |idx|
        Factory(:build, name: idx.to_s)
      end

      allow(FinalAPI.config.api).to receive(:tests).and_return(fake_config_offset)

      get '/ddtf/tests', {}, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.size).to eq 12
      names = response.map {|r| r["name"]}
      expect(names).to include(*(1..12).to_a.map(&:to_s))
    end

    it 'returns last builds with statuscode 200 in case the output is incomplete '\
       'if limit in request is set unproperly' do
      1.upto(22) do |idx|
        Factory(:build, name: idx.to_s)
      end

      allow(FinalAPI.config.api).to receive(:tests).and_return(fake_config_limit)

      get '/ddtf/tests', { limit: 20000 }, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.size).to eq 10
    end

    it 'limits results by limit param' do
      1.upto(3) do |idx|
        Factory(:build, config: { name: idx.to_s })
      end
      get '/ddtf/tests', { limit: 2 }, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.size).to eq 2
    end

    it 'paginates by limit and offset params' do
      1.upto(5) do |idx|
        Factory(:build, name: idx.to_s)
      end
      get '/ddtf/tests', { limit: 2, offset: 2 }, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.last['name']).to eq '2'
      expect(response.first['name']).to eq '3'
      expect(response.size).to eq 2
    end

    describe 'filter by "q" param' do
      let(:user_nomae) { Factory(:user, name: 'noname') }
      let(:user) { Factory(:user, name: 'franta.lopata') }
      let!(:builds) do
        (1..20).map do |idx|
          Factory(:build, name: idx.to_s, owner: user_nomae)
        end
      end
      let!(:user_build) do
        Factory(:build, name: 'user_build', owner: user, stopped_by: user)
      end

      it 'search by \'nam\' and \'name\' keyword with contains operator' do
        get '/ddtf/tests', { q: 'nam: 2' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 3 # '2', '12', '20'

        get '/ddtf/tests', { q: 'name: 2' }, headers
        expect(last_response.status).to eq(200)
        response2 = MultiJson.load(last_response.body)
        expect(response2).to eq response1
      end

      it 'search by \'nam\' and \'name\' keyword with = operator' do
        get '/ddtf/tests', { q: 'nam= 2' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 1

        get '/ddtf/tests', { q: 'name= 2' }, headers
        expect(last_response.status).to eq(200)
        response2 = MultiJson.load(last_response.body)
        expect(response2).to eq response1
      end

      it 'search by \'startedBy\' keyword with = operator' do
        get '/ddtf/tests', { q: 'startedBy = franta.lopata' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 1
      end

      it 'search by \'stoppedBy\' keyword with : operator' do
        get '/ddtf/tests', { q: 'stoppedBy : nta.lopa' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 1
      end


      it 'searches by combination of keywords' do
        b = builds.last
        get '/ddtf/tests',
            { q: "name : #{b.name} id = \"#{b.id}\"" },
            headers
        response = MultiJson.load(last_response.body)
        expect(response.size).to eq 1
        expect(response.first['id']).to eq b.id
      end

      context 'when invalid query given' do
        let(:invalid_expression) { 'craaaaaazy' }
        before do
          b = builds.last
          get '/ddtf/tests',
              { q: "name : #{b.name} #{invalid_expression}" },
              headers
        end

        it 'returns 400' do
          expect(last_response.status).to eq 400
        end

        it 'says what is wrong' do
          response = MultiJson.load(last_response.body)
          expect(response['message']).to include(invalid_expression)
        end
      end
    end

    it 'returns proper structure' do
      build = Factory(:build,
                      config: {
                        name: 'TSD name',
                        description: 'myDescription'
                      },
                      name: 'TSD name'
                     )

      get '/ddtf/tests', {}, headers
      response = MultiJson.load(last_response.body).first
      expected_response = {
        'id' => build.id,
        'name' => 'TSD name',
        'description' => 'myDescription',
        'branch' => nil,
        'build' => nil,
        'status' => 'Finished',
        'strategy' => nil,
        'email' => nil,
        'startedBy' => 'Sven Fuchs',
        'stopped' => nil,
        'stoppedBy' => nil,
        'isTsd' => true,
        'checkpoints' => false,
        'buildSignal' => false,
        'scenarioScript' => false,
        'executionLogs' => [],
        'stashTSD' => nil,
        'runtimeConfig' => [],
        'parts' => [{ 'name' => nil, 'result' => 'Created' }],
        'tags' => [],
        'result' => 'passed',
        'results' => [{ 'type' => 'NotSet', 'value' => 1.0 }],
        'buildId' => build.id
      }
      expect(response).to include(expected_response)
    end

    context 'when test data invalid' do
      before :each do
        expect_any_instance_of(FinalAPI::V1::Http::DDTF_Build).to receive(:test_data) do
          raise 'Some test data are invalid'
        end
      end

      it 'handles request with reduced json response' do
        build_name = 'custom name'

        Factory(:build, name: build_name)

        get '/ddtf/tests', {}, headers

        expect(last_response.status).to eq(200)
        expect_name(build_name)
      end

      it 'returns custom title with build id if name is missing' do
        Factory(:build, id: 666, name: nil)

        get '/ddtf/tests', {}, headers

        expect(last_response.status).to eq(200)
        expect_name('Broken build data 666')
      end

      def expect_name(name)
        response = MultiJson.load(last_response.body)
        expect(response.first['name']).to eq name
      end
    end
  end

  describe 'GET /ddtf/tests/:id' do
    before do
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:clusters) { ['cluster'] }
    end

    context 'when build exists' do
      build_id = nil
      before do
        post '/ddtf/tests', post_payload, headers
        build_id = MultiJson.load(last_response.body)['id'].to_s
      end

      it 'returns 200' do
        get "/ddtf/tests/#{build_id}", headers
        expect(last_response.status).to eq(200)
      end
    end

    context 'when build does not exist' do
      it 'returns 404' do
        get '/ddtf/tests/foo', headers
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'GET /ddtf/tests/new' do
    before do
      allow(TsdUtils::ContentFetcher).to receive(:load) do
        {
          'source': { 'GIT' => 'some link' }
        }.to_json
      end
    end

    it 'returns 400 when missing stashTsdLink parameter' do
      get '/ddtf/tests/new'
      expect(last_response.status).to eq(400)
    end

    it 'returns 200 and new test payload' do
      get '/ddtf/tests/new?stashTSDLink=link'
      result = JSON.parse(last_response.body)
      expect(last_response.status).to eq(200)

      expect(result['packageFrom']).to eq 'GIT'
      expect(result['stashTSD']).to eq 'link'
      expect(result['package']).to eq 'some link'
    end

    context 'when Content fetcher throws error' do
      before do
        allow(TsdUtils::ContentFetcher).to receive(:load) { raise ArgumentError }
      end

      it 'returns 404' do
        get '/ddtf/tests/new?stashTSDLink=unexisting_tsd'
        expect(last_response.status).to eq(404)
      end
    end

    context 'when TSD is not valid' do
      before do
        allow(TsdUtils::ContentFetcher).to receive(:load) { 'Not valid tsd' }
      end

      it 'returns 404' do
        get '/ddtf/tests/new?stashTSDLink=not_valid_tsd'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'POST /ddtf/tests/:id/retest' do
    before do
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:clusters) { ['cluster'] }
    end

    let(:build) { Factory(:build) }
    let(:webserver_runtime_config) do
      [{ definition:  'webserver1', value: '1.2.3.4' },
       { definition: 'do_you', value: 'see_me' }]
    end

    it 'omits webserver runtime config fields' do
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:runtime_config) do
        webserver_runtime_config
      end
      post '/ddtf/tests', { runtimeConfigFields: webserver_runtime_config }.to_json, headers
      build_id = MultiJson.load(last_response.body)['id'].to_s
      post "/ddtf/tests/#{build_id}/retest", headers
      response = MultiJson.load(last_response.body)
      expected_runtime_config = [{ 'definition' => 'do_you', 'value' => 'see_me' }]
      expect(response['runtimeConfigFields']).to eq(expected_runtime_config)
    end

    it 'returns test suite definition' do
      post '/ddtf/tests', post_payload, headers
      build_id = MultiJson.load(last_response.body)['id'].to_s
      get '/ddtf/tests/' + build_id, headers
      response = MultiJson.load(last_response.body)
      expect(response['tsdContent']).to eq build['tsdContent']
    end
  end

  context 'GET /ddtf/tests/:id/part' do
    it 'TODO ..write tests here'
  end

  context 'POST /ddtf/tests' do
    context 'data not parsable' do
      before do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:build_all) { raise 'BOOM!' }
      end

      it 'returns status code 422' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(422)
        expect(last_response.body).to include('error')
      end
    end

    context 'data not valid' do
      before :each do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { false }
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:errors) { ['BOOM!'] }
      end

      it 'returns status code 400' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(400)
      end

      it 'returns array of reasons' do
        post '/ddtf/tests', post_payload, headers
        expect(JSON.parse(last_response.body)).to be_an_instance_of(Array)
      end
    end

    context 'name not specified in headers' do
      before :each do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
      end

      it 'returns status code 422' do
        post '/ddtf/tests', post_payload, {}
        expect(last_response.status).to eq(422)
      end
    end

    context 'build id not retrieved' do
      before do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:get_new_build_params) { {} }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:create_build)

        allow(FinalAPI.config.ddtf).to receive(:email_domain) { 'mail.com' }
      end

      it 'returns status code 422' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(422)
      end

      it 'returns detailed description' do
        post '/ddtf/tests', post_payload, headers
        expect(JSON.parse(last_response.body)).to include('message' => 'Could not create new build')
      end
    end

    context 'request succeeds' do
      let(:build) { Factory(:build) }

      before do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:clusters) { ['cluster'] }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:get_new_build_params) { {} }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:create_build) { build }

        allow(FinalAPI.config).to receive(:allowed_origin) { '*' }

        allow(TsdUtils::EnqueueData).to receive(:prepare_xml)
      end

      it 'returns status code 200' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(200)
      end

      it 'returns expected data' do
        post '/ddtf/tests', post_payload, headers
        expect(JSON.parse(last_response.body)).to include(
          'id', 'name', 'build', 'result', 'results', 'started')
      end

      it 'adds build id' do
        expect_any_instance_of(Travis::Amqp::Publisher).to receive(:publish)
          .with(hash_including(:enqueue_data => a_string_matching("<BuildId>#{build.id}</BuildId>")))

        post '/ddtf/tests', post_payload, headers
      end
    end
  end

  describe 'PUT /ddtf/tests/:id/stop' do
    let(:build) { Factory(:build, state: 'created') }

    it 'set state in DB' do
      put "/ddtf/tests/#{build.id}/stop"
      expect(last_response.status).to eq(200)
      build.reload
      expect(build.state).to eq 'canceled'
    end
  end
end
