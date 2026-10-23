///|
/// A container owned by a Compose project. This handle does not own cleanup.
struct Container {
  container_id : String
  host : String
}

///|
pub fn Container::id(self : Self) -> String {
  self.container_id
}

///|
/// Docker host without a port or IPv6 brackets, not the container's private IP.
pub fn Container::get_host(self : Self) -> String {
  self.host
}

///|
async fn Container::network_settings(self : Self) -> Json {
  let result = docker_checked([
    "inspect",
    "--type",
    "container",
    "--format",
    "{{json .NetworkSettings}}",
    self.container_id,
  ])
  @json.parse(@utf8.decode(result.0))
}

///|
/// Published bindings: "8080/tcp" -> [(host IP, host port), ...].
/// Exposed but unpublished ports have an empty array. Ports remain strings.
pub async fn Container::ports(
  self : Self,
) -> Map[String, Array[(String, String)]] {
  parse_ports(self.network_settings())
}

///|
/// Accepts "8080" (TCP), "8080/tcp" or "8080/udp". None means no IPv4 binding.
/// Multiple distinct IPv4 host ports raise an error; use ports() to select one.
pub async fn Container::get_host_port_ipv4(
  self : Self,
  port : String,
) -> String? {
  find_port(self.ports(), port, ipv6=false)
}

///|
/// None means no IPv6 binding. Docker command failures are raised separately.
pub async fn Container::get_host_port_ipv6(
  self : Self,
  port : String,
) -> String? {
  find_port(self.ports(), port, ipv6=true)
}

///|
/// IPv4 address on the default bridge, or the sole attached network.
/// Multiple non-default networks are ambiguous and raise an error.
/// A private container IP may not be reachable from the host on Docker Desktop.
pub async fn Container::get_bridge_ip_address(self : Self) -> String? {
  let settings = self.network_settings()
  guard settings is { "Networks": Object(networks), .. } else {
    raise DockerError::UnexpectedOutput("missing NetworkSettings.Networks")
  }
  let selected = if networks.get("bridge") is Some(bridge) {
    Some(bridge)
  } else {
    guard networks.length() <= 1 else {
      raise DockerError::UnexpectedOutput(
        "multiple networks; no unambiguous bridge address",
      )
    }
    networks.values().next()
  }
  if selected is Some({ "IPAddress": String(ip), .. }) && ip != "" {
    Some(ip)
  } else {
    None
  }
}

///|
fn parse_ports(settings : Json) -> Map[String, Array[(String, String)]] raise {
  guard settings is { "Ports": ports, .. } else {
    raise DockerError::UnexpectedOutput("missing NetworkSettings.Ports")
  }
  if ports is Null {
    return {}
  }
  guard ports is Object(ports) else {
    raise DockerError::UnexpectedOutput("expected a port mapping")
  }
  let result = Map([])
  for internal_port, bindings in ports {
    let mapped = []
    result.set(internal_port, mapped)
    if bindings is Null {
      continue
    }
    guard bindings is Array(bindings) else {
      raise DockerError::UnexpectedOutput("expected port bindings array")
    }
    for binding in bindings {
      guard binding
        is { "HostIp": String(host_ip), "HostPort": String(host_port), .. } else {
        raise DockerError::UnexpectedOutput("invalid port binding")
      }
      let port = @string.parse_int(host_port)
      guard port > 0 && port <= 65535 else {
        raise DockerError::UnexpectedOutput("invalid host port: \{host_port}")
      }
      mapped.push((host_ip, host_port))
    }
  }
  result
}

///|
fn find_port(
  ports : Map[String, Array[(String, String)]],
  port : String,
  ipv6~ : Bool,
) -> String? raise {
  let internal = if port.contains("/") { port } else { "\{port}/tcp" }
  let mut found = None
  if ports.get(internal) is Some(bindings) {
    for (host_ip, host_port) in bindings {
      if host_ip.contains(":") == ipv6 {
        if found is Some(previous) && previous != host_port {
          raise DockerError::UnexpectedOutput(
            "multiple host ports for \{internal}; use ports() to select a binding",
          )
        }
        found = Some(host_port)
      }
    }
  }
  found
}
