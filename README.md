# testdock

Disposable Docker Compose environments for MoonBit tests.
Requires Docker Compose v2 with `up --wait` and a running Docker daemon.

Import `moonbit-community/testdock`, `moonbitlang/async/http` and `tonyfettes/url`
in your `moon.pkg`. The example's `api` service publishes port `3000` and returns
`ok` from `GET /health`:

```mbt nocheck
///|
async test "GET /health" {
  let compose = @testdock.DockerCompose(config="compose.yml")
  defer compose.down() // Remove containers, networks and volumes after the test.
  compose.up(timeout=60_000) // Wait for running/healthy services; milliseconds.

  let api = compose.service("api")
  guard api.get_host_port_ipv4("3000") is Some(port) else {
    fail("api has no published IPv4 port")
  }
  let endpoint = @url.Url::parse("http://localhost/health")
  endpoint.set_hostname(api.get_host())
  endpoint.set_port(port)
  let (_, body) = @http.get(endpoint.href())
  json_inspect(body.text(), content="ok")
}
```

See [example/](example/) for a complete HTTP + PostgreSQL test that creates and
reads a message.

Run it from this repository:

```sh
moon test example/app --target native
# Or use --target wasm.
```

Both services define their own health checks. Each run gets a fresh Compose
project, a random HTTP port and a disposable database volume. The test uses
`defer compose.down()` to clean up when it finishes or an assertion fails.
The initial run downloads the images and MoonBit toolchain needed for the build.

To run all tests:

```sh
moon test --target native
```
