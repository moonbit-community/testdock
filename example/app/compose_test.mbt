///|
async test "write and read PostgreSQL data through HTTP" {
  let compose = @testdock.DockerCompose(config="compose.yml", force_build=true)
  defer compose.down()
  compose.up(timeout=600_000)

  let api = compose.service("api")
  guard api.get_host_port_ipv4("3000") is Some(port) else {
    fail("the HTTP service has no published IPv4 port")
  }
  let endpoint = @url.Url::parse("http://localhost/")
  endpoint.set_hostname(api.get_host())
  endpoint.set_port(port)
  endpoint.set_pathname("/messages")

  @async.with_timeout(10_000, () => {
    // Each run starts with an empty database.
    let (initial, initial_body) = @http.get(endpoint.href())
    json_inspect(initial, content={
      "code": 200,
      "reason": "OK",
      "headers": {
        "content-type": "application/json",
        "Transfer-Encoding": "chunked",
      },
      "cookies": [],
    })
    json_inspect(initial_body.json(), content=[])

    // The HTTP API inserts a row into PostgreSQL and returns its generated ID.
    let message : Json = { "body": "hello from testdock" }
    let (created, created_body) = @http.post(endpoint.href(), message, headers={
      "Content-Type": "application/json",
    })
    json_inspect(created, content={
      "code": 201,
      "reason": "Created",
      "headers": {
        "content-type": "application/json",
        "Transfer-Encoding": "chunked",
      },
      "cookies": [],
    })
    json_inspect(created_body.json(), content={
      "id": 1,
      "body": "hello from testdock",
    })

    // A separate request reads the committed row back from the database.
    let (fetched, fetched_body) = @http.get(endpoint.href())
    json_inspect(fetched, content={
      "code": 200,
      "reason": "OK",
      "headers": {
        "content-type": "application/json",
        "Transfer-Encoding": "chunked",
      },
      "cookies": [],
    })
    json_inspect(fetched_body.json(), content=[
      { "id": 1, "body": "hello from testdock" },
    ])
  })
}
