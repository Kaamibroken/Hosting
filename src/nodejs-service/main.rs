// ============================================================================
// 👑 SILENTHOST PURE VOLUME NODEJS WORKER CORE (100% BULLETPROOF & COMPILABLE)
// ============================================================================
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

    // 🌟 ہینگ پروٹیکشن فکس: اب راؤٹر دونوں روٹس (/start اور /api/worker/start) کو فلی ہینڈل کرے گا
    // اب اگر مین سرور سے پاتھ مکسنگ کا کوئی بھی ایشو ائے گا، ورکر اسے ہر حال میں کیچ کر لے گا!
    let app = Router::new()
        .route("/start", post(handle_start_project))
        .route("/api/worker/start", post(handle_start_project))
        .route("/stop", post(handle_stop_project))
        .route("/api/worker/stop", post(handle_stop_project))
        .route("/redeploy", post(handle_redeploy_project))
        .route("/api/worker/redeploy", post(handle_redeploy_project))
        .route("/create", post(handle_create_project))
        .route("/api/worker/create", post(handle_create_project))
        .route("/api/worker/project/:project_id/details", get(get_project_telemetry_details))
        // --- 📥 IMPORT & EXPORT ARCHIVE ROUTERS ---
        .route("/api/worker/project/export", get(volume_export_project))
        .route("/api/worker/project/import", post(volume_import_project))
        // --- 📁 FILE MANAGER ROUTERS ---
        .route("/api/worker/files", get(volume_list_files))
        .route("/api/worker/files/upload", post(volume_upload_files))
        .route("/api/worker/files/create", post(volume_create_file_folder))
        .route("/api/worker/files/write", post(volume_write_file))
        .route("/api/worker/files/rename", post(volume_rename_file))
        .route("/api/worker/files/delete", post(volume_delete_files))
        .route("/api/worker/files/extract", post(volume_extract_zip))
        .route("/api/worker/files/download", get(volume_download_files))
        .with_state(worker_state);

    let addr = SocketAddr::from(([0, 0, 0, 0], 8086));
    println!("🚀 VIP Volume NodeJS Worker Engine Active on: {}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

// ============================================================================
// 🏗️ VIP WORKER PROJECT CREATION ENGINE (With Unpack Tracking & Perms)
// ============================================================================
async fn handle_create_project(
    State(state): State<Arc<WorkerState>>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<Json<WorkerResponse>, StatusCode> {
    println!("\n📥 [DEBUG NODEJS WORKER] ---> Intercepted /api/worker/create request from Main Server.");
    if !validate_cluster_request(&headers) { 
        println!("❌ [DEBUG NODEJS WORKER] Cluster Authentication Token Mismatch!"); 
        return Err(StatusCode::FORBIDDEN); 
    }

    let (mut project_id, mut user_id, mut base_dir, mut zip_bytes) = (String::new(), 0, String::new(), Vec::new());

    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        let name = field.name().unwrap_or("").to_string();
        if name == "project_id" { project_id = field.text().await.unwrap_or_default(); }
        else if name == "user_id" { user_id = field.text().await.unwrap_or_default().parse().unwrap_or(0); }
        else if name == "base_dir" { base_dir = field.text().await.unwrap_or_default(); }
        else if name == "files[]" { zip_bytes = field.bytes().await.unwrap_or_default().to_vec(); }
    }

    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let sys_user = format!("u_jail_p{}", p_id);
    let sys_uid = 10000 + p_id;

    if tokio::fs::create_dir_all(&base_dir).await.is_err() { return Err(StatusCode::INTERNAL_SERVER_ERROR); }

    if !zip_bytes.is_empty() {
        let tmp_zip = format!("/tmp/node_onboard_{}.zip", p_id);
        if tokio::fs::write(&tmp_zip, &zip_bytes).await.is_ok() {
            println!("📥 [DEBUG NODEJS WORKER] Extracting workspace package archive...");
            let _unpack_status = tokio::process::Command::new("unzip").args(&["-o", &tmp_zip, "-d", &base_dir]).status().await;
            let _ = tokio::fs::remove_file(&tmp_zip).await;
        }
    }

    let _ = tokio::process::Command::new("sh").arg("-c").arg(format!("id -u {} 2>/dev/null || (useradd -m -u {} -s /bin/bash {} && chmod 711 /app/data/user_{})", sys_user, sys_uid, sys_user, user_id)).status().await;
    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
    let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

    append_to_redis_log(&state.redis_client, p_id, "🏗️ [SilentHost] Persistent NodeJS volume workspace mapped and provisioned successfully.\n", user_id).await;

    Ok(Json(WorkerResponse {
        status: "success".to_string(),
        message: "Sandbox storage volume directory successfully allocated and locked".to_string(),
    }))
}

// ============================================================================
// ⚡ LIFE-CYCLE MANAGEMENT CONTROLLERS (Resilient Concurrency & Atomic Boot Lock)
// ============================================================================
async fn handle_start_project(State(state): State<Arc<WorkerState>>, headers: HeaderMap, Json(payload): Json<ActionPayload>) -> Result<Json<WorkerResponse>, StatusCode> {
    let p_id: i32 = payload.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    println!("\n🚀 [DEBUG NODEJS WORKER] ---> Received START signal for project ID string: {}", p_id);
    
    if !validate_cluster_request(&headers) { 
        println!("❌ [DEBUG NODEJS WORKER] Cluster Authentication Token Mismatch!");
        return Err(StatusCode::FORBIDDEN); 
    }

    // 🌟 Atomic Distributed Lock: Intercept and drop concurrent overlapping boot requests
    let lock_key = format!("project:{}:boot_lock", p_id);
    if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
        let is_locked: bool = redis::cmd("SET")
            .arg(&lock_key)
            .arg("true")
            .arg("NX")
            .arg("EX")
            .arg("45") // 45-second lock window to completely finish build/boot pipeline
            .query_async(&mut redis_conn)
            .await
            .unwrap_or(false);

        if !is_locked {
            println!("⚠️ [DEBUG NODEJS WORKER] Project {} boot pipeline already active. Dropping duplicate request.", p_id);
            return Ok(Json(WorkerResponse { 
                status: "success".to_string(), 
                message: "Boot pipeline already in progress for this runtime environment".to_string() 
            }));
        }
    }
    
    let user_id = payload.user_id; let base_dir = payload.base_dir.clone(); let port = payload.port;
    let state_clone = state.clone();

    tokio::spawn(async move {
        use std::os::unix::process::ExitStatusExt;

        let sys_user = format!("u_jail_p{}", p_id); let sys_uid = 10000 + p_id;
        
        let _ = tokio::process::Command::new("pkill")
            .args(&["-9", "-u", &sys_user])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .await;

        let _ = tokio::process::Command::new("sh").arg("-c").arg(format!("id -u {} 2>/dev/null || (useradd -m -u {} -s /bin/bash {} && chmod 711 /app/data/user_{})", sys_user, sys_uid, sys_user, user_id)).status().await;
        let _ = tokio::fs::create_dir_all(&base_dir).await;
        
        let local_cache_path = format!("{}/.cache", base_dir);
        let _ = tokio::fs::create_dir_all(&local_cache_path).await;
        
        let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
        let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

        let mut active_port = port;
        loop { if std::net::TcpListener::bind(format!("127.0.0.1:{}", active_port)).is_ok() { break; } active_port += 1; }

        let entry_files = [
            "index.js", "server.js", "app.js", "main.js", "bot.js", 
            "index.ts", "server.ts", "app.ts",
            "index.cjs", "server.cjs", "app.cjs", "main.cjs",
            "index.mjs", "server.mjs", "app.mjs", "main.mjs"
        ];
        for file_name in &entry_files {
            let file_path = format!("{}/{}", base_dir, file_name);
            if tokio::fs::metadata(&file_path).await.is_ok() {
                if let Ok(content) = tokio::fs::read_to_string(&file_path).await {
                    println!("⚙️ [DEBUG NODEJS WORKER] Patching hardcoded ports while preserving case style inside: {}", file_name);
                    
                    let re_listen = regex::Regex::new(r"(?i)(\.listen\s*\(\s*)\d+").unwrap();
                    let mut modified = re_listen.replace_all(&content, |caps: &regex::Captures| {
                        format!("{}{}", &caps[1], active_port)
                    }).to_string();
                    
                    let re_env_fallback = regex::Regex::new(r"(?i)(process\.env\.PORT\s*\|\|\s*)\d+").unwrap();
                    modified = re_env_fallback.replace_all(&modified, |caps: &regex::Captures| {
                        format!("{}{}", &caps[1], active_port)
                    }).to_string();

                    let re_port_var = regex::Regex::new(r"(?i)\b(ports?\s*=\s*)\d+").unwrap();
                    modified = re_port_var.replace_all(&modified, |caps: &regex::Captures| {
                        format!("{}{}", &caps[1], active_port)
                    }).to_string();

                    let _ = tokio::fs::write(&file_path, modified).await;
                }
            }
        }

        let puppeteer_cache_dir = format!("{}/puppeteer", local_cache_path);
        let host_path = format!("{}/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin", base_dir);
        
        // Removed explicit UV_THREADPOOL_SIZE allocation to prevent container PID limit exhaustion (Fixes Exit Code 134)
        let mut safe_envs = vec![
            ("HOME".to_string(), base_dir.clone()), 
            ("XDG_CACHE_HOME".to_string(), local_cache_path.clone()),
            ("PORT".to_string(), active_port.to_string()),
            ("NODE_ENV".to_string(), "production".to_string()), 
            ("PYTHON".to_string(), "python3".to_string()), 
            ("PUPPETEER_CACHE_DIR".to_string(), puppeteer_cache_dir.clone()),
            ("PATH".to_string(), host_path),
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
        
        // 🌟 کلسٹر وائڈ لائیو انوائرمنٹ ویری ایبلز انجیکشن انجن
        if let Ok(env_row) = sqlx::query("SELECT env_vars FROM projects WHERE id = $1").bind(p_id).fetch_one(&state_clone.pg_pool).await {
            let env_vars: serde_json::Value = env_row.try_get("env_vars").unwrap_or(serde_json::json!({}));
            if let Some(map) = env_vars.as_object() {
                let mut custom_env_file_buffer = String::new();
                for (k, v) in map {
                    if let Some(val_str) = v.as_str() {
                // الف: پروسیس کے اندر انوائرمنٹ ویری ایبل انجیکٹ کرنا
                        safe_envs.push((k.clone(), val_str.to_string()));
                // ب: فائل بفر بنانا تاکہ فریم ورک جیسے Next.js یا Dotenv اسے نیٹو ریڈ کر سکیں
                        custom_env_file_buffer.push_str(&format!("{}={}\n", k, val_str));
                    }
                }
        // ورکر کی ہارڈ ڈسک پر بھی لائیو کلون رائٹ کر دینا سیکیورٹی کے ساتھ
                let live_env_target = format!("{}/.env", base_dir);
                if tokio::fs::write(&live_env_target, custom_env_file_buffer).await.is_ok() {
                    let _ = std::process::Command::new("chown").args(&[&format!("{}:{}", sys_user, sys_user), &live_env_target]).status();
                }
            }
        }


        let pkg_json_path = format!("{}/package.json", base_dir);
        let hash_file_path = format!("{}/.package.json.hash", base_dir);
        let mut need_npm_install = true;
        let mut current_hash = String::new();

        if tokio::fs::metadata(&pkg_json_path).await.is_ok() {
            if let Ok(content) = tokio::fs::read_to_string(&pkg_json_path).await {
                println!("⚙️ [DEBUG NODEJS WORKER] Scanning raw package.json blueprints for delta changes...");
                
                use std::hash::{Hash, Hasher};
                let mut hasher = std::collections::hash_map::DefaultHasher::new();
                content.hash(&mut hasher);
                current_hash = hasher.finish().to_string();

                if tokio::fs::metadata(format!("{}/node_modules", base_dir)).await.is_ok() {
                    if let Ok(old_hash) = tokio::fs::read_to_string(&hash_file_path).await {
                        if old_hash.trim() == current_hash.trim() {
                            
                            let puppeteer_node_path = format!("{}/node_modules/puppeteer", base_dir);
                            if tokio::fs::metadata(&puppeteer_node_path).await.is_ok() {
                                let chrome_root = format!("{}/chrome", puppeteer_cache_dir);
                                let shell_root = format!("{}/chrome-headless-shell", puppeteer_cache_dir);
                                
                                let mut chrome_is_healthy = false;
                                let mut shell_is_healthy = false;
                                
                                if let Ok(entries) = std::fs::read_dir(&chrome_root) {
                                    for entry in entries.flatten() {
                                        if entry.path().join("chrome-linux64/chrome").exists() { chrome_is_healthy = true; break; }
                                    }
                                }
                                if let Ok(entries) = std::fs::read_dir(&shell_root) {
                                    for entry in entries.flatten() {
                                        if entry.path().join("chrome-headless-shell-linux64/chrome-headless-shell").exists() { shell_is_healthy = true; break; }
                                    }
                                }

                                if chrome_is_healthy && shell_is_healthy {
                                    need_npm_install = false; 
                                    println!("⚡ [DEBUG NODEJS WORKER] Cache hit: package.json is unchanged and browser is healthy.");
                                    append_to_redis_log(&state_clone.redis_client, p_id, "⚡ [SilentHost] Microsecond cache hit. Configuration is unchanged and Chromium binaries are healthy, bypassing build...\n", user_id).await;
                                } else {
                                    need_npm_install = true; 
                                    println!("🚨 [DEBUG NODEJS WORKER] Puppeteer binary corruption detected! Forcing repair build...");
                                    append_to_redis_log(&state_clone.redis_client, p_id, "🚨 [SilentHost] Puppeteer runtime corruption detected (Missing shell or chrome binary). Forcing auto-repair build...\n", user_id).await;
                                }
                            } else {
                                need_npm_install = false;
                                println!("⚡ [DEBUG NODEJS WORKER] Cache hit: Identical package.json (No Puppeteer). Skipping build chain.");
                                append_to_redis_log(&state_clone.redis_client, p_id, "⚡ [SilentHost] Microsecond cache hit. Bypassing build pipeline...\n", user_id).await;
                            }
                        }
                    }
                }
            }
        }

        let mut install_successful = false;

        if need_npm_install && tokio::fs::metadata(&pkg_json_path).await.is_ok() {
            println!("🚀 [DEBUG NODEJS WORKER] Executing package blueprint delta sync via npm install...");
            append_to_redis_log(&state_clone.redis_client, p_id, "📦 [SilentHost] Resolving system dependencies via npm install...\n", user_id).await;
            
            if tokio::fs::metadata(&puppeteer_cache_dir).await.is_ok() {
                let _ = tokio::process::Command::new("rm").args(&["-rf", &puppeteer_cache_dir]).status().await;
                println!("🧹 [DEBUG NODEJS WORKER] Hard purged puppeteer cache directory using root-level rm -rf execution.");
            }

            let tmp_npm_cache = format!("/tmp/npm_cache_{}", p_id);
            let _ = tokio::fs::create_dir_all(&tmp_npm_cache).await;
            let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &tmp_npm_cache]).status();
            
            // Cleaned npm flags to optimize startup execution velocity without pushing unknown arguments
            let npm_cmd = format!(
                "ulimit -u 65535 2>/dev/null; ulimit -n 65535 2>/dev/null; npm install --prefer-offline --no-audit --no-fund --foreground-scripts --ignore-scripts --cache {} 2>&1", 
                tmp_npm_cache
            );
            
            println!("⚙️ [DIAGNOSTIC] Launching optimally throttled npm process under UID: {}, GID: {}", sys_uid, sys_uid);
            if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).uid(sys_uid as u32).gid(sys_uid as u32).env_clear().envs(safe_envs.clone()).arg("-c").arg(&npm_cmd).stdout(std::process::Stdio::piped()).spawn() {
                if let Some(out) = child.stdout.take() {
                    let mut reader = tokio::io::BufReader::new(out).lines();
                    while let Ok(Some(line)) = reader.next_line().await { 
                        append_to_redis_log(&state_clone.redis_client, p_id, &format!("{}\n", line), user_id).await; 
                    }
                }
                
                match child.wait().await {
                    Ok(exit_status) => {
                        println!("⚙️ [DIAGNOSTIC] npm install finished. Success status: {}", exit_status.success());
                        if let Some(code) = exit_status.code() {
                            println!("⚙️ [DIAGNOSTIC] npm install terminated with exit code: {}", code);
                        }
                        if let Some(signal) = exit_status.signal() {
                            println!("🚨 [DIAGNOSTIC CRITICAL] npm install was abruptly killed by OS signal: {}", signal);
                            let diagnostic_log = format!("🚨 [SilentHost] Build process aborted by system signal: {}. (Signal 9 = Out of Memory/Cgroup Kill, Signal 6 = Aborted)\n", signal);
                            append_to_redis_log(&state_clone.redis_client, p_id, &diagnostic_log, user_id).await;
                        }
                        if exit_status.success() {
                            install_successful = true;
                        }
                    }
                    Err(e) => {
                        println!("❌ [DIAGNOSTIC] Failed to capture npm install exit status: {:?}", e);
                    }
                }
            } else {
                println!("❌ [DIAGNOSTIC] Failed to spawn shell process for npm install execution.");
            }
            let _ = tokio::fs::remove_dir_all(&tmp_npm_cache).await;

            let puppeteer_install_script = format!("{}/node_modules/puppeteer/install.mjs", base_dir);
            if install_successful && tokio::fs::metadata(&puppeteer_install_script).await.is_ok() {
                println!("🧹 [DEBUG NODEJS WORKER] Launching clean isolated manual Chromium bin capture sync...");
                append_to_redis_log(&state_clone.redis_client, p_id, "⚙️ [SilentHost] Syncing production Chromium browser binary inside sandbox...\n", user_id).await;
                
                if let Ok(mut child) = tokio::process::Command::new("sh")
                    .current_dir(&base_dir)
                    .uid(sys_uid as u32)
                    .gid(sys_uid as u32)
                    .env_clear()
                    .envs(safe_envs.clone())
                    .arg("-c")
                    .arg("node node_modules/puppeteer/install.mjs 2>&1")
                    .stdout(std::process::Stdio::piped())
                    .spawn() {
                        if let Some(out) = child.stdout.take() {
                            let mut reader = tokio::io::BufReader::new(out).lines();
                            while let Ok(Some(line)) = reader.next_line().await { append_to_redis_log(&state_clone.redis_client, p_id, &format!("{}\n", line), user_id).await; }
                        }
                        let _ = child.wait().await;
                    }
            }

            if install_successful && !current_hash.is_empty() {
                let _ = tokio::fs::write(&hash_file_path, &current_hash).await;
                println!("💾 [DEBUG NODEJS WORKER] Build pipeline completed successfully. Saved deployment state hash matrix.");
            }
        }

        let mut start_cmd = String::new();
        if tokio::fs::metadata(&pkg_json_path).await.is_ok() {
            if let Ok(content) = tokio::fs::read_to_string(&pkg_json_path).await {
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(cmd) = parsed.get("scripts").and_then(|s| s.get("start")).and_then(|c| c.as_str()) {
                        start_cmd = cmd.to_string();
                        println!("🎯 [DEBUG NODEJS WORKER] Extracted native user start script: '{}'", start_cmd);
                    }
                }
            }
        }

        if start_cmd.is_empty() {
            start_cmd = "node index.js".to_string(); 
            let scan_files = [
                "index.js", "server.js", "bot.js", "app.js", "main.js",
                "index.ts", "server.ts", "app.ts",
                "index.cjs", "server.cjs", "app.cjs", "main.cjs",
                "index.mjs", "server.mjs", "app.mjs", "main.mjs"
            ];
            for f in scan_files {
                if tokio::fs::metadata(format!("{}/{}", base_dir, f)).await.is_ok() {
                    start_cmd = format!("node {}", f);
                    println!("🔍 [DEBUG NODEJS WORKER] Start script missing. Auto-detected entry file root hook: '{}'", start_cmd);
                    break;
                }
            }
        }

        let final_execution_command = start_cmd;

        let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
        let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

        // 🌟 Release the atomic distributed lock right before spawning long-running application context
        if let Ok(mut redis_conn) = state_clone.redis_client.get_multiplexed_tokio_connection().await {
            let _: Result<(), _> = redis::cmd("DEL").arg(&lock_key).query_async(&mut redis_conn).await;
        }

        println!("🚀 [DEBUG NODEJS WORKER] Firing full-freedom execution command for Proj {}: '{}'", p_id, final_execution_command);
        let _ = sqlx::query("UPDATE projects SET status = 'Online', port = $1 WHERE id = $2").bind(active_port).bind(p_id).execute(&state_clone.pg_pool).await;
        if let Ok(mut redis_conn) = state_clone.redis_client.get_multiplexed_tokio_connection().await {
            let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", p_id)).arg("Online").query_async(&mut redis_conn).await;
            let channel_name = format!("project:{}:updates", p_id);
            let status_msg = serde_json::json!({ "project_id": p_id, "type": "status_update", "value": "Online" }).to_string();
            let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(status_msg).query_async(&mut redis_conn).await;
        }

        append_to_redis_log(&state_clone.redis_client, p_id, "🚀 [SilentHost] Core NodeJS application successfully ignited via isolated sandbox container.\n\n", user_id).await;

        let state_watch = state_clone.clone(); let base_dir_watch = base_dir.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(4)).await;
                let row = sqlx::query("SELECT plan_type, status FROM projects WHERE id = $1").bind(p_id).fetch_one(&state_watch.pg_pool).await;
                if let Ok(r) = row {
                    if r.get::<String, _>("status") == "Offline" || r.get::<String, _>("status") == "Crashed" { break; }
                    let plan_type: String = r.get("plan_type");
                    let ram_used = get_jail_ram_usage(sys_uid as u32);
                    let storage_used = get_dir_size(std::path::Path::new(&base_dir_watch));
                    let (ram_limit, storage_total) = match plan_type.to_lowercase().as_str() { "basic" => (1024, 2048), "pro" => (2048, 5120), _ => (512, 1024) };

                    if ram_used > ram_limit || storage_used > storage_total {
                        let _ = tokio::process::Command::new("pkill").args(&["-9", "-u", &sys_user]).status().await;
                        let kill_log = format!("\n🚨 [LIMIT EXCEEDED] Sandbox killed automatically! RAM: {}MB/{}MB, Storage: {}MB/{}MB.\n", ram_used, ram_limit, storage_used, storage_total);
                        append_to_redis_log(&state_watch.redis_client, p_id, &kill_log, user_id).await;
                        let _ = sqlx::query("UPDATE projects SET status = 'Crashed' WHERE id = $1").bind(p_id).execute(&state_watch.pg_pool).await;
                        break;
                    }
                } else { break; }
            }
        });

        let start_exec = format!("umask 000; ulimit -u 500000 2>/dev/null; ulimit -n 500000 2>/dev/null; echo $$ > run.pid; exec {} 2>&1", final_execution_command);
        let mut application_failed_at_runtime = false;

        if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).env_clear().envs(safe_envs).uid(sys_uid as u32).gid(sys_uid as u32).arg("-c").arg(&start_exec).process_group(0).stdout(std::process::Stdio::piped()).spawn() {
            if let Some(out) = child.stdout.take() {
                let mut reader = tokio::io::BufReader::new(out).lines();
                while let Ok(Some(line)) = reader.next_line().await { 
                    append_to_redis_log(&state_clone.redis_client, p_id, &format!("{}\n", line), user_id).await; 
                    if line.contains("Error: Cannot find module") || line.contains("node:internal/modules/cjs/loader") || line.contains("FATAL ERROR") {
                        application_failed_at_runtime = true;
                    }
                }
            }
            
            if let Ok(exit_status) = child.wait().await {
                if !exit_status.success() || application_failed_at_runtime {
                    println!("❌ [DEBUG NODEJS WORKER] Application process crashed at runtime! Syncing 'Crashed' state matrix...");
                    let _ = sqlx::query("UPDATE projects SET status = 'Crashed' WHERE id = $1").bind(p_id).execute(&state_clone.pg_pool).await;
                    if let Ok(mut redis_conn) = state_clone.redis_client.get_multiplexed_tokio_connection().await {
                        let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", p_id)).arg("Crashed").query_async(&mut redis_conn).await;
                        let channel_name = format!("project:{}:updates", p_id);
                        let status_msg = serde_json::json!({ "project_id": p_id, "type": "status_update", "value": "Crashed" }).to_string();
                        let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(status_msg).query_async(&mut redis_conn).await;
                    }
                    append_to_redis_log(&state_clone.redis_client, p_id, "❌ [RUNTIME CRASH] The node core process terminated due to unhandled exceptions. Suspended.\n", user_id).await;
                    return;
                }
            }
        }
        
        let _ = sqlx::query("UPDATE projects SET status = 'Offline' WHERE id = $1").bind(p_id).execute(&state_clone.pg_pool).await;
    });

    Ok(Json(WorkerResponse { status: "success".to_string(), message: "VIP Volume Core ignited successfully with bulletproof resilience".to_string() }))
}


async fn handle_stop_project(State(state): State<Arc<WorkerState>>, headers: HeaderMap, Json(payload): Json<ActionPayload>) -> Result<Json<WorkerResponse>, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let p_id: i32 = payload.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let sys_user = format!("u_jail_p{}", p_id);

    let _ = tokio::process::Command::new("pkill").args(&["-9", "-u", &sys_user]).status().await;
    let _ = sqlx::query("UPDATE projects SET status = 'Offline' WHERE id = $1").bind(p_id).execute(&state.pg_pool).await;

    if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
        let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", p_id)).arg("Offline").query_async(&mut redis_conn).await;
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
        Err(_) => Err(StatusCode::NOT_FOUND)
    }
}

async fn volume_import_project(State(state): State<Arc<WorkerState>>, headers: HeaderMap, Query(p): Query<FileManagerQuery>, mut multipart: Multipart) -> Result<StatusCode, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let mut zip_bytes = Vec::new();
    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        if field.name().unwrap_or("") == "archive" { zip_bytes = field.bytes().await.unwrap_or_default().to_vec(); }
    }
    if zip_bytes.is_empty() { return Err(StatusCode::BAD_REQUEST); }
    let p_id: i32 = p.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let tmp_import_zip = format!("/tmp/node_import_{}.zip", p_id);
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
            append_to_redis_log(&state.redis_client, p_id, "📥 [SYSTEM] NodeJS backup deployment packaging sync ok.\n", p.user_id).await;
            return Ok(StatusCode::OK);
        }
    }
    Err(StatusCode::BAD_REQUEST)
}

async fn volume_export_project(headers: HeaderMap, Query(q): Query<FileManagerQuery>) -> Result<Response, StatusCode> {
    if !validate_cluster_request(&headers) { return Err(StatusCode::FORBIDDEN); }
    let p_id = q.project_id.parse::<i32>().map_err(|_| StatusCode::BAD_REQUEST)?;
    let tmp_export_zip = format!("/tmp/node_export_{}.zip", p_id);

    let status = tokio::process::Command::new("zip")
        .arg("-r").arg(&tmp_export_zip).arg(".")
        .arg("-x").arg("node_modules/*").arg(".npm/*").arg("app.log").arg("run.pid")
        .current_dir(&q.base_dir).status().await;

    if let Ok(s) = status {
        if s.success() {
            if let Ok(bytes) = tokio::fs::read(&tmp_export_zip).await {
                let _ = tokio::fs::remove_file(&tmp_export_zip).await;
                return Ok(Response::builder().status(200).header("Content-Type", "application/zip").body(axum::body::Body::from(bytes)).unwrap());
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
        if name == "node_modules" || name == ".npm" || name == "run.pid" || name == "app.log" { continue; }
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
    if payload.r#type.unwrap_or_default() == "folder" { let _ = tokio::fs::create_dir_all(&target_path).await; }
    else { let _ = tokio::fs::write(&target_path, "").await; }
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
    } else { Err(StatusCode::BAD_REQUEST) }
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

// ============================================================================
// 🔄 AUTOMATED INFRASTRUCTURE RECOVERY DAEMON LOOP (With Deep Fault Logs)
// ============================================================================
async fn auto_recover_volume_projects(state: Arc<WorkerState>) {
    tokio::time::sleep(Duration::from_secs(5)).await;
    println!("🔄 [DEBUG NODEJS WORKER] Auto-recovery daemon grid active. Scanning infrastructure database...");
    
    // 🌟 وی آئی پی سرجیکل فکس: '=', LOWER کو بدل کر اب LIKE '%node%' کر دیا ہے!
    // اب پرانے پروجیکٹس جن کا نام ڈیٹا بیس میں 'Node.js' یا 'Node' سیو تھا، وہ ۱۰۰٪ اسکین ہو کر آٹو ریکور ہوں گے!
    let query = "SELECT id, user_id, port FROM projects WHERE (LOWER(language) LIKE '%node%' OR LOWER(language) = 'js' OR LOWER(language) = 'javascript') AND status = 'Online'";
    
    match sqlx::query(query).fetch_all(&state.pg_pool).await {
        Ok(rows) => {
            println!("🔄 [DEBUG NODEJS WORKER] Scan complete. Found {} stranded online Node.js containers to recover.", rows.len());
            let client = reqwest::Client::new();
            for r in rows {
                let p_id: i32 = r.get("id"); 
                let u_id: i32 = r.get("user_id"); 
                let port: i32 = r.get("port");
                
                println!("🔄 [DEBUG NODEJS WORKER] Dispatched hot booting signal sequence for Proj ID: {}", p_id);
                let _ = client.post("http://127.0.0.1:8086/api/worker/start")
                    .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
                    .json(&serde_json::json!({ 
                        "project_id": p_id.to_string(), 
                        "user_id": u_id, 
                        "base_dir": format!("/app/data/user_{}/project_{}", u_id, p_id), 
                        "port": port, 
                        "action": "start" 
                    })).send().await;
            }
        },
        Err(e) => {
            println!("❌ [DEBUG NODEJS WORKER] CRITICAL: Auto-recovery loop query interrupted! DB Error: {:?}", e);
        }
    }
}

// ============================================================================
// 🔍 REAL-TIME RESOURCE UTILITIES (Missing System Metrics Scanner)
// ============================================================================
fn get_jail_ram_usage(uid: u32) -> u64 {
    let mut sys = sysinfo::System::new();
    sys.refresh_all();
    let mut total_memory = 0;
    for (_pid, process) in sys.processes() {
        if let Some(p_uid) = process.user_id() {
            if p_uid.to_string() == uid.to_string() { 
                total_memory += process.memory(); 
            }
        }
    }
    total_memory / (1024 * 1024)
}

fn get_dir_size(path: &std::path::Path) -> u64 {
    let mut total_size = 0;
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() { 
                total_size += get_dir_size(&p); 
            } else if let Ok(meta) = entry.metadata() { 
                total_size += meta.len(); 
            }
        }
    }
    total_size / (1024 * 1024)
}
