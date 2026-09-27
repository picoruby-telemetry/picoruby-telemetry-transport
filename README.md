# PicoTelemetry transport

TCP and HTTP(S) adapters for PicoRuby and FemtoRuby. Development version.
Add this directory to a PicoRuby build with `conf.gem gemdir:`. Load it with
`require 'telemetry'` followed by `require 'telemetry-transport'`. TLS
verification is enabled by default. Timeouts and certificate handling depend
on the selected PicoRuby build and its socket / HTTP gems.
The host FemtoRuby socket port rejects bounded HTTP requests. The transport
reports that configuration error instead of retrying it forever.

Host tests: `ruby test/run.rb` with a sibling PicoRuby checkout.

## 日本語

PicoTelemetry の TCP / HTTP(S) 通信層です。開発版です。
`conf.gem gemdir:` でビルドに追加します。通信タイムアウトと TLS の検証は、
PicoRuby 本体のソケット・HTTP 実装を利用します。
組み込み後は `require 'telemetry'`、`require 'telemetry-transport'` の順に読み込みます。
ホスト版 FemtoRuby の socket port は応答サイズ制限付き HTTP に対応していません。

MIT License.
