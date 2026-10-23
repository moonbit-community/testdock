///|
/// One disposable Compose project. Serialize operations on the same handle.
struct DockerCompose {
  config : String
  env : String?
  force_build : Bool
  cwd : String?
  mut project : String
  mut active : Bool
  mut ready : Bool
  mut host : String
  mut services : Array[String]
}

///|
pub(all) enum Client {
  Local
}

///|
/// `config` is a Compose file path. `env` is a Compose `--env-file` path.
/// `force_build=false` keeps Compose's normal policy, rather than passing `--no-build`.
pub fn DockerCompose::DockerCompose(
  config~ : String,
  env? : String,
  client~ : Client = Local,
  force_build~ : Bool = false,
) -> DockerCompose {
  println("[TestDock] Running docker compose ...")
  match client {
    Local =>
      {
        config,
        env,
        force_build,
        cwd: @env.current_dir(),
        project: "",
        active: false,
        ready: false,
        host: "",
        services: [],
      }
  }
}

///|
/// Wait for Compose's running/healthy state. Without a healthcheck, running is
/// sufficient. `timeout` is in milliseconds; omit it for no startup deadline.
/// Failed or timed-out startup attempts to remove the partially created project.
pub async fn DockerCompose::up(self : Self, timeout? : Int32) -> Unit {
  guard !self.active else {
    raise DockerError::InvalidConfig(
      "call down before starting this project again",
    )
  }
  // Run cleanup outside the timeout's cancelled task.
  errdefer self.down()
  if timeout is Some(timeout) {
    @async.with_timeout(timeout, () => self.start())
  } else {
    self.start()
  }
}

///|
async fn DockerCompose::start(self : Self) -> Unit {
  guard self.config != "" else {
    raise DockerError::InvalidConfig("config must be a Compose file path")
  }
  guard @env.rand(16) is Some(random) else {
    raise DockerError::InvalidConfig("could not generate a unique project name")
  }
  self.project = "testdock-" +
    [ for byte in random => byte.to_uint().to_string(radix=16) ].join("-")
  // Delegate interpolation, includes and merges to Compose, then inspect its YAML.
  let config = self.run(["config"])
  self.services = compose_services(@utf8.decode(config.0))
  self.host = docker_host()
  let args = ["up", "--detach", "--wait"]
  if self.force_build {
    args.push("--build")
  }
  self.active = true
  self.run(args) |> ignore
  self.ready = true
}

///|
/// Remove this project's containers, networks and volumes, keeping images.
/// External volumes and bind-mounted files are not removed. Idempotent.
pub async fn DockerCompose::down(self : Self) -> Unit {
  if self.active {
    self.run(["down", "--volumes", "--remove-orphans"]) |> ignore
    self.active = false
    self.ready = false
    self.services = []
  }
}

///|
/// Look up one service container, including completed init containers.
/// A replicated service raises an ambiguity error instead of choosing a replica.
pub async fn DockerCompose::service(self : Self, name : String) -> Container {
  guard self.ready else { raise DockerError::NotStarted }
  guard self.services.contains(name) else {
    raise DockerError::ServiceNotFound(name)
  }
  let output = self.run(["ps", "--all", "--quiet", name])
  let ids = @utf8.decode(output.0)
    .split("\n")
    .filter_map(line => {
      let line = line.trim()
      if line.is_empty() {
        None
      } else {
        Some(line.to_owned())
      }
    })
    .to_array()
  match ids {
    [id] => { container_id: id, host: self.host, }
    [] => raise DockerError::ServiceNotFound(name)
    _ => raise DockerError::AmbiguousService(name, ids.length())
  }
}

///|
async fn DockerCompose::run(
  self : Self,
  command : Array[String],
) -> (Bytes, Bytes) {
  let args = ["compose", "--project-name", self.project, "--file", self.config]
  if self.env is Some(env) {
    args.push("--env-file")
    args.push(env)
  }
  args.append(command)
  let cwd = self.cwd
  docker_checked(args, cwd?)
}

///|
fn compose_services(source : String) -> Array[String] raise {
  let documents = @yaml.Yaml::load_from_string(source)
  guard documents is [@yaml.Map(root)] &&
    root.get("services") is Some(@yaml.Map(services)) else {
    raise DockerError::InvalidConfig(
      "expected one Compose mapping with services",
    )
  }
  services.keys().to_array()
}
