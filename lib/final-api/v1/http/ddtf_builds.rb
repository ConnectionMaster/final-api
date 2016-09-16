module FinalAPI
  module V1
    module Http
      class DDTF_Builds
        include ::Travis::Api::Formats, ::Travis::Api::V1::Helpers::Legacy

        attr_reader :builds

        def initialize(builds, options = {})
          @builds = builds
        end

        def data
          builds.map do |build|
            begin
              DDTF_Build.new(build).test_data
            rescue => error
              {
                'id': build.id,
                'buildId': build.id,
                'name': build.try(&:name) || "Broken build data #{build.id}",
                'build': error.to_s,
                'status': 'broken',
                'started': build.try(&:created_at),
                'isTsd': true,
                'results': [
                  { 'type': 'Failed', 'value': 1.0 }
                 ]
              }
            end
          end
        end

      end
    end
  end
end
