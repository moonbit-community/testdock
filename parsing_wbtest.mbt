///|
test "Docker endpoints use URI authority and IP parsing" {
  for
    (input, expected) in [
      ("unix:///var/run/docker.sock", "localhost"),
      ("npipe:////./pipe/docker_engine", "localhost"),
      ("tcp://127.0.0.1:2375", "127.0.0.1"),
      ("tcp://[2001:db8::1]:2376", "2001:db8::1"),
      ("ssh://user@example.com:22", "example.com"),
      ("ssh://user%40name@[::1]:22", "::1"),
      ("TCP://example.com:2375", "example.com"),
    ] {
    assert_eq(endpoint_host(input), expected)
  }
  for
    input in [
      "tcp://[broken]:2375", "tcp://:2375", "tcp://host:99999", "host:2375",
    ] {
    try endpoint_host(input) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid Docker endpoint: \{input}")
    }
  }
}

///|
test "YAML extracts services without depending on application names" {
  let source =
    #|name: example
    #|services:
    #|  hello:
    #|    image: example:latest
    #|  worker:
    #|    image: example:latest
  assert_eq(compose_services(source), ["hello", "worker"])
  for source in ["[]", "services: []", "services: {}\n---\nservices: {}"] {
    try compose_services(source) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid Compose shape")
    }
  }
}

///|
test "port bindings preserve protocol, family and unbound ports" {
  let ports = parse_ports({
    "Ports": {
      "8080/tcp": [
        { "HostIp": "0.0.0.0", "HostPort": "49152" },
        { "HostIp": "::", "HostPort": "49153" },
      ],
      "8080/udp": [{ "HostIp": "127.0.0.1", "HostPort": "49154" }],
      "9000/tcp": null,
    },
  })
  assert_eq(find_port(ports, "8080", ipv6=false), Some("49152"))
  assert_eq(find_port(ports, "8080/tcp", ipv6=true), Some("49153"))
  assert_eq(find_port(ports, "8080/udp", ipv6=false), Some("49154"))
  assert_eq(find_port(ports, "9000", ipv6=false), None)
  assert_eq(find_port(ports, "1234", ipv6=true), None)
  assert_eq(ports.get("9000/tcp"), Some([]))
  assert_true(parse_ports({ "Ports": null }).is_empty())
}

///|
test "multiple host ports require explicit selection" {
  let ports = { "80/tcp": [("127.0.0.1", "8000"), ("127.0.0.2", "8001")] }
  try find_port(ports, "80", ipv6=false) catch {
    DockerError::UnexpectedOutput(_) => ()
    error => raise error
  } noraise {
    _ => fail("silently selected an ambiguous binding")
  }
}
