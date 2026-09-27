class TransportTest < Picotest::Test
  def test_statuses_and_split_read
    assert(Object.const_defined?(:PicoTelemetry))
    return unless Object.const_defined?(:PicoTelemetry)
    assert_equal(:ok, PicoTelemetry::Transport.classify_http_status(200))
    assert_equal(:drop, PicoTelemetry::Transport.classify_http_status(400))
    assert_equal(:fatal, PicoTelemetry::Transport.classify_http_status(403))
    assert_equal(:retry, PicoTelemetry::Transport.classify_http_status(429))
    tcp = PicoTelemetry::Transport::TCP.new(host: 'localhost', port: 1)
    assert_equal('abc', tcp.read_exact(SplitIO.new('abc'), 3))
  end

  class SplitIO
    def initialize(text); @text = text; end
    def read(n)
      return nil if @text.empty?
      byte = @text.byteslice(0, 1)
      @text = @text.byteslice(1, @text.bytesize - 1)
      byte
    end
  end
end
