# testdock

Disposable Docker Compose environments for MoonBit tests.
Requires Docker Compose v2 with `up --wait` and a running Docker daemon.

The [example/](example/) project combines a MoonBit HTTP service and PostgreSQL.
The service uses `moonback` for HTTP and `moonbit-community/postgres` for queries.
Its `app/` package contains the API, database initialization, and Compose test;
`main/` is the entry point. The example uses the local testdock library through
`moon.work`, with its Dockerfile and Compose file alongside both packages.
The test builds the service from its Dockerfile, starts both services, and
snapshots the HTTP responses when creating and reading a message.

Run it from this repository:

```sh
moon test example/app --target native
# Or use --target wasm.
```

Both services define their own health checks. Each run gets a fresh Compose
project, a random HTTP port and a disposable database volume. The test uses
`defer compose.down()` to clean up when it finishes or an assertion fails.
The initial run downloads the images and MoonBit toolchain needed for the build.

To also run the library's Docker integration tests:

```sh
TESTDOCK_DOCKER_TESTS=1 moon test --target native
```
