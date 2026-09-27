# PicoTelemetry transport

TCP and HTTP(S) adapters for PicoRuby and FemtoRuby. Development version.
Add this directory to a PicoRuby build with `conf.gem gemdir:`. Load it with
`require 'telemetry'` followed by `require 'telemetry-transport'`. TLS
verification is enabled by default. Timeouts and certificate handling depend
on the selected PicoRuby build and its socket / HTTP gems.
The host FemtoRuby socket port rejects bounded HTTP requests. The transport
reports that configuration error instead of retrying it forever.

Host tests: `ruby test/run.rb` with a sibling PicoRuby checkout.

MIT License.
