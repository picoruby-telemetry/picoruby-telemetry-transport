MRuby::Gem::Specification.new('picoruby-telemetry-transport') do |spec|
  spec.license = 'MIT'
  spec.author = 'PicoTelemetry contributors'
  spec.summary = 'TCP and HTTP transports for PicoTelemetry'
  spec.version = '0.1.0.dev'
  spec.add_dependency 'picoruby-socket'
  spec.add_dependency 'picoruby-net-http'
end
