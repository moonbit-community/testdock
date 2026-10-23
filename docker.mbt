///|
priv suberror DockerError {
  InvalidConfig(String)
  NotStarted
  ServiceNotFound(String)
  AmbiguousService(String, Int32)
  UnexpectedOutput(String)
  CommandFailed(Array[String], Int32, String, String)
} derive(Debug)

///|
impl Show for DockerError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
async fn docker_checked(args : Array[String], cwd? : String) -> (Bytes, Bytes) {
  let cwd = cwd.map(path => path[:])
  let (exit_code, stdout, stderr) = @process.collect_output(
    "docker",
    args,
    cwd?,
  )
  if exit_code != 0 {
    raise DockerError::CommandFailed(
      args,
      exit_code,
      @utf8.decode_lossy(stdout.binary()),
      @utf8.decode_lossy(stderr.binary()),
    )
  }
  (stdout.binary(), stderr.binary())
}

///|
async fn docker_host() -> String {
  let context = @env.get_env_var("DOCKER_CONTEXT").unwrap_or("")
  if context == "" &&
    @env.get_env_var("DOCKER_HOST") is Some(endpoint) &&
    endpoint != "" {
    return endpoint_host(endpoint)
  }
  let args = ["context", "inspect", "--format", "{{.Endpoints.docker.Host}}"]
  if context != "" {
    args.push(context)
  }
  let output = docker_checked(args)
  endpoint_host(@utf8.decode(output.0).trim().to_owned())
}

///|
fn endpoint_host(endpoint : String) -> String raise {
  let url = @url.Url::parse(endpoint)
  match url.scheme {
    "unix" | "npipe" => "localhost"
    "tcp" | "http" | "https" | "ssh" => {
      guard url.host is Some(host) else {
        raise DockerError::InvalidConfig("Docker endpoint requires a host")
      }
      match host {
        IPv4(ip) => ip.to_string()
        IPv6(ip) => ip.to_string()
        Domain(name) | Opaque(name) => {
          guard name != "" else {
            raise DockerError::InvalidConfig("Docker endpoint requires a host")
          }
          name
        }
      }
    }
    _ => raise DockerError::InvalidConfig("unsupported Docker endpoint scheme")
  }
}
