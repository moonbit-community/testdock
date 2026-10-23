///|
async fn assert_removed(label : String) -> Unit {
  for
    args in [
      ["ps", "--all", "--quiet", "--filter", "label=testdock.fixture=\{label}"],
      ["volume", "ls", "--quiet", "--filter", "label=testdock.fixture=\{label}"],
      [
        "network",
        "ls",
        "--quiet",
        "--filter",
        "label=testdock.fixture=\{label}",
      ],
    ] {
    let (code, output, error) = @process.collect_output("docker", args)
    assert_eq(code, 0, msg=error.text())
    assert_eq(output.text().trim().to_owned(), "")
  }
}

///|
async fn assert_http(container : @testdock.Container) -> Unit {
  guard container.get_host_port_ipv4("80") is Some(port) else {
    fail("missing HTTP port")
  }
  let url = @url.Url::parse("http://localhost/")
  url.set_hostname(container.get_host())
  url.set_port(port)
  let (code, output, error) = @process.collect_output("curl", [
    "--fail",
    "--silent",
    "--show-error",
    "--max-time",
    "5",
    url.href(),
  ])
  assert_eq(code, 0, msg=error.text())
  assert_eq(output.text().trim().to_owned(), "testdock-ready")
}

///|
async test "Docker: local build, env file, init service, HTTP, isolation and cleanup" {
  if @env.get_env_var("TESTDOCK_DOCKER_TESTS") != Some("1") {
    return
  }
  let dir = @fs.tmpdir(prefix="testdock-")
  defer @fs.rmdir(dir, recursive=true)
  let label = "\{@env.now()}"
  let image_name = "testdock-fixture-\{label}:latest"
  defer @process.collect_output("docker", ["image", "rm", image_name]) |> ignore
  let dockerfile =
    #|FROM nginx:alpine
    #|RUN echo testdock-ready > /usr/share/nginx/html/index.html
    #|CMD ["nginx", "-g", "daemon off;"]
  @fs.write_file("\{dir}/Dockerfile", dockerfile)
  @fs.write_file("\{dir}/test.env", "TESTDOCK_IMAGE=\{image_name}\n")
  let config = "\{dir}/compose.yml"
  let yaml =
    $|services:
    $|  init:
    $|    image: alpine:3.22
    $|    command: [sh, -c, "echo ready > /data/ready"]
    $|    volumes: [state:/data]
    $|    labels: {testdock.fixture: "\{label}"}
    $|  api:
    $|    image: ${TESTDOCK_IMAGE:?missing image}
    $|    build: .
    $|    ports: ["80"]
    $|    volumes: [state:/data]
    $|    labels: {testdock.fixture: "\{label}"}
    $|    depends_on:
    $|      init:
    $|        condition: service_completed_successfully
    $|    healthcheck:
    $|      test: [CMD-SHELL, "test -f /data/ready && wget -q -O /dev/null http://127.0.0.1:80/"]
    $|      interval: 1s
    $|      timeout: 1s
    $|      retries: 10
    $|volumes:
    $|  state:
    $|    labels: {testdock.fixture: "\{label}"}
    $|networks:
    $|  default:
    $|    labels: {testdock.fixture: "\{label}"}
  @fs.write_file(config, yaml)
  let first = @testdock.DockerCompose(
    config~,
    env="\{dir}/test.env",
    force_build=true,
  )
  defer first.down()
  let second = @testdock.DockerCompose(config~, env="\{dir}/test.env")
  defer second.down()
  first.up(timeout=120_000)
  let api = first.service("api")
  assert_true(api.id() != "")
  assert_http(api)
  assert_true(first.service("init").id() != "")
  assert_true(api.get_bridge_ip_address() is Some(_))
  assert_eq(api.get_host_port_ipv4("9999"), None)
  assert_true(api.ports().contains("80/tcp"))
  try first.service("missing") catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  } noraise {
    _ => fail("missing service lookup succeeded")
  }
  second.up(timeout=60_000)
  let other = second.service("api")
  assert_true(api.id() != other.id())
  assert_true(api.get_host_port_ipv4("80") != other.get_host_port_ipv4("80"))
  first.down()
  first.down()
  assert_http(other)
  second.down()
  assert_removed(label)

  // An assertion failure still runs the caller's deferred cleanup.
  try
    @async.with_timeout(60_000, () => {
      let compose = @testdock.DockerCompose(config~, env="\{dir}/test.env")
      defer compose.down()
      compose.up()
      assert_eq(1, 2, msg="deliberate assertion failure")
    })
  catch {
    Failure(message) =>
      assert_true(message.contains("deliberate assertion failure"))
    error => raise error
  } noraise {
    _ => fail("expected the assertion to fail")
  }
  assert_removed(label)
}

///|
async test "Docker: unhealthy and timed-out startup remove partial resources" {
  if @env.get_env_var("TESTDOCK_DOCKER_TESTS") != Some("1") {
    return
  }
  for
    (reason, retries, timeout) in [
      ("unhealthy", 1, 30_000),
      ("timeout", 120, 3_000),
    ] {
    let dir = @fs.tmpdir(prefix="testdock-failure-")
    defer @fs.rmdir(dir, recursive=true)
    let label = "\{@env.now()}-\{reason}"
    let config = "\{dir}/compose.yml"
    let yaml =
      $|services:
      $|  worker:
      $|    image: alpine:3.22
      $|    command: [sleep, "300"]
      $|    stop_grace_period: 1s
      $|    volumes: [state:/data]
      $|    labels: {testdock.fixture: "\{label}"}
      $|    healthcheck:
      $|      test: [CMD, "false"]
      $|      interval: 1s
      $|      timeout: 1s
      $|      retries: \{retries}
      $|volumes:
      $|  state:
      $|    labels: {testdock.fixture: "\{label}"}
      $|networks:
      $|  default:
      $|    labels: {testdock.fixture: "\{label}"}
    @fs.write_file(config, yaml)
    let compose = @testdock.DockerCompose(config~)
    defer compose.down()
    try compose.up(timeout~) catch {
      @async.TimeoutError => inspect(reason, content="timeout")
      error if @async.is_being_cancelled() => raise error
      error => {
        inspect(reason, content="unhealthy")
        assert_true(Repr(error).to_string().contains("unhealthy"))
      }
    } noraise {
      _ => fail("unready service unexpectedly started")
    }
    // Assert before calling down: startup itself must have cleaned up.
    assert_removed(label)
  }
}
