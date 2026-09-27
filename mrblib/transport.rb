class PicoTelemetry
  module Transport
    class Error < StandardError; end
    class ConnectionError < Error; end
    class TimeoutError < Error; end
    class ProtocolError < Error; end
    class UnsupportedError < Error; end

    class Response
      attr_reader :status, :body, :headers
      def initialize(status, body, headers)
        @status, @body, @headers = status, body, headers
      end
    end

    def self.classify_http_status(status)
      return :ok if status >= 200 && status < 300
      return :retry if status == 408 || status == 429 || status >= 500
      return :fatal if status == 401 || status == 403
      :drop
    end

    def self.now_us
      if Object.const_defined?(:Machine) && Machine.respond_to?(:uptime_us)
        Machine.uptime_us
      elsif Object.const_defined?(:Process)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000_000).to_i
      else
        ClockSource.now_us
      end
    end

    class ClockSource
      def self.now_us
        now = Time.now
        @start_sec ||= now.to_i
        (now.to_i - @start_sec) * 1_000_000 + now.usec
      end
    end

    class TCP
      def initialize(host:, port:, connect_timeout_ms: 3000, io_timeout_ms: 5000)
        @host, @port = host, port
        @connect_timeout_ms, @io_timeout_ms = connect_timeout_ms, io_timeout_ms
      end

      def exchange(request)
        require 'socket' unless Object.const_defined?(:TCPSocket)
        deadline = Transport.now_us + @connect_timeout_ms * 1000
        socket = if TCPSocket.respond_to?(:__transport_open)
                   TCPSocket.__transport_open(@host, @port, deadline)
                 elsif Object.const_defined?(:Socket) && Socket.respond_to?(:tcp)
                   Socket.tcp(@host, @port, connect_timeout: @connect_timeout_ms / 1000.0)
                 else
                   TCPSocket.new(@host, @port)
                 end
        deadline = Transport.now_us + @io_timeout_ms * 1000
        offset = 0
        size = request.bytesize
        while offset < size
          written = if socket.respond_to?(:__transport_write)
                      socket.__transport_write(request, offset, size - offset, deadline)
                    else
                      socket.write(request.byteslice(offset, size - offset))
                    end
          raise ProtocolError, 'short write' if !written || written <= 0
          offset += written
        end
        # A single framing callback is required because TCP has no message boundary.
        yield socket
      rescue Error
        raise
      rescue StandardError => error
        raise(normalize(error))
      ensure
        socket.close if socket
      end

      def read_exact(io, length)
        raise ProtocolError, 'invalid length' if length < 0
        deadline = Transport.now_us + @io_timeout_ms * 1000
        result = ''
        while result.bytesize < length
          remaining = length - result.bytesize
          part = if io.respond_to?(:__transport_read)
                   io.__transport_read(remaining, deadline)
                 elsif Object.const_defined?(:IO) && io.respond_to?(:to_io)
                   wait = (deadline - Transport.now_us) / 1_000_000.0
                   raise TimeoutError, 'read timeout' if wait <= 0 || !IO.select([io], nil, nil, wait)
                   io.readpartial(remaining)
                 else
                   io.read(remaining)
                 end
          raise ProtocolError, 'unexpected EOF' unless part && part.bytesize > 0
          result << part
          raise TimeoutError, 'read timeout' if Transport.now_us > deadline
        end
        result
      rescue Error
        raise
      rescue StandardError => error
        raise(normalize(error))
      end

      private
      def normalize(error)
        return TimeoutError.new(error.message) if error.message.include?('timeout')
        ConnectionError.new(error.message)
      end
    end

    class HTTP
      def initialize(base_url:, ca_file: nil, verify: true, open_timeout_ms: 5000,
                     read_timeout_ms: 10_000, max_body_bytes: 4096)
        scheme_end = base_url.index('://')
        raise ArgumentError, 'invalid base URL' unless scheme_end
        @scheme = base_url.byteslice(0, scheme_end)
        raise ArgumentError, 'invalid URL scheme' unless @scheme == 'http' || @scheme == 'https'
        authority_start = scheme_end + 3
        path_start = base_url.index('/', authority_start)
        authority = path_start ? base_url.byteslice(authority_start, path_start - authority_start) : base_url.byteslice(authority_start, base_url.bytesize - authority_start)
        host_port = authority.split(':')
        @host = host_port[0]
        raise ArgumentError, 'missing URL host' if !@host || @host.empty?
        @port = (host_port[1] || (@scheme == 'https' ? '443' : '80')).to_i
        @prefix = path_start ? base_url.byteslice(path_start, base_url.bytesize - path_start) : ''
        @ca_file, @verify = ca_file, verify
        @open_timeout_ms, @read_timeout_ms = open_timeout_ms, read_timeout_ms
        @max_body_bytes = max_body_bytes
      end

      def post(path, body, headers = nil)
        request(:post, path, body, headers)
      end

      def get(path, headers = nil)
        request(:get, path, nil, headers)
      end

      def request(method, path, body, headers)
        require 'net/http' unless Object.const_defined?(:Net) && Net.const_defined?(:HTTP)
        client = Net::HTTP.new(@host, @port)
        client.use_ssl = @scheme == 'https'
        client.open_timeout = @open_timeout_ms / 1000.0
        client.read_timeout = @read_timeout_ms / 1000.0
        client.write_timeout = @read_timeout_ms / 1000.0 if client.respond_to?(:write_timeout=)
        client.max_response_body_bytes = @max_body_bytes if client.respond_to?(:max_response_body_bytes=)
        client.ca_file = @ca_file if @ca_file
        unless @verify
          puts('PicoTelemetry: TLS verification disabled') unless self.class.warned?
          self.class.warned!
          if Object.const_defined?(:SSLContext)
            client.verify_mode = SSLContext::VERIFY_NONE
          elsif Object.const_defined?(:OpenSSL)
            client.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
        end
        client.start
        response = method == :post ? client.post(@prefix + path, body, headers) : client.get(@prefix + path, headers)
        text = response.body || ''
        text = text.byteslice(0, @max_body_bytes) if text.bytesize > @max_body_bytes
        Response.new(response.code.to_i, text, response)
      rescue StandardError => error
        message = error.message
        raise UnsupportedError, message if message.include?('unsupported_transport')
        if message.include?('timeout') || error.class.to_s.include?('Timeout')
          raise TimeoutError, message
        end
        raise ConnectionError, message
      ensure
        client.finish if client
      end
    end

    class << HTTP
      def warned?; @warned; end
      def warned!; @warned = true; end
    end

    class Mock
      attr_reader :requests
      def initialize(limit = 16)
        @requests, @responses, @limit = [], [], limit
      end
      def enqueue_response(status, body = '', headers = nil)
        raise ArgumentError, 'response queue full' if @responses.size >= @limit
        @responses << Response.new(status, body, headers)
      end
      def enqueue_error(error)
        raise ArgumentError, 'response queue full' if @responses.size >= @limit
        @responses << error
      end
      def post(path, body, headers = nil)
        capture(:post, path, body, headers)
      end
      def get(path, headers = nil)
        capture(:get, path, nil, headers)
      end
      private
      def capture(method, path, body, headers)
        @requests.shift if @requests.size >= @limit
        @requests << [method, path, body, headers]
        result = @responses.shift || Response.new(200, '{}', nil)
        raise result if result.is_a?(StandardError)
        result
      end
    end
  end
end
