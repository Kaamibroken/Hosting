

use axum::{
    extract::{State, Path, Multipart, Query},
    http::{StatusCode, HeaderMap},
    routing::{post, get},
    Json, Router, response::Response,
};
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgPoolOptions;
use sqlx::Row;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncBufReadExt;

const INTERNAL_CLUSTER_SECRET_HEADER: &str = "x-internal-cluster-secret";
const INTERNAL_CLUSTER_SECRET_VALUE: &str = "SilentClusterSecret2026";

#[derive(Clone)]
struct WorkerState {
    pg_pool: sqlx::PgPool,
    redis_client: redis::Client,
}

#[derive(Deserialize, Clone)]
struct ActionPayload {
    project_id: String,
    user_id: i32,
    base_dir: String,
    port: i32,
    action: String,
}

#[derive(Deserialize)]
struct CreateProjectPayload {
    project_id: String,
    user_id: i32,
    base_dir: String,
}

#[derive(Deserialize)]
struct FileActionReq {
    filename: String,
    content: Option<String>,
    r#type: Option<String>,
    new_name: Option<String>,
}

#[derive(Deserialize)]
struct FileManagerQuery {
    project_id: String,
    user_id: i32,
    base_dir: String,
    port: i32,
    path: Option<String>,
    files: Option<String>,
}

#[derive(Serialize)]
struct WorkerResponse {
    status: String,
    message: String,
}

fn validate_cluster_request(headers: &HeaderMap) -> bool {
    if let Some(secret) = headers.get(INTERNAL_CLUSTER_SECRET_HEADER) {
        if let Ok(secret_str) = secret.to_str() {
            return secret_str == INTERNAL_CLUSTER_SECRET_VALUE;
        }
    }
    false
}

#[tokio::main]
async fn main() {
    let db_url = std::env::var("DATABASE_URL").expect("❌ DATABASE_URL missing");
    let redis_url = std::env::var("REDIS_URL").expect("❌ REDIS_URL missing");

    let pg_pool = PgPoolOptions::new()
        .max_connections(100)
        .connect(&db_url)
        .await
        .expect("❌ PostgreSQL Failed");

    let redis_client = redis::Client::open(redis_url).expect("❌ Redis Failed");
    let worker_state = Arc::new(WorkerState { pg_pool, redis_client });

    let recovery_state = worker_state.clone();
    tokio::spawn(async move {
        auto_recover_volume_projects(recovery_state).await;
    });

    let app = Router::new()
        .route("/api/worker/start", post(handle_start_project))
        .route("/api/worker/stop", post(handle_stop_project))
        .route("/api/worker/redeploy", post(handle_redeploy_project))
        .route("/api/worker/create", post(handle_create_project))
        .route("/api/worker/project/:project_id/details", get(get_project_telemetry_details))

        .route("/api/worker/project/export", get(volume_export_project))
        .route("/api/worker/project/import", post(volume_import_project))

        .route("/api/worker/files", get(volume_list_files))
        .route("/api/worker/files/upload", post(volume_upload_files))
        .route("/api/worker/files/create", post(volume_create_file_folder))
        .route("/api/worker/files/write", post(volume_write_file))
        .route("/api/worker/files/rename", post(volume_rename_file))
        .route("/api/worker/files/delete", post(volume_delete_files))
        .route("/api/worker/files/extract", post(volume_extract_zip))
        .route("/api/worker/files/download", get(volume_download_files))
        .with_state(worker_state);

    let addr = SocketAddr::from(([0, 0, 0, 0], 8085));

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn handle_create_project(
    State(state): State<Arc<WorkerState>>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<Json<WorkerResponse>, StatusCode> {

    if !validate_cluster_request(&headers) { 

        return Err(StatusCode::FORBIDDEN); 
    }

    let (mut project_id, mut user_id, mut base_dir, mut zip_bytes) = (String::new(), 0, String::new(), Vec::new());

    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        let name = field.name().unwrap_or("").to_string();
        if name == "project_id" { 
            project_id = field.text().await.unwrap_or_default(); 

        } else if name == "user_id" { 
            user_id = field.text().await.unwrap_or_default().parse().unwrap_or(0); 

        } else if name == "base_dir" { 
            base_dir = field.text().await.unwrap_or_default(); 

        } else if name == "files[]" { 
            let file_name = field.file_name().unwrap_or("unknown_source.zip").to_string();
            zip_bytes = field.bytes().await.unwrap_or_default().to_vec(); 

        }
    }

    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let sys_user = format!("u_jail_p{}", p_id);
    let sys_uid = 10000 + p_id;

    if tokio::fs::create_dir_all(&base_dir).await.is_err() { 

        return Err(StatusCode::INTERNAL_SERVER_ERROR); 
    }

    if !zip_bytes.is_empty() {
        let tmp_zip = format!("/tmp/onboard_{}.zip", p_id);

        if tokio::fs::write(&tmp_zip, &zip_bytes).await.is_ok() {

            let unpack_status = tokio::process::Command::new("unzip").args(&["-o", &tmp_zip, "-d", &base_dir]).status().await;

            let _ = tokio::fs::remove_file(&tmp_zip).await;
        }
    } else {

    }

    if let Ok(mut entries) = tokio::fs::read_dir(&base_dir).await {

        while let Ok(Some(entry)) = entries.next_entry().await {

        }
    }

    let _ = tokio::process::Command::new("sh").arg("-c").arg(format!("id -u {} 2>/dev/null || (useradd -m -u {} -s /bin/bash {} && chmod 711 /app/data/user_{})", sys_user, sys_uid, sys_user, user_id)).status().await;
    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
    let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

    append_to_redis_log(&state.redis_client, p_id, "🏗️ [SilentHost] Persistent sandbox grid storage successfully synchronized.\n", user_id).await;

    Ok(Json(WorkerResponse {
        status: "success".to_string(),
        message: "Sandbox storage volume directory successfully allocated and code payload synchronized".to_string(),
    }))
}

async fn handle_start_project(State(state): State<Arc<WorkerState>>, headers: HeaderMap, Json(payload): Json<ActionPayload>) -> Result<Json<WorkerResponse>, StatusCode> {
    let p_id: i32 = payload.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    if !validate_cluster_request(&headers) { 

        return Err(StatusCode::FORBIDDEN); 
    }

    let user_id = payload.user_id; 
    let base_dir = payload.base_dir.clone(); 
    let port = payload.port;
    let state_clone = state.clone();

    let check_main_py = format!("{}/main.py", base_dir);
    if tokio::fs::metadata(&check_main_py).await.is_ok() {

    }

    tokio::spawn(async move {
        let sys_user = format!("u_jail_p{}", p_id); let sys_uid = 10000 + p_id;
        let _ = tokio::process::Command::new("sh").arg("-c").arg(format!("id -u {} 2>/dev/null || (useradd -m -u {} -s /bin/bash {} && chmod 711 /app/data/user_{})", sys_user, sys_uid, sys_user, user_id)).status().await;
        let _ = tokio::fs::create_dir_all(&base_dir).await;
        let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
        let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

        let mut active_port = port;
        loop { if std::net::TcpListener::bind(format!("127.0.0.1:{}", active_port)).is_ok() { break; } active_port += 1; }

        let mut safe_envs = vec![
            ("HOME".to_string(), format!("/app/data/user_{}", user_id)), 
            ("PORT".to_string(), active_port.to_string()),
            ("PYTHONUNBUFFERED".to_string(), "1".to_string()), 
            ("UV_THREADPOOL_SIZE".to_string(), "8".to_string()), 
            ("OMP_NUM_THREADS".to_string(), "4".to_string()),
        ];

        if let Ok(linked_dbs) = sqlx::query("SELECT db_type, internal_url FROM project_databases WHERE project_id = $1").bind(p_id).fetch_all(&state_clone.pg_pool).await {
            for db_row in linked_dbs {
                let db_type: String = db_row.get("db_type"); let internal_url: String = db_row.get("internal_url");
                if db_type == "postgres" { safe_envs.push(("POSTGRES_URL".to_string(), internal_url.clone())); safe_envs.push(("DATABASE_URL".to_string(), internal_url)); }
                else if db_type == "mongodb" { safe_envs.push(("MONGO_URL".to_string(), internal_url)); }
                else if db_type == "redis" { safe_envs.push(("REDIS_URL".to_string(), internal_url)); }
                else if db_type == "mysql" { safe_envs.push(("MYSQL_URL".to_string(), internal_url)); }
            }
        }

        if let Ok(env_row) = sqlx::query("SELECT env_vars FROM projects WHERE id = $1").bind(p_id).fetch_one(&state_clone.pg_pool).await {
            let env_vars: serde_json::Value = env_row.get("env_vars");
            if let Some(map) = env_vars.as_object() {
                let mut custom_env_file_buffer = String::new();
                for (k, v) in map {
                    if let Some(val_str) = v.as_str() {

                        safe_envs.push((k.clone(), val_str.to_string()));

                        custom_env_file_buffer.push_str(&format!("{}={}\n", k, val_str));
                    }
                }

                let live_env_target = format!("{}/.env", base_dir);
                if tokio::fs::write(&live_env_target, custom_env_file_buffer).await.is_ok() {
                    let _ = std::process::Command::new("chown").args(&[&format!("{}:{}", sys_user, sys_user), &live_env_target]).status();
                }
            }
        }

        let req_path = format!("{}/requirements.txt", base_dir); 
        let venv_path = format!("{}/.venv", base_dir);
        let dockerfile_path = format!("{}/Dockerfile", base_dir);

        if tokio::fs::metadata(&dockerfile_path).await.is_ok() {

            append_to_redis_log(&state_clone.redis_client, p_id, "🐳 [SilentHost] Dockerfile detected! Intelligently combining multi-line installation chains...\n", user_id).await;

            if let Ok(content) = tokio::fs::read_to_string(&dockerfile_path).await {
                let mut parsed_commands = Vec::new();
                let mut current_block = String::new();
                let mut inside_run_block = false;

                for line in content.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() || trimmed.starts_with('#') { continue; }

                    if trimmed.starts_with("RUN") {
                        inside_run_block = true;
                        let cmd_part = trimmed.trim_start_matches("RUN").trim();
                        current_block = cmd_part.to_string();
                    } else if inside_run_block {
                        current_block.push(' ');
                        current_block.push_str(trimmed);
                    } else {
                        inside_run_block = false;
                    }

                    if inside_run_block {
                        if current_block.ends_with('\\') {
                            current_block.pop(); 
                        } else {
                            let final_cmd = current_block.trim().to_string();
                            if !final_cmd.is_empty() {
                                parsed_commands.push(final_cmd);
                            }
                            inside_run_block = false;
                            current_block.clear();
                        }
                    }
                }

                if inside_run_block && !current_block.is_empty() {
                    let final_cmd = current_block.trim().to_string();
                    if !final_cmd.is_empty() { parsed_commands.push(final_cmd); }
                }

                for raw_cmd in parsed_commands {
                    let cmd_low = raw_cmd.to_lowercase();

                    if cmd_low.contains("rm -rf") || cmd_low.contains("apt-get upgrade") || cmd_low.contains("/etc") || cmd_low.contains("from ") || cmd_low.contains("copy ") {

                        continue;
                    }

                    if cmd_low.contains("apt") || cmd_low.contains("pip") || cmd_low.contains("python") || cmd_low.contains("wget") || cmd_low.contains("curl") || cmd_low.contains("git") {

                        append_to_redis_log(&state_clone.redis_client, p_id, &format!("🐳 [Dockerfile RUN] Syncing Layer: {}\n", raw_cmd), user_id).await;

                        let mut cmd_job = tokio::process::Command::new("sh");
                        cmd_job.current_dir(&base_dir)
                               .env_clear()
                               .envs(safe_envs.clone())
                               .arg("-c")
                               .arg(&raw_cmd)
                               .stdout(std::process::Stdio::piped());

                        if !cmd_low.contains("apt") && !cmd_low.contains("apt-get") {
                            cmd_job.uid(sys_uid as u32).gid(sys_uid as u32);
                        }

                        if let Ok(mut child) = cmd_job.spawn() {
                            if let Some(out) = child.stdout.take() {
                                let mut reader = tokio::io::BufReader::new(out).lines();
                                while let Ok(Some(line)) = reader.next_line().await {
                                    append_to_redis_log(&state_clone.redis_client, p_id, &format!("{}\n", line), user_id).await;
                                }
                            }
                            let _ = child.wait().await;
                        }
                    }
                }
            }
        }

        if tokio::fs::metadata(&req_path).await.is_ok() && tokio::fs::metadata(&venv_path).await.is_err() {
            append_to_redis_log(&state_clone.redis_client, p_id, "📦 [SilentHost] Compiling virtual isolated environment (.venv)...\n", user_id).await;
            let _ = tokio::process::Command::new("python3").args(&["-m", "venv", ".venv"]).current_dir(&base_dir).uid(sys_uid as u32).gid(sys_uid as u32).status().await;
        }

        if tokio::fs::metadata(&req_path).await.is_ok() {
            append_to_redis_log(&state_clone.redis_client, p_id, "⚡ [SilentHost] Resolving blueprints from requirements.txt...\n", user_id).await;
            let pip_exec = "./.venv/bin/pip install -r requirements.txt --prefer-binary --no-warn-script-location 2>&1";
            if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).uid(sys_uid as u32).gid(sys_uid as u32).arg("-c").arg(pip_exec).stdout(std::process::Stdio::piped()).spawn() {
                if let Some(out) = child.stdout.take() {
                    let mut reader = tokio::io::BufReader::new(out).lines();
                    while let Ok(Some(line)) = reader.next_line().await { append_to_redis_log(&state_clone.redis_client, p_id, &format!("{}\n", line), user_id).await; }
                }
                let _ = child.wait().await;
            }
        }

        let host_path = format!("{}/.venv/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin", base_dir);
        safe_envs.push(("PATH".to_string(), host_path));

        let python_exec = if tokio::fs::metadata(format!("{}/.venv/bin/python3", base_dir)).await.is_ok() { "./.venv/bin/python3" } else { "python3" };
        let mut start_cmd = format!("{} main.py", python_exec);
        for f in ["app.py", "bot.py", "server.py"] { if tokio::fs::metadata(format!("{}/{}", base_dir, f)).await.is_ok() { start_cmd = format!("{} {}", python_exec, f); break; } }

        let _ = sqlx::query("UPDATE projects SET status = 'Online', port = $1 WHERE id = $2").bind(active_port).bind(p_id).execute(&state_clone.pg_pool).await;
        if let Ok(mut redis_conn) = state_clone.redis_client.get_multiplexed_tokio_connection().await {
            let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", p_id)).arg("Online").query_async(&mut redis_conn).await;
            let channel_name = format!("project:{}:updates", p_id);
            let status_msg = serde_json::json!({ "project_id": p_id, "type": "status_update", "value": "Online" }).to_string();
            let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(status_msg).query_async(&mut redis_conn).await;
        }

        append_to_redis_log(&state_clone.redis_client, p_id, "🚀 [SilentHost] Core application ignited successfully inside the volume container.\n\n", user_id).await;

        let state_watch = state_clone.clone(); let base_dir_watch = base_dir.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(4)).await;
                let row = sqlx::query("SELECT plan_type, status FROM projects WHERE id = $1").bind(p_id).fetch_one(&state_watch.pg_pool).await;
                if let Ok(r) = row {
                    if r.get::<String, _>("status") == "Offline" { break; }
                    let plan_type: String = r.get("plan_type");
                    let ram_used = get_jail_ram_usage(sys_uid as u32);
                    let storage_used = get_dir_size(std::path::Path::new(&base_dir_watch));
                    let (ram_limit, storage_limit) = match plan_type.to_lowercase().as_str() { "basic" => (1024, 2048), "pro" => (2048, 5120), _ => (512, 1024) };

                    if ram_used > ram_limit || storage_used > storage_limit {
                        let _ = tokio::process::Command::new("pkill").args(&["-9", "-u", &sys_user]).status().await;
                        let kill_log = format!("\n🚨 [LIMIT EXCEEDED] Sandbox killed! Tier: {}. RAM: {}MB/{}MB, Storage: {}MB/{}MB.\n", plan_type, ram_used, ram_limit, storage_used, storage_limit);
                        append_to_redis_log(&state_watch.redis_client, p_id, &kill_log, user_id).await;
                        let _ = sqlx::query("UPDATE projects SET status = 'Crashed' WHERE id = $1").bind(p_id).execute(&state_watch.pg_pool).await;
                        if let Ok(mut redis_conn) = state_watch.redis_client.get_multiplexed_tokio_connection().await {
                            let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", p_id)).arg("Crashed").query_async(&mut redis_conn).await;
                            let channel_name = format!("project:{}:updates", p_id);
                            let status_msg = serde_json::json!({ "project_id": p_id, "type": "status_update", "value": "Crashed" }).to_string();
                            let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(status_msg).query_async(&mut redis_conn).await;
                        }
                        break;
                    }
                } else { break; }
            }
        });

        let start_exec = format!("umask 000; ulimit -n 65535 2>/dev/null; echo $$ > run.pid; exec {} 2>&1", start_cmd);
        if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).env_clear().envs(safe_envs).uid(sys_uid as u32).gid(sys_uid as u32).arg("-c").arg(&start_exec).process_group(0).stdout(std::process::Stdio::piped()).spawn() {
            if let Some(out) = child.stdout.take() {
                let mut reader = tokio::io::BufReader::new(out).lines();
                while let Ok(Some(line)) = reader.next_line().await { append_to_redis_log(&state_clone.redis_client, p_id, &format!("{}\n", line), user_id).await; }
            }
            let _ = child.wait().await;
        }
        let _ = sqlx::query("UPDATE projects SET status = 'Offline' WHERE id = $1").bind(p_id).execute(&state_clone.pg_pool).await;
    });

    Ok(Json(WorkerResponse { status: "success".to_string(), message: "VIP Volume Core ignited successfully".to_string() }))
}

async fn handle_stop_project(State(state): State<Arc<WorkerState>>, headers: HeaderMap, Json(payload): Json<ActionPayload>) -> Result<Json<WorkerResponse>, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let p_id: i32 = payload.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let sys_user = format!("u_jail_p{}", p_id);

    let _ = tokio::process::Command::new("pkill").args(&["-9", "-u", &sys_user]).status().await;
    let _ = sqlx::query("UPDATE projects SET status = 'Offline' WHERE id = $1").bind(p_id).execute(&state.pg_pool).await;

    if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
        let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", p_id)).arg("Offline").query_async(&mut redis_conn).await;
        let channel_name = format!("project:{}:updates", p_id);
        let status_msg = serde_json::json!({ "project_id": p_id, "type": "status_update", "value": "Offline" }).to_string();
        let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(status_msg).query_async(&mut redis_conn).await;
    }

    append_to_redis_log(&state.redis_client, p_id, "\n🛑 [SYSTEM] Process container stopped safely across the isolation node.\n", payload.user_id).await;
    Ok(Json(WorkerResponse { status: "success".to_string(), message: "Stopped".to_string() }))
}

async fn handle_redeploy_project(State(state): State<Arc<WorkerState>>, headers: HeaderMap, Json(payload): Json<ActionPayload>) -> Result<Json<WorkerResponse>, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let stop_payload = payload.clone(); let _ = handle_stop_project(State(state.clone()), headers.clone(), Json(stop_payload)).await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    handle_start_project(State(state), headers, Json(payload)).await
}

async fn get_project_telemetry_details(State(state): State<Arc<WorkerState>>, headers: HeaderMap, Path(project_id): Path<String>) -> Result<Json<serde_json::Value>, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    match sqlx::query("SELECT user_id, plan_type FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(row) => {
            let user_id: i32 = row.get("user_id");
            let plan_type: String = row.get("plan_type");
            let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
            let sys_uid = 10000 + p_id;
            let ram_used = get_jail_ram_usage(sys_uid as u32);
            let storage_used = get_dir_size(std::path::Path::new(&base_dir));
            let (ram_total, storage_total) = match plan_type.to_lowercase().as_str() {
                "basic" => (1024, 2048), "pro" => (2048, 5120), _ => (512, 1024),
            };
            Ok(Json(serde_json::json!({ "status": "Online", "plan_type": plan_type, "ram_used": ram_used, "ram_total": ram_total, "storage_used": storage_used, "storage_total": storage_total })))
        },
        Err(e) => {

            Err(StatusCode::NOT_FOUND)
        }
    }
}

async fn volume_import_project(
    State(state): State<Arc<WorkerState>>,
    headers: HeaderMap,
    Query(p): Query<FileManagerQuery>,
    mut multipart: Multipart,
) -> Result<StatusCode, StatusCode> {

    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }

    let mut zip_bytes = Vec::new();
    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        if field.name().unwrap_or("") == "archive" { zip_bytes = field.bytes().await.unwrap_or_default().to_vec(); }
    }
    if zip_bytes.is_empty() { return Err(StatusCode::BAD_REQUEST); }

    let p_id: i32 = p.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let tmp_import_zip = format!("/tmp/import_pkg_{}.zip", p_id);
    if tokio::fs::write(&tmp_import_zip, zip_bytes).await.is_err() { return Err(StatusCode::INTERNAL_SERVER_ERROR); }

    let _ = tokio::fs::remove_dir_all(&p.base_dir).await;
    let _ = tokio::fs::create_dir_all(&p.base_dir).await;

    let status = tokio::process::Command::new("unzip").args(&["-o", &tmp_import_zip, "-d", &p.base_dir]).status().await;
    let _ = tokio::fs::remove_file(&tmp_import_zip).await;

    if let Ok(s) = status {
        if s.success() {
            let sys_user = format!("u_jail_p{}", p_id);
            let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &p.base_dir]).status();
            let _ = std::process::Command::new("chmod").args(&["-R", "755", &p.base_dir]).status();
            append_to_redis_log(&state.redis_client, p_id, "📥 [SYSTEM] New workspace backup layout successfully deployed onto the cluster grid.\n", p.user_id).await;
            return Ok(StatusCode::OK);
        }
    }
    Err(StatusCode::BAD_REQUEST)
}

async fn volume_export_project(
    headers: HeaderMap,
    Query(q): Query<FileManagerQuery>,
) -> Result<Response, StatusCode> {

    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }

    let p_id = q.project_id.parse::<i32>().map_err(|_| StatusCode::BAD_REQUEST)?;
    let tmp_export_zip = format!("/tmp/export_pkg_{}.zip", p_id);

    let status = tokio::process::Command::new("zip")
        .arg("-r").arg(&tmp_export_zip).arg(".")
        .arg("-x").arg("node_modules/*").arg("venv/*").arg(".venv/*").arg("target/*").arg("app.log").arg("run.pid")
        .current_dir(&q.base_dir).status().await;

    if let Ok(s) = status {
        if s.success() {
            if let Ok(bytes) = tokio::fs::read(&tmp_export_zip).await {
                let _ = tokio::fs::remove_file(&tmp_export_zip).await;
                return Ok(Response::builder()
                    .status(200).header("Content-Type", "application/zip")
                    .header("Content-Disposition", format!("attachment; filename=\"export_{}.zip\"", p_id))
                    .body(axum::body::Body::from(bytes)).unwrap());
            }
        }
    }
    let _ = tokio::fs::remove_file(&tmp_export_zip).await;
    Err(StatusCode::INTERNAL_SERVER_ERROR)
}

async fn volume_list_files(headers: HeaderMap, Query(q): Query<FileManagerQuery>) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let sub_path = q.path.unwrap_or_default().trim_matches('/').to_string();
    let target_dir = if sub_path.is_empty() { q.base_dir.clone() } else { format!("{}/{}", q.base_dir, sub_path) };
    let mut files_list = Vec::new();
    let mut entries = tokio::fs::read_dir(&target_dir).await.map_err(|_| StatusCode::NOT_FOUND)?;
    while let Ok(Some(entry)) = entries.next_entry().await {
        let name = entry.file_name().to_string_lossy().to_string();
        if name == ".venv" || name == "__pycache__" || name == "run.pid" || name == "app.log" { continue; }
        let metadata = entry.metadata().await.unwrap();
        let f_type = if metadata.is_dir() { "folder" } else { "file" };
        files_list.push(serde_json::json!({ "name": name, "type": f_type, "size": format!("{} KB", metadata.len() / 1024) }));
    }
    Ok(Json(files_list))
}

async fn volume_upload_files(headers: HeaderMap, Query(q): Query<FileManagerQuery>, mut multipart: Multipart) -> Result<StatusCode, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let sub_path = q.path.unwrap_or_default().trim_matches('/').to_string();
    let upload_dir = if sub_path.is_empty() { q.base_dir.clone() } else { format!("{}/{}", q.base_dir, sub_path) };
    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        if let Some(filename) = field.file_name() {
            let file_path = format!("{}/{}", upload_dir, filename);
            if let Ok(bytes) = field.bytes().await { let _ = tokio::fs::write(&file_path, bytes).await; }
        }
    }
    let sys_user = format!("u_jail_p{}", q.project_id);
    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &q.base_dir]).status();
    Ok(StatusCode::OK)
}

async fn volume_create_file_folder(headers: HeaderMap, Query(p): Query<FileManagerQuery>, Json(payload): Json<FileActionReq>) -> Result<StatusCode, StatusCode> {

    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let target_path = format!("{}/{}", p.base_dir, payload.filename.trim_matches('/'));

    if payload.r#type.unwrap_or_default() == "folder" { 
        let _ = tokio::fs::create_dir_all(&target_path).await; 
    } else { 
        let _ = tokio::fs::write(&target_path, "").await; 
    }
    let sys_user = format!("u_jail_p{}", p.project_id);
    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &p.base_dir]).status();
    Ok(StatusCode::OK)
}

async fn volume_write_file(headers: HeaderMap, Query(p): Query<FileManagerQuery>, Json(payload): Json<FileActionReq>) -> Result<StatusCode, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let target_path = format!("{}/{}", p.base_dir, payload.filename.trim_matches('/'));
    if tokio::fs::write(&target_path, payload.content.unwrap_or_default().into_bytes()).await.is_ok() {
        let sys_user = format!("u_jail_p{}", p.project_id);
        let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &p.base_dir]).status();
        Ok(StatusCode::OK)
    } else { Err(StatusCode::INTERNAL_SERVER_ERROR) }
}

async fn volume_rename_file(headers: HeaderMap, Query(p): Query<FileManagerQuery>, Json(payload): Json<FileActionReq>) -> Result<StatusCode, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let old = format!("{}/{}", p.base_dir, payload.filename.trim_matches('/'));
    let new = format!("{}/{}", p.base_dir, payload.new_name.unwrap_or_default().trim_matches('/'));
    if tokio::fs::rename(&old, &new).await.is_ok() { Ok(StatusCode::OK) } else { Err(StatusCode::INTERNAL_SERVER_ERROR) }
}

async fn volume_delete_files(headers: HeaderMap, Query(p): Query<FileManagerQuery>, Json(payload): Json<FileActionReq>) -> Result<StatusCode, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let target = format!("{}/{}", p.base_dir, payload.filename.trim_matches('/'));
    if let Ok(m) = tokio::fs::metadata(&target).await {
        if m.is_dir() { let _ = tokio::fs::remove_dir_all(&target).await; }
        else { let _ = tokio::fs::remove_file(&target).await; }
        Ok(StatusCode::OK)
    } else { Err(StatusCode::NOT_FOUND) }
}

async fn volume_extract_zip(headers: HeaderMap, Query(p): Query<FileManagerQuery>, Json(payload): Json<FileActionReq>) -> Result<StatusCode, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let zip_p = format!("{}/{}", p.base_dir, payload.filename.trim_matches('/'));

    if tokio::process::Command::new("unzip").args(&["-o", &zip_p, "-d", &p.base_dir]).status().await.is_ok() {

        let sys_user = format!("u_jail_p{}", p.project_id);
        let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &p.base_dir]).status();
        Ok(StatusCode::OK)
    } else { 
        Err(StatusCode::BAD_REQUEST) 
    }
}

async fn volume_download_files(headers: HeaderMap, Query(q): Query<FileManagerQuery>) -> Result<Response, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let files_p = q.files.unwrap_or_default();
    let targets: Vec<&str> = files_p.split(',').collect();
    let mut buf = Vec::new();
    {
        let mut zip = zip::ZipWriter::new(std::io::Cursor::new(&mut buf));
        let opt = zip::write::FileOptions::<()>::default().compression_method(zip::CompressionMethod::Stored);
        for f in targets {
            let path = format!("{}/{}", q.base_dir, f.trim_matches('/'));
            if let Ok(b) = tokio::fs::read(&path).await {
                let _ = zip.start_file(f, opt); let _ = std::io::Write::write_all(&mut zip, &b);
            }
        }
        let _ = zip.finish();
    }
    Ok(Response::builder().status(200).header("Content-Type", "application/zip").body(axum::body::Body::from(buf)).unwrap())
}

async fn auto_recover_volume_projects(state: Arc<WorkerState>) {
    tokio::time::sleep(Duration::from_secs(3)).await;
    let query = "SELECT id, user_id, port FROM projects WHERE language ILIKE 'python' AND status = 'Online'";
    if let Ok(rows) = sqlx::query(query).fetch_all(&state.pg_pool).await {
        let client = reqwest::Client::new();
        for r in rows {
            let p_id: i32 = r.get("id"); let u_id: i32 = r.get("user_id"); let port: i32 = r.get("port");
            let _ = client.post("http://127.0.0.1:8085/api/worker/start")
                .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE) 
                .json(&serde_json::json!({ "project_id": p_id.to_string(), "user_id": u_id, "base_dir": format!("/app/data/user_{}/project_{}", u_id, p_id), "port": port, "action": "start" })).send().await;
        }
    }
}

async fn append_to_redis_log(redis_client: &redis::Client, p_id: i32, new_text: &str, user_id: i32) {
    let incoming_lines: Vec<&str> = new_text.lines().filter(|l| !l.is_empty()).collect();
    if incoming_lines.is_empty() { return; }

    if let Ok(mut conn) = redis_client.get_multiplexed_tokio_connection().await {
        let log_key = format!("project:{}:history_logs", p_id);
        let channel_name = format!("project:{}:updates", p_id);
        let absolute_path = format!("/app/data/user_{}/project_{}", user_id, p_id);
        let jail_user = format!("u_jail_p{}", p_id);

        for line in incoming_lines {
            let cleaned_line = line.replace(&absolute_path, "/app").replace(&jail_user, "root").replace("/app/data", "/app");
            let _: Result<(), _> = redis::cmd("RPUSH").arg(&log_key).arg(&cleaned_line).query_async(&mut conn).await;
            let msg = serde_json::json!({ "project_id": p_id, "type": "log_update", "value": cleaned_line }).to_string();
            let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut conn).await;
        }
        let _: Result<(), _> = redis::cmd("LTRIM").arg(&log_key).arg(-200).arg(-1).query_async(&mut conn).await;
    }
}

fn get_jail_ram_usage(uid: u32) -> u64 {
    let mut sys = sysinfo::System::new();
    sys.refresh_all();
    let mut total_memory = 0;
    for (_pid, process) in sys.processes() {
        if let Some(p_uid) = process.user_id() {
            if p_uid.to_string() == uid.to_string() { total_memory += process.memory(); }
        }
    }
    total_memory / (1024 * 1024)
}

fn get_dir_size(path: &std::path::Path) -> u64 {
    let mut total_size = 0;
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() { total_size += get_dir_size(&p); }
            else if let Ok(meta) = entry.metadata() { total_size += meta.len(); }
        }
    }
    total_size / (1024 * 1024)
}
