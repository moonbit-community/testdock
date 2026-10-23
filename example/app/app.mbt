///|
fn message_json(row : @client.Row) -> Json raise {
  let id : Int32 = row.get_name("id")
  let body : String = row.get_name("body")
  { "id": Json(id), "body": Json(body) }
}

///|
pub async fn run() -> Unit {
  let config = @pgpool.Config(
    [
      @pgpool.ConnectionTarget(
        host=@env.get_env_var("PGHOST").unwrap_or("localhost"),
      ),
    ],
    user=@env.get_env_var("PGUSER").unwrap_or("postgres"),
    password=@env.get_env_var("PGPASSWORD").unwrap_or("example-password"),
    dbname=@env.get_env_var("PGDATABASE").unwrap_or("example"),
    application_name="testdock-example",
    ssl_mode=Disable,
    pool=@pgpool.PoolConfig(4),
  )
  let (pool, executor) = @pgpool.Pool::create(config)
  defer pool.close()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => executor.run())
    pool.ready()
    let schema =
      #|CREATE TABLE IF NOT EXISTS messages (
      #|  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      #|  body text NOT NULL
      #|);
    pool.batch_execute(schema)
    let app = @moonback.App(ctx => {
      ctx.get("/health", (_req, res) => {
        // Readiness requires both the HTTP server and the database schema.
        pool.query_one("SELECT COUNT(*) FROM messages") |> ignore
        res.send_text("ok")
      })
      ctx.get("/messages", (_req, res) => {
        let rows = pool.query_all("SELECT id, body FROM messages ORDER BY id")
        res.send_json(Json(rows.map(message_json)))
      })
      ctx.post("/messages", (req, res) => {
        guard req.body.json() is { "body": String(body), .. } && body != "" else {
          res.send_json(
            { "error": "body must be a non-empty string" },
            status=400,
          )
          return
        }
        let row = pool.query_one(
          "INSERT INTO messages (body) VALUES ($1::text) RETURNING id, body",
          params=[body],
        )
        res.send_json(message_json(row), status=201)
      })
    })
    defer app.close()
    app.serve(@moonback.listen(host="0.0.0.0", port=3000))
  })
}
