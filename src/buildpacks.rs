use axum::{
    routing::get,
    extract::{State, Path},
    http::{StatusCode, HeaderMap},
    Json,
    response::Response,
};
use axum::extract::Multipart; 
use sqlx::Row;
use std::time::Instant;
use std::collections::HashMap;
use std::io::Write;
use std::process::Stdio;
use futures_util::stream::StreamExt;
use tokio::io::{AsyncBufReadExt, BufReader, AsyncWriteExt};

use crate::AppState;

pub const INTERNAL_CLUSTER_SECRET_HEADER: &str = "x-internal-cluster-secret";
pub const INTERNAL_CLUSTER_SECRET_VALUE: &str = "SilentClusterSecret2026";

pub const PYTHON_WORKER_URL: &str = "http://silent-python:8085/api/worker";
pub const NODEJS_WORKER_URL: &str = "http://silent-nodejs:8086/api/worker";
pub const GOLANG_WORKER_URL: &str = "http://silent-golang:8087/api/worker";

pub fn get_worker_base_url(language: &str) -> Option<&'static str> {
    let lang = language.to_lowercase();
    if lang.contains("python") {
        Some(PYTHON_WORKER_URL)
    } else if lang.contains("node") || lang.contains("javascript") || lang.contains("js") {
        Some(NODEJS_WORKER_URL)
    } else if lang.contains("go") || lang.contains("golang") {
        Some(GOLANG_WORKER_URL)
    } else {
        None
    }
}

pub static RUST_BUILD_SEMAPHORE: once_cell::sync::Lazy<tokio::sync::Semaphore> = 
    once_cell::sync::Lazy::new(|| tokio::sync::Semaphore::new(5)); 

pub static OTHER_BUILD_SEMAPHORE: once_cell::sync::Lazy<tokio::sync::Semaphore> = 
    once_cell::sync::Lazy::new(|| tokio::sync::Semaphore::new(10)); 

pub static USERADD_MUTEX: once_cell::sync::Lazy<tokio::sync::Mutex<()>> = 
    once_cell::sync::Lazy::new(|| tokio::sync::Mutex::new(()));

pub static ACTIVE_BUILDS: once_cell::sync::Lazy<tokio::sync::Mutex<HashMap<i32, ActiveBuild>>> = 
    once_cell::sync::Lazy::new(|| tokio::sync::Mutex::new(HashMap::new()));

pub static TOTAL_SUCCESS_BUILDS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static TOTAL_FAILED_BUILDS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

pub const TG_BOT_TOKEN: &str = "8940591240:AAFgkoyuHqivL1xj6QeQId-awlunVj-kJxQ";
pub const TG_CHAT_ID: &str = "8167904992";
pub const TG_MESSAGE_ID_FILE: &str = "/app/data/tg_monitor_msg.id";

pub struct ActiveBuild {
    pub username: String,
    pub project_name: String,
    pub language: String,
    pub start_time: Instant,
}

#[derive(serde::Deserialize)]
pub struct ActionReq {
    pub action: String,
    pub new_name: Option<String>,
    pub status: Option<String>,
    pub new_password: Option<String>,
}

#[derive(serde::Serialize)]
pub struct ApiResponse {
    pub status: String,
    pub message: String,
    pub role: Option<String>,
}

pub async fn trigger_telegram_dashboard(state: &AppState) {
    let client = reqwest::Client::new();
    update_live_dashboard_message(state, &client).await;
}

pub async fn start_telegram_bot_daemon(state: AppState) {
    let client = reqwest::Client::new();
    let mut last_update_id: i64 = 0;
    let mut last_dashboard_update = std::time::Instant::now();

    let _ = tokio::fs::remove_file(TG_MESSAGE_ID_FILE).await;
    update_live_dashboard_message(&state, &client).await;

    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;

        if last_dashboard_update.elapsed().as_secs() >= 30 {
            update_live_dashboard_message(&state, &client).await;
            last_dashboard_update = std::time::Instant::now();
        }

        let get_updates_url = format!(
            "https://api.telegram.org/bot{}/getUpdates?offset={}&timeout=2",
            TG_BOT_TOKEN, last_update_id + 1
        );

        if let Ok(res) = client.get(&get_updates_url).send().await {
            if let Ok(json_body) = res.json::<serde_json::Value>().await {
                if let Some(updates) = json_body["result"].as_array() {
                    for update in updates {
                        if let Some(update_id_val) = update["update_id"].as_i64() { last_update_id = update_id_val; }

                        if let Some(message) = update["message"].as_object() {
                            if let (Some(chat_id), Some(text)) = (message["chat"]["id"].as_i64(), message["text"].as_str()) {
                                let incoming_cmd = text.trim();

                                if incoming_cmd.starts_with("/start") {
                                    let welcome_text = "🌟 *Silent Hosting Admin Bot Active.*\n==================================\nUse `/chk` command to pull instant cluster telemetry array.";
                                    let _ = client.post(&format!("https://api.telegram.org/bot{}/sendMessage", TG_BOT_TOKEN))
                                        .json(&serde_json::json!({ "chat_id": chat_id, "text": welcome_text, "parse_mode": "Markdown" })).send().await;
                                }
                                else if incoming_cmd.starts_with("/chk") {
                                    let total_online: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE status IN ('Online', 'Starting', 'Building')").fetch_one(&state.pg_pool).await.unwrap_or(0);
                                    let total_crashed: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE status = 'Crashed'").fetch_one(&state.pg_pool).await.unwrap_or(0);
                                    let total_offline: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE status = 'Offline'").fetch_one(&state.pg_pool).await.unwrap_or(0);

                                    let chk_reply = format!(
                                        "📊 *Instant Cluster Status Pull*\n======================\n🟢 Live Online : `{}` Nodes\n🔴 Crashed Jails: `{}` Nodes\n⚪ Offline/Idle : `{}` Nodes",
                                        total_online, total_crashed, total_offline
                                    );
                                    let _ = client.post(&format!("https://api.telegram.org/bot{}/sendMessage", TG_BOT_TOKEN))
                                        .json(&serde_json::json!({ "chat_id": chat_id, "text": chk_reply, "parse_mode": "Markdown" })).send().await;
                                }
                                else if incoming_cmd.starts_with("/help") {
                                    let help_text = "🛠️ *CLUSTER COMMAND MENU*\n==================================\n`/start` - Initialize bot handshake\n`/chk`   - Force instant cluster status pull";
                                    let _ = client.post(&format!("https://api.telegram.org/bot{}/sendMessage", TG_BOT_TOKEN))
                                        .json(&serde_json::json!({ "chat_id": chat_id, "text": help_text, "parse_mode": "Markdown" })).send().await;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

pub async fn generate_cluster_telemetry_text(state: &AppState) -> String {
    let total_online: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE status IN ('Online', 'Starting', 'Building')").fetch_one(&state.pg_pool).await.unwrap_or(0);
    let total_crashed: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE status = 'Crashed'").fetch_one(&state.pg_pool).await.unwrap_or(0);
    let total_offline: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE status = 'Offline'").fetch_one(&state.pg_pool).await.unwrap_or(0);

    let builds = ACTIVE_BUILDS.lock().await;
    let mut build_logs = String::new();
    if builds.is_empty() {
        build_logs.push_str("   🟢 No active builds in compile zone.\n");
    } else {
        for (index, (_, b)) in builds.iter().enumerate() {
            let elapsed = b.start_time.elapsed().as_secs() / 60;
            build_logs.push_str(&format!("   {}. 🏗️ User: `{}`, Project: `{}`, Lang: `{}` [🕒 {} min active]\n", index + 1, b.username, b.project_name, b.language, elapsed));
        }
    }

    let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
    let (mut wait_rust, mut wait_node, mut wait_py, mut wait_go) = (0, 0, 0, 0);
    if let Ok(mut cursor) = mongo_coll.find(mongodb::bson::doc! { "status": "Building" }).await {
        while let Some(Ok(doc)) = cursor.next().await {
            if let Some(lang) = doc.get_str("language").ok() {
                match lang.to_lowercase().as_str() { 
                    "rust" | "rs" => wait_rust += 1, 
                    "node" | "js" => wait_node += 1, 
                    "python" | "py" => wait_py += 1, 
                    "go" | "golang" => wait_go += 1, 
                    _ => {} 
                }
            }
        }
    }
    let total_waiting = wait_rust + wait_node + wait_py + wait_go;

    let permits_rust = RUST_BUILD_SEMAPHORE.available_permits();
    let permits_other = OTHER_BUILD_SEMAPHORE.available_permits();

    let pkt_time = chrono::Utc::now() + chrono::Duration::hours(5);
    let current_sync_time = pkt_time.format("%I:%M:%S %p PKT (%d-%m-%Y)").to_string();

    format!(
        "💎 🌟 *SILENT HOSTING CLUSTER CORE MONITOR* 🌟 💎\n==========================================\n\n\
         📊 *INFRASTRUCTURE SLOTS MATRIX*:\n\
         🦀 Rust Build Slots   : `{}/5 Available`\n\
         🌐 Other Build Slots  : `{}/10 Available`\n\
         🟢 Live Online Apps   : `{}` Active Sandbox Jails\n\
         🔴 Crashed Failed Apps: `{}` Failed Sandbox Jails\n\
         ⚪ Offline Sleeping Apps: `{}` Sleeping Sandbox Jails\n\n\
         🏗️ *CURRENT COMPILER OPERATIONS*:\n\
         {}\n\
         ⏳ *WAITING QUEUE BREAKDOWN*:\n\
         👥 Total In Queue     : `{}` Users Waiting\n\
         |-- 🦀 Rust : `{}` | |-- 🟢 Node.js : `{}`\n\
         |-- 🐍 Python : `{}` | |-- 🐹 Golang : `{}`\n\n\
         📈 *PLATFORM PERFORMANCE RATIO*:\n\
         ✅ Success Builds : `{}` | ❌ Failed Builds : `{}`\n==========================================\n\
         🕒 *Last Core Sync: {}*",
        permits_rust, permits_other, total_online, total_crashed, total_offline,
        build_logs, total_waiting, wait_rust, wait_node, wait_py, wait_go, 
        TOTAL_SUCCESS_BUILDS.load(std::sync::atomic::Ordering::Relaxed), 
        TOTAL_FAILED_BUILDS.load(std::sync::atomic::Ordering::Relaxed), 
        current_sync_time
    )
}

pub async fn update_live_dashboard_message(state: &AppState, client: &reqwest::Client) {
    let dashboard_text = generate_cluster_telemetry_text(state).await;

    if let Ok(msg_id) = tokio::fs::read_to_string(TG_MESSAGE_ID_FILE).await {
        let edit_url = format!("https://api.telegram.org/bot{}/editMessageText", TG_BOT_TOKEN);
        if let Ok(res) = client.post(&edit_url).json(&serde_json::json!({
            "chat_id": TG_CHAT_ID,
            "message_id": msg_id.trim().parse::<i32>().unwrap_or(0),
            "text": dashboard_text,
            "parse_mode": "Markdown"
        })).send().await {
            let status = res.status();
            if status.is_success() { return; }

            let res_text = res.text().await.unwrap_or_default();
            if res_text.contains("message is not modified") { return; }
            if res_text.contains("message to edit not found") { let _ = tokio::fs::remove_file(TG_MESSAGE_ID_FILE).await; } 
            else { return; }
        }
    }

    let send_url = format!("https://api.telegram.org/bot{}/sendMessage", TG_BOT_TOKEN);
    if let Ok(res) = client.post(&send_url).json(&serde_json::json!({ "chat_id": TG_CHAT_ID, "text": dashboard_text, "parse_mode": "Markdown" })).send().await {
        if let Ok(json) = res.json::<serde_json::Value>().await {
            if let Some(id) = json["result"]["message_id"].as_i64() { let _ = tokio::fs::write(TG_MESSAGE_ID_FILE, id.to_string()).await; }
        }
    }
}

pub fn spawn_security_watchdog(
    stderr: tokio::process::ChildStderr,
    project_id: i32,
    _username: String,
    base_dir: String,
    port: i32,
    state: AppState,
) {
    let bd_clone = base_dir.clone(); let state_clone = state.clone();

    tokio::spawn(async move {
        loop {
            tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;
            let mut limit_mb = 500;
            let row = sqlx::query("SELECT storage_total FROM projects WHERE id = $1").bind(project_id).fetch_one(&state_clone.pg_pool).await;
            if let Ok(r) = row { limit_mb = r.get("storage_total"); }

            let current_size = crate::get_dir_size(&bd_clone).unwrap_or(0);
            if current_size > (limit_mb as u64 * 1024 * 1024) {
                kill_room_surgical(&bd_clone, port, project_id).await;
                update_project_status_all(&state_clone, project_id, "Suspended").await;

                if let Ok(mut conn) = state_clone.redis_client.get_multiplexed_tokio_connection().await {
                    let log_key = format!("project:{}:history_logs", project_id);
                    let channel_name = format!("project:{}:updates", project_id);
                    let alert = "⚠️ [NOTICE] Storage quota exceeded. Application paused for server safety.\n[STATUS_UPDATE] Suspended\n";
                    let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(alert).query_async(&mut conn).await;
                    let msg = serde_json::json!({ "project_id": project_id, "type": "log_update", "value": alert.trim() }).to_string();
                    let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut conn).await;
                }
                trigger_telegram_dashboard(&state_clone).await; break;
            }
        }
    });

    tokio::spawn(async move {
        use tokio::io::AsyncBufReadExt;
        let mut reader = tokio::io::BufReader::new(stderr).lines(); let mut violation_count = 0;
        while let Ok(Some(line)) = reader.next_line().await {
            let lower_line = line.to_lowercase();
            if lower_line.contains("permission denied") && (lower_line.contains("/proc") || lower_line.contains("/sys") || lower_line.contains("/root") || lower_line.contains("/app/data")) {
                violation_count += 1;
                if violation_count >= 50 {
                    kill_room_surgical(&base_dir, port, project_id).await;
                    update_project_status_all(&state, project_id, "Suspended").await;

                    if let Ok(mut conn) = state.redis_client.get_multiplexed_tokio_connection().await {
                        let log_key = format!("project:{}:history_logs", project_id);
                        let channel_name = format!("project:{}:updates", project_id);
                        let alert = "⚠️ [SECURITY] Unstable background access attempt blocked. Application isolated for safety.\n[STATUS_UPDATE] Suspended\n";
                        let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(alert).query_async(&mut conn).await;
                        let msg = serde_json::json!({ "project_id": project_id, "type": "log_update", "value": alert.trim() }).to_string();
                        let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut conn).await;
                    }
                    trigger_telegram_dashboard(&state).await; break;
                }
            }
        }
    });
}

pub async fn create_project(State(state): State<AppState>, headers: HeaderMap, mut multipart: Multipart) -> (StatusCode, Json<serde_json::Value>) {

    let username = match crate::get_username_from_cookie(&headers) { 
        Some(u) => u, 
        None => {

            return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"status": "error", "message": "Unauthorized"})));
        } 
    };

    let user_row = sqlx::query("SELECT id, plan_type FROM users WHERE username = $1").bind(&username).fetch_one(&state.pg_pool).await.unwrap();
    let user_id: i32 = user_row.get::<i32, _>("id"); 
    let plan_type: String = user_row.get::<String, _>("plan_type");

    if plan_type == "none" { 

        return (StatusCode::FORBIDDEN, Json(serde_json::json!({"status": "error", "message": "No active plan found!"}))); 
    }
    let (ram_limit, storage_limit, _) = crate::get_plan_limits(&plan_type);

    let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
    let mut new_port = 8001;
    if let Ok(Some(max_doc)) = mongo_coll.find_one(mongodb::bson::Document::new()).sort(mongodb::bson::doc! { "port": -1 }).await {
        if let Some(p) = max_doc.get_i32("port").ok() { if p >= 8000 { new_port = p + 1; } }
    }
    loop { if std::net::TcpListener::bind(format!("127.0.0.1:{}", new_port)).is_ok() { break; } new_port += 1; }

    let (mut name, mut runtime, mut build_cmd, mut start_cmd) = (String::new(), String::new(), String::new(), String::new());
    let mut proj_id: Option<i32> = None;
    let mut base_dir = String::new();
    let mut user_home = format!("/app/data/user_{}", user_id);
    let mut uploaded_zip_files = Vec::new();

    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        let field_name = field.name().unwrap_or("").to_string();

        if field_name == "name" { name = field.text().await.unwrap_or_default(); }
        else if field_name == "runtime" { runtime = field.text().await.unwrap_or_default(); }
        else if field_name == "build_cmd" { build_cmd = field.text().await.unwrap_or_default(); }
        else if field_name == "start_cmd" { start_cmd = field.text().await.unwrap_or_default(); }
        else if field_name == "files[]" {

            if proj_id.is_none() {
                let check_cmd = |cmd: &str| -> bool { let l = cmd.to_lowercase(); !(l.contains("..") || l.contains("/app/data") || l.contains("/etc") || l.contains("/root")) };
                if !check_cmd(&build_cmd) || !check_cmd(&start_cmd) { 

                    return (StatusCode::FORBIDDEN, Json(serde_json::json!({"status": "error", "message": "Dangerous commands detected!"}))); 
                }
                if runtime == "HTML" && start_cmd.is_empty() { start_cmd = format!("python3 -m http.server {}", new_port); }

                let mut clean_lang = runtime.trim().to_lowercase();
                if clean_lang.contains("go") || clean_lang.contains("golang") { clean_lang = "go".to_string(); }
                else if clean_lang.contains("node") || clean_lang.contains("js") || clean_lang.contains("javascript") { clean_lang = "node".to_string(); }
                else if clean_lang.contains("python") { clean_lang = "python".to_string(); }

                let id: i32 = sqlx::query(
                    "INSERT INTO projects (user_id, name, runtime, language, build_cmd, start_cmd, ram_total, storage_total, port, status) \
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'Building') RETURNING id"
                )
                .bind(user_id).bind(&name).bind(&runtime).bind(&clean_lang).bind(&build_cmd).bind(&start_cmd).bind(ram_limit).bind(storage_limit).bind(new_port)
                .fetch_one(&state.pg_pool).await.unwrap().get::<i32, _>("id");

                let project_doc = mongodb::bson::doc! { "project_id": id, "user_id": user_id, "name": &name, "runtime": &runtime, "language": &clean_lang, "build_cmd": &build_cmd, "start_cmd": &start_cmd, "ram_total": ram_limit, "storage_total": storage_limit, "port": new_port, "status": "Building", "created_at": mongodb::bson::DateTime::now() };
                let _ = mongo_coll.insert_one(project_doc).await;

                update_project_status_all(&state, id, "Building").await;
                ensure_jail_user(id, user_id).await;

                base_dir = format!("{}/project_{}", user_home, id);
                let _ = tokio::fs::create_dir_all(&base_dir).await;
                proj_id = Some(id);
            }

            let filename = field.file_name().unwrap_or("unknown_source.zip").to_string();
            let file_path = format!("{}/{}", base_dir, filename);

            if let Ok(mut file) = tokio::fs::File::create(&file_path).await {
                let mut field_stream = field;
                while let Ok(Some(chunk)) = field_stream.chunk().await {

                    let _ = tokio::io::AsyncWriteExt::write_all(&mut file, &chunk).await;
                }
            }

            if filename.ends_with(".zip") {
                uploaded_zip_files.push(file_path);
            }
        }
    }

    let final_proj_id = match proj_id {
        Some(id) => id,
        None => {
            let mut clean_lang = runtime.trim().to_lowercase();
            if clean_lang.contains("go") || clean_lang.contains("golang") { clean_lang = "go".to_string(); }
            else if clean_lang.contains("node") || clean_lang.contains("js") || clean_lang.contains("javascript") { clean_lang = "node".to_string(); }
            else if clean_lang.contains("python") { clean_lang = "python".to_string(); }

            let id: i32 = sqlx::query("INSERT INTO projects (user_id, name, runtime, language, build_cmd, start_cmd, ram_total, storage_total, port, status) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'Building') RETURNING id").bind(user_id).bind(&name).bind(&runtime).bind(&clean_lang).bind(&build_cmd).bind(&start_cmd).bind(ram_limit).bind(storage_limit).bind(new_port).fetch_one(&state.pg_pool).await.unwrap().get::<i32, _>("id");
            base_dir = format!("{}/project_{}", user_home, id);
            let _ = tokio::fs::create_dir_all(&base_dir).await;
            id
        }
    };

    for zip_path in uploaded_zip_files {
        let _ = tokio::process::Command::new("unzip").args(&["-o", &zip_path, "-d", &base_dir]).status().await;
        let _ = tokio::fs::remove_file(&zip_path).await;
    }

    let _ = tokio::process::Command::new("sh").arg("-c").arg(format!("cd {} && ITEM_COUNT=$(ls -1A | wc -l) && if [ \"$ITEM_COUNT\" -eq 1 ]; then ITEM_NAME=$(ls -1A); if [ -d \"$ITEM_NAME\" ]; then mv \"$ITEM_NAME\"/* . 2>/dev/null; mv \"$ITEM_NAME\"/.[!.]* . 2>/dev/null; rmdir \"$ITEM_NAME\"; fi; fi", base_dir)).status().await;

    let sys_user = format!("u_jail_p{}", final_proj_id);
    let _ = std::process::Command::new("chmod").args(&["711", &user_home]).status();
    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
    let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

    if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
        let log_key = format!("project:{}:history_logs", final_proj_id);
        let channel_name = format!("project:{}:updates", final_proj_id);
        let init_log = format!("[SYSTEM] Project created successfully! Allocated {}MB RAM & {}MB Storage. Preparing workspace...\n", ram_limit, storage_limit);
        let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(&init_log).query_async(&mut redis_conn).await;
        let msg = serde_json::json!({ "project_id": final_proj_id, "type": "log_update", "value": init_log }).to_string();
        let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut redis_conn).await;
    }

    let mut clean_lang = runtime.trim().to_lowercase();
    if clean_lang.contains("go") || clean_lang.contains("golang") { clean_lang = "go".to_string(); }
    else if clean_lang.contains("node") || clean_lang.contains("js") || clean_lang.contains("javascript") { clean_lang = "node".to_string(); }
    else if clean_lang.contains("python") { clean_lang = "python".to_string(); }

    if let Some(base_url) = get_worker_base_url(&clean_lang) {
        let client = reqwest::Client::new();

        let create_endpoint = format!("{}/create", base_url);
        let start_endpoint = format!("{}/start", base_url);

        let tmp_zip = format!("/tmp/create_sync_{}.zip", final_proj_id);
        let _ = tokio::process::Command::new("zip")
            .arg("-r").arg(&tmp_zip).arg(".")
            .arg("-x").arg("node_modules/*").arg("venv/*").arg(".venv/*").arg("target/*").arg("app.log").arg("run.pid")
            .current_dir(&base_dir).status().await;

        if let Ok(zip_bytes) = tokio::fs::read(&tmp_zip).await {
            let form_part = reqwest::multipart::Part::bytes(zip_bytes).file_name("source.zip").mime_str("application/zip").unwrap();
            let form = reqwest::multipart::Form::new()
                .text("project_id", final_proj_id.to_string())
                .text("user_id", user_id.to_string())
                .text("base_dir", base_dir.clone())
                .text("port", new_port.to_string())
                .part("files[]", form_part);

            let state_clone = state.clone();
            tokio::spawn(async move {
                match client.post(&create_endpoint)
                    .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE) 
                    .multipart(form).send().await 
                {
                    Ok(res) => {
                        let status_code = res.status();
                        let raw_body_text = res.text().await.unwrap_or_else(|_| "Unreadable Payload String".to_string());

                        if status_code.is_success() && (raw_body_text.contains("success") || raw_body_text.contains("\"success\"")) {
                            let worker_payload = serde_json::json!({ "project_id": final_proj_id.to_string(), "user_id": user_id, "base_dir": base_dir, "port": new_port, "action": "start" });
                            let _ = client.post(&start_endpoint)
                                .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
                                .json(&worker_payload).send().await;

                            let _ = tokio::fs::remove_dir_all(&base_dir).await;
                        } else {
                            update_project_status_all(&state_clone, final_proj_id, "Crashed").await;
                        }
                    },
                    Err(_) => {
                        update_project_status_all(&state_clone, final_proj_id, "Crashed").await;
                    }
                }
            });
        }
        let _ = tokio::fs::remove_file(&tmp_zip).await;
    } else {
        dispatch_buildpack_stream(state, clean_lang, runtime, start_cmd, final_proj_id, user_id, base_dir, new_port);
    }

    (StatusCode::OK, Json(serde_json::json!({ "status": "success", "project_id": final_proj_id.to_string() })))
}

pub async fn handle_project_action(State(state): State<AppState>, headers: HeaderMap, Path(proj_id_str): Path<String>, Json(payload): Json<ActionReq>) -> Result<Json<ApiResponse>, StatusCode> {

    let _username = crate::get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let proj_id = proj_id_str.parse::<i32>().map_err(|_| StatusCode::BAD_REQUEST)?;
    let project_doc = match migrate_or_get_project(&state, proj_id).await { Some(doc) => doc, None => return Err(StatusCode::NOT_FOUND) };

    let user_id = project_doc.get_i32("user_id").unwrap_or(0); 
    let port = project_doc.get_i32("port").unwrap_or(0);
    let language = project_doc.get_str("language").unwrap_or("node").to_string().to_lowercase();
    let runtime = project_doc.get_str("runtime").unwrap_or("").to_string();
    let start_cmd = project_doc.get_str("start_cmd").unwrap_or("").to_string();
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, proj_id);

    let mut current_lang = language.clone();
    let client = reqwest::Client::new();

    match payload.action.as_str() {
        "start" | "redeploy" => {
            let is_redeploy = payload.action == "redeploy"; 
            let status_val = if is_redeploy { "Building" } else { "Starting" };

            if tokio::fs::read_dir(&base_dir).await.is_ok() {

                let mut detected_lang = current_lang.clone();

                if tokio::fs::metadata(format!("{}/Cargo.toml", base_dir)).await.is_ok() { detected_lang = "rust".to_string(); } 
                else if tokio::fs::metadata(format!("{}/package.json", base_dir)).await.is_ok() || tokio::fs::metadata(format!("{}/index.js", base_dir)).await.is_ok() || tokio::fs::metadata(format!("{}/server.js", base_dir)).await.is_ok() { detected_lang = "node".to_string(); } 
                else if tokio::fs::metadata(format!("{}/requirements.txt", base_dir)).await.is_ok() || tokio::fs::metadata(format!("{}/main.py", base_dir)).await.is_ok() { detected_lang = "python".to_string(); } 
                else if tokio::fs::metadata(format!("{}/go.mod", base_dir)).await.is_ok() || tokio::fs::metadata(format!("{}/main.go", base_dir)).await.is_ok() { detected_lang = "go".to_string(); } 
                else if tokio::fs::metadata(format!("{}/index.php", base_dir)).await.is_ok() { detected_lang = "php".to_string(); } 
                else if tokio::fs::metadata(format!("{}/index.html", base_dir)).await.is_ok() { detected_lang = "html".to_string(); }

                if detected_lang != current_lang && !detected_lang.is_empty() {

                    current_lang = detected_lang;
                    let _ = sqlx::query("UPDATE projects SET language = $1 WHERE id = $2").bind(&current_lang).bind(proj_id).execute(&state.pg_pool).await;
                    let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
                    let _ = mongo_coll.update_one(mongodb::bson::doc! { "project_id": proj_id }, mongodb::bson::doc! { "$set": { "language": &current_lang } }).await;
                }
            }

            if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
                let log_key = format!("project:{}:history_logs", proj_id);
                let channel_name = format!("project:{}:updates", proj_id);
                let action_log = if is_redeploy { "\n🔄 [SYSTEM] Redeployment triggered! Rebuilding environment...\n" } else { "\n⚡ [SYSTEM] Start command received! Booting application...\n" };
                let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(action_log).query_async(&mut redis_conn).await;
                let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": action_log }).to_string();
                let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut redis_conn).await;
            }

            if let Some(worker_base_url) = get_worker_base_url(&current_lang) {
                update_project_status_all(&state, proj_id, status_val).await;

                if tokio::fs::read_dir(&base_dir).await.is_ok() {
                    let tmp_zip = format!("/tmp/migrate_{}.zip", proj_id);
                    let _ = tokio::process::Command::new("zip")
                        .arg("-r").arg(&tmp_zip).arg(".")
                        .arg("-x").arg("node_modules/*").arg("venv/*").arg(".venv/*").arg("target/*").arg("app.log").arg("run.pid")
                        .current_dir(&base_dir).status().await;

                    if let Ok(zip_bytes) = tokio::fs::read(&tmp_zip).await {
                        let create_url = format!("{}/create", worker_base_url);
                        let form_part = reqwest::multipart::Part::bytes(zip_bytes).file_name("source.zip").mime_str("application/zip").unwrap();
                        let form = reqwest::multipart::Form::new().text("project_id", proj_id.to_string()).text("user_id", user_id.to_string()).text("base_dir", base_dir.clone()).text("port", port.to_string()).part("files[]", form_part);

                        match client.post(&create_url).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).multipart(form).send().await {
                            Ok(res) => {
                                let status_code = res.status();
                                let raw_body_dump = res.text().await.unwrap_or_default();
                                if status_code.is_success() && (raw_body_dump.contains("success") || raw_body_dump.contains("\"success\"")) {

                                    let _ = tokio::fs::remove_dir_all(&base_dir).await;
                                }
                            },
                            Err(err) => println!("❌ [CLUSTER RAW LOG] Offloading link transmission error context: {:?}", err)
                        }
                    }
                    let _ = tokio::fs::remove_file(&tmp_zip).await;
                }

                let endpoint = if is_redeploy { "/redeploy" } else { "/start" };
                let worker_url = format!("{}{}", worker_base_url, endpoint);

                let worker_payload = serde_json::json!({ "project_id": proj_id.to_string(), "user_id": user_id, "base_dir": base_dir, "port": port, "action": payload.action });

                match client.post(&worker_url).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).json(&worker_payload).send().await {
                    Ok(res) => {

                    },
                    Err(e) => {

                        update_project_status_all(&state, proj_id, "Crashed").await;
                    }
                }
            } else {

                let _ = tokio::fs::create_dir_all(&base_dir).await;
                kill_room_surgical(&base_dir, port, proj_id).await;
                if is_redeploy { let _ = tokio::fs::remove_file(format!("{}/silent_app_bin", base_dir)).await; }
                update_project_status_all(&state, proj_id, status_val).await;
                dispatch_buildpack_stream(state, current_lang, runtime, start_cmd, proj_id, user_id, base_dir, port);
            }
        },
        "stop" => {
            if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
                let log_key = format!("project:{}:history_logs", proj_id);
                let channel_name = format!("project:{}:updates", proj_id);
                let stop_log = "\n🛑 [SYSTEM] Stop command triggered! Suspending active infrastructure nodes safely...\n";
                let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(stop_log).query_async(&mut redis_conn).await;
                let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": stop_log }).to_string();
                let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut redis_conn).await;
            }

            if let Some(worker_base_url) = get_worker_base_url(&current_lang) {
                let worker_url = format!("{}/stop", worker_base_url);
                let worker_payload = serde_json::json!({ "project_id": proj_id.to_string(), "user_id": user_id, "base_dir": base_dir, "port": port, "action": payload.action });

                match client.post(&worker_url).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).json(&worker_payload).send().await {
                    Ok(res) => println!("🔍 [CLUSTER RAW LOG] Stop response status: {}", res.status()),
                    Err(e) => println!("❌ [CLUSTER RAW LOG] Stop network connection failure: {:?}", e)
                }
                update_project_status_all(&state, proj_id, "Offline").await;
                trigger_telegram_dashboard(&state).await;
            } else {
                kill_room_surgical(&base_dir, port, proj_id).await;
                update_project_status_all(&state, proj_id, "Offline").await;
                trigger_telegram_dashboard(&state).await;
            }
        },
        "rename" => {
            if let Some(new_name) = payload.new_name {
                let _ = sqlx::query("UPDATE projects SET name = $1 WHERE id = $2").bind(&new_name).bind(proj_id).execute(&state.pg_pool).await;
                let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
                let _ = mongo_coll.update_one(mongodb::bson::doc! { "project_id": proj_id }, mongodb::bson::doc! { "$set": { "name": new_name } }).await;
            }
        },
        "delete" => {
            if let Some(worker_base_url) = get_worker_base_url(&current_lang) {
                let worker_url = format!("{}/stop", worker_base_url);
                let worker_payload = serde_json::json!({ "project_id": proj_id.to_string(), "user_id": user_id, "base_dir": base_dir, "port": port, "action": payload.action });
                let _ = client.post(&worker_url).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).json(&worker_payload).send().await;
            } else {
                kill_room_surgical(&base_dir, port, proj_id).await;
            }

            if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await { 
                let _: Result<(), _> = redis::cmd("DEL").arg(format!("project:{}:history_logs", proj_id)).query_async(&mut redis_conn).await;
                let _: Result<(), _> = redis::cmd("DEL").arg(format!("project:{}:status", proj_id)).query_async(&mut redis_conn).await; 
            }

            let _ = sqlx::query("DELETE FROM projects WHERE id = $1").bind(proj_id).execute(&state.pg_pool).await;
            let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
            let _ = mongo_coll.delete_one(mongodb::bson::doc! { "project_id": proj_id }).await;

            let _ = tokio::fs::remove_dir_all(&base_dir).await;
            trigger_telegram_dashboard(&state).await;
        },
        _ => return Err(StatusCode::BAD_REQUEST),
    }
    Ok(Json(ApiResponse { status: "success".to_string(), message: "Action executed successfully.".to_string(), role: None }))
}

pub async fn auto_recover_projects(state: AppState) {
    let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
    let clean_query = mongodb::bson::doc! { "status": { "$in": ["Building", "Starting"] } };

    let _ = mongo_coll.update_many(clean_query.clone(), mongodb::bson::doc! { "$set": { "status": "Crashed" } }).await;

    let mut total_fail_count = 0;
    if let Ok(res) = sqlx::query("UPDATE projects SET status = 'Crashed' WHERE status IN ('Building', 'Starting')").execute(&state.pg_pool).await {
        total_fail_count = res.rows_affected();
    }

    if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
        if let Ok(Some(rows)) = sqlx::query("SELECT id FROM projects WHERE status = 'Crashed'").fetch_all(&state.pg_pool).await.map(|r| Some(r)) {
            for row in rows {
                let p_id: i32 = row.get("id");
                let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", p_id)).arg("Crashed").query_async(&mut redis_conn).await;
            }
        }
    }

    let _ = tokio::process::Command::new("sh").arg("-c").arg("mkdir -p /app/data/global_cache/cargo /app/data/global_cache/npm /app/data/global_cache/python /app/data/global_cache/ms-playwright /app/data/global_cache/go_cache /app/data/global_cache/go_mod /app/data/global_cache/rust_deps; chmod -R 777 /app/data/global_cache 2>/dev/null || true").status().await;

    let filter = mongodb::bson::doc! { "status": "Online" };
    let mut cursor = match mongo_coll.find(filter).await { Ok(c) => c, Err(_) => return };

    let mut total_online_count = 0;
    let mut total_success_count = 0;

    while cursor.advance().await.unwrap_or(false) {
        if let Ok(doc) = cursor.deserialize_current() {
            let language = doc.get_str("language").unwrap_or("node").to_string().to_lowercase();

            if language == "python" || language.contains("node") || language.contains("javascript") || language.contains("js") || language == "go" || language == "golang" {
                continue;
            }

            total_online_count += 1;
            let id = doc.get_i32("project_id").unwrap_or(0); 
            let user_id = doc.get_i32("user_id").unwrap_or(0);

            let owner_username: String = sqlx::query_scalar("SELECT username FROM users WHERE id = $1").bind(user_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
            if owner_username.is_empty() { continue; }

            let exp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as usize + 60;
            let token = jsonwebtoken::encode(&jsonwebtoken::Header::default(), &crate::Claims { sub: owner_username, role: "user".to_string(), exp }, &jsonwebtoken::EncodingKey::from_secret(crate::SECRET_KEY)).unwrap();

            let mut forged_headers = axum::http::HeaderMap::new();
            forged_headers.insert(axum::http::header::COOKIE, axum::http::HeaderValue::from_str(&format!("silent_session={}", token)).unwrap());

            let action_payload = ActionReq { action: "start".to_string(), new_password: None, status: None, new_name: None };

            let _ = handle_project_action(axum::extract::State(state.clone()), forged_headers, axum::extract::Path(id.to_string()), axum::Json(action_payload)).await;
            total_success_count += 1;
            tokio::time::sleep(std::time::Duration::from_millis(1000)).await;
        }
    }

    let mut crash_report = String::new();
    crash_report.push_str("=====================================================\n");
    crash_report.push_str("⚠️   SILENT HOSTING SYSTEM: GLOBAL CRASH REPORT MATRIX   ⚠️\n");
    crash_report.push_str("=====================================================\n\n");

    if let Ok(crashed_rows) = sqlx::query("SELECT id, user_id, name, language FROM projects WHERE status = 'Crashed'").fetch_all(&state.pg_pool).await {
        for row in crashed_rows {
            let p_id: i32 = row.get("id"); let u_id: i32 = row.get("user_id"); let p_name: String = row.get("name"); let p_lang: String = row.get("language");
            crash_report.push_str("-----------------------------------------------------\n");
            crash_report.push_str(&format!("📦 PROJECT: {} (ID: {}) | 👤 USER ID: {} | ⚙️ LANG: {}\n", p_name, p_id, u_id, p_lang));
            crash_report.push_str("-----------------------------------------------------\n");

            let mut fetched_log = String::new();
            if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
                let log_key = format!("project:{}:history_logs", p_id);
                if let Ok(lines) = redis::cmd("LRANGE").arg(&log_key).arg(-20).arg(-1).query_async::<Vec<String>>(&mut redis_conn).await {
                    if !lines.is_empty() { fetched_log = lines.join("\n"); }
                }
            }

            if !fetched_log.is_empty() { crash_report.push_str(&fetched_log); } 
            else { crash_report.push_str("[SYSTEM] No log history available for this project yet.\n"); }
            crash_report.push_str("\n\n");
        }
    }

    let report_path = "/tmp/cluster_crash_report.txt";
    if tokio::fs::write(report_path, &crash_report).await.is_ok() {
        if let Ok(file_bytes) = tokio::fs::read(report_path).await {
            let client = reqwest::Client::new();
            let part = reqwest::multipart::Part::bytes(file_bytes).file_name("cluster_crash_report.txt").mime_str("text/plain").unwrap();
            let form = reqwest::multipart::Form::new()
                .text("chat_id", TG_CHAT_ID.to_string())
                .text("caption", format!("🔄 *[AUTO RECOVER COMPLETION SUMMARY]*\n\n🟢 Online Found: `{}`\n✅ Successfully Routed: `{}`\n🔴 Reset Stuck: `{}`\n\n📂 لاگ رپورٹ کلسٹر سے کامیابی کے ساتھ اٹیچ کر دی گئی ہے!", total_online_count, total_success_count, total_fail_count))
                .text("parse_mode", "Markdown")
                .part("document", part);

            let doc_url = format!("https://api.telegram.org/bot{}/sendDocument", TG_BOT_TOKEN);
            let _ = client.post(&doc_url).multipart(form).send().await;
        }
        let _ = tokio::fs::remove_file(report_path).await;
    }
    trigger_telegram_dashboard(&state).await;
}

pub async fn ensure_jail_user(proj_id: i32, user_id: i32) {
    let sys_user = format!("u_jail_p{}", proj_id);
    let sys_uid = 10000 + proj_id;
    let _lock = USERADD_MUTEX.lock().await;

    let check = tokio::process::Command::new("id").arg("-u").arg(&sys_user).output().await;
    if let Ok(out) = check { if out.status.success() { return; } }

    let _ = tokio::process::Command::new("groupadd").args(&["-g", &sys_uid.to_string(), &sys_user]).status().await;
    let _ = tokio::process::Command::new("useradd")
        .args(&["-u", &sys_uid.to_string(), "-g", &sys_user, "-M", "-d", &format!("/app/data/user_{}", user_id), "-s", "/bin/false", &sys_user])
        .status().await;

    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
}

pub async fn kill_room_surgical(base_dir: &str, port: i32, project_id: i32) {
    if port > 0 {
        let cmd = format!("fuser -k -9 {0}/tcp 2>/dev/null || lsof -ti:{0} 2>/dev/null | xargs -r kill -9 2>/dev/null", port);
        let _ = tokio::process::Command::new("sh").arg("-c").arg(&cmd).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().await;
    }
    let pid_path = format!("{}/run.pid", base_dir);
    if let Ok(pid_str) = tokio::fs::read_to_string(&pid_path).await {
        let pid = pid_str.trim();
        if !pid.is_empty() {
            let cmd = format!("kill -9 -{0} 2>/dev/null || kill -9 {0} 2>/dev/null", pid);
            let _ = tokio::process::Command::new("sh").arg("-c").arg(&cmd).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().await;
        }
    }
    let _ = tokio::process::Command::new("pkill").args(&["-9", "-f", base_dir]).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().await;

    if project_id > 0 {
        let sys_uid = 10000 + project_id;
        let _ = tokio::process::Command::new("pkill").args(&["-9", "-u", &sys_uid.to_string()]).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().await;
    }
    let _ = tokio::fs::remove_file(&pid_path).await;
}

pub async fn kill_room(base_dir: &str, port: i32) {
    kill_room_surgical(base_dir, port, 0).await;
}

pub async fn update_project_status_all(state: &AppState, proj_id: i32, status: &str) {
    let _ = sqlx::query("UPDATE projects SET status = $1 WHERE id = $2").bind(status).bind(proj_id).execute(&state.pg_pool).await;
    let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
    let _ = mongo_coll.update_one(mongodb::bson::doc! { "project_id": proj_id }, mongodb::bson::doc! { "$set": { "status": status } }).await;

    if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
        let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", proj_id)).arg(status).query_async(&mut redis_conn).await;
        let channel_name = format!("project:{}:updates", proj_id);
        let msg = serde_json::json!({ "project_id": proj_id, "type": "status_update", "value": status }).to_string();
        let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut redis_conn).await;
    }
}

pub async fn has_rust_code_changed(base_dir: &str, bin_time: std::time::SystemTime) -> bool {
    let mut stack = vec![base_dir.to_string()];
    while let Some(current_dir) = stack.pop() {
        if let Ok(mut entries) = tokio::fs::read_dir(&current_dir).await {
            while let Some(entry) = entries.next_entry().await.unwrap_or(None) {
                let path = entry.path(); 
                let file_name = entry.file_name().to_string_lossy().to_string();
                if file_name == "app.log" || file_name == "run.pid" || file_name == "silent_app_bin" || file_name == "target" || file_name.starts_with('.') { continue; }

                if path.is_dir() { stack.push(path.to_string_lossy().to_string()); } 
                else if file_name.ends_with(".rs") || file_name == "Cargo.toml" || file_name == "Cargo.lock" {
                    if let Ok(meta) = entry.metadata().await { 
                        if let Ok(mod_time) = meta.modified() { if mod_time > bin_time { return true; } } 
                    }
                }
            }
        }
    }
    false
}

pub async fn migrate_or_get_project(state: &AppState, proj_id: i32) -> Option<mongodb::bson::Document> {
    let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
    if let Ok(Some(doc)) = mongo_coll.find_one(mongodb::bson::doc! { "project_id": proj_id }).await { return Some(doc); }
    let old_data = sqlx::query("SELECT id, user_id, name, runtime, language, build_cmd, start_cmd, port, ram_total, storage_total FROM projects WHERE id = $1").bind(proj_id).fetch_optional(&state.pg_pool).await.unwrap_or(None);
    if let Some(row) = old_data {
        let mongo_doc = mongodb::bson::doc! {
            "project_id": row.get::<i32, _>("id"), "user_id": row.get::<i32, _>("user_id"), "name": row.get::<String, _>("name"), "status": "Online",
            "runtime": row.get::<String, _>("runtime"), "language": row.get::<String, _>("language"), "build_cmd": row.get::<String, _>("build_cmd"),
            "start_cmd": row.get::<String, _>("start_cmd"), "port": row.get::<i32, _>("port"), "ram_total": row.get::<i32, _>("ram_total"), "storage_total": row.get::<i32, _>("storage_total"), "created_at": mongodb::bson::DateTime::now()
        };
        let _ = mongo_coll.insert_one(mongo_doc.clone()).await; return Some(mongo_doc);
    }
    None
}

pub fn dispatch_buildpack_stream(state: AppState, language: String, runtime: String, start_cmd: String, proj_id: i32, user_id: i32, base_dir: String, port: i32) {
    let check_str = format!("{} {} {}", language, runtime, start_cmd).to_lowercase();
    let words: Vec<&str> = check_str.split(|c: char| !c.is_alphanumeric()).collect();
    let has_word = |target: &str| -> bool { words.contains(&target) };

    if has_word("rust") || has_word("rs") || has_word("cargo") {
        tokio::spawn(compile_rust_environment(state, proj_id, user_id, base_dir, port));
    } else if has_word("php") {
        tokio::spawn(compile_php_environment(state, proj_id, user_id, base_dir, port));
    } else if check_str.contains("html") || check_str.contains("static") || check_str.contains("web") {
        tokio::spawn(compile_static_environment(state, proj_id, user_id, base_dir, port));
    } else {
        let state_clone = state.clone();
        tokio::spawn(async move {
            if let Ok(mut conn) = state_clone.redis_client.get_multiplexed_tokio_connection().await {
                let log_key = format!("project:{}:history_logs", proj_id);
                let channel_name = format!("project:{}:updates", proj_id);
                let err_msg = "❌ [ERROR] Could not detect a valid project language framework. Please verify your files.\n";
                let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(&err_msg).query_async(&mut conn).await;
                let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": err_msg.trim() }).to_string();
                let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut conn).await;
            }
            update_project_status_all(&state_clone, proj_id, "Crashed").await;
            trigger_telegram_dashboard(&state_clone).await;
        });
    }
}

pub fn spawn_advanced_log_cleaner<R>(reader: R, base_dir: String, user_home: String, user_id: i32, proj_id: i32, redis_client: redis::Client) where R: tokio::io::AsyncRead + Send + Unpin + 'static, {
    tokio::spawn(async move {
        let mut lines = tokio::io::BufReader::new(reader).lines();
        let jail_username = format!("u_jail_{}", user_id);
        while let Ok(Some(line)) = lines.next_line().await {
            let mut cleaned_line = line.replace("\u{1b}", "").replace("[32m", "").replace("[0m", "").replace("[1m", "").replace("[31m", "");
            cleaned_line = cleaned_line.replace("/app/data/global_cache/cargo", "/app/.cache/cargo");
            cleaned_line = cleaned_line.replace("/app/data/global_cache", "/app/.cache");
            cleaned_line = cleaned_line.replace(&base_dir, "/app").replace(&user_home, "/app").replace("/app/data", "/app").replace(&jail_username, "user");

            if !cleaned_line.trim().is_empty() {
                if let Ok(mut conn) = redis_client.get_multiplexed_tokio_connection().await {
                    let log_key = format!("project:{}:history_logs", proj_id);
                    let channel_name = format!("project:{}:updates", proj_id);
                    let formatted_line = format!("{}\n", cleaned_line);
                    let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(&formatted_line).query_async(&mut conn).await;
                    let _: Result<(), _> = redis::cmd("LTRIM").arg(&log_key).arg(-200).arg(-1).query_async(&mut conn).await;
                    let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": cleaned_line }).to_string();
                    let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut conn).await;
                }
            }
        }
    });
}

pub async fn execute_docker(dir: &str, uid: u32, envs: Vec<(String, String)>, ulimit: &str, home: String, user_id: i32, proj_id: i32, redis_client: redis::Client) {
    let d_path = format!("{}/Dockerfile", dir);
    if tokio::fs::metadata(&d_path).await.is_ok() {
        if let Ok(content) = tokio::fs::read_to_string(&d_path).await {
            let (mut cmds, mut cur, mut in_run) = (Vec::new(), String::new(), false);
            for line in content.lines() {
                let t = line.trim();
                if t.is_empty() || t.starts_with("FROM ") || t.starts_with("ENV ") || t.starts_with("CMD ") { continue; }
                if t.starts_with("RUN ") { in_run = true; cur.push_str(t.trim_start_matches("RUN ").trim()); }
                else if in_run { cur.push_str(" "); cur.push_str(t); }
                if in_run && !cur.ends_with('\\') {
                    let l = cur.to_lowercase();
                    if !l.contains("rm -rf") && !l.contains("sudo ") { cmds.push(cur.replace("apt-get install", "apt-get install -y")); }
                    cur.clear(); in_run = false;
                } else if in_run { cur.pop(); }
            }
            if !cmds.is_empty() {
                if let Ok(mut conn) = redis_client.get_multiplexed_tokio_connection().await {
                    let log_key = format!("project:{}:history_logs", proj_id);
                    let channel_name = format!("project:{}:updates", proj_id);
                    let notice = "📦 [SYSTEM] Applying custom environment build layers...\n";
                    let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(notice).query_async(&mut conn).await;
                    let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": notice.trim() }).to_string();
                    let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut conn).await;
                }
                let exec = format!("export DEBIAN_FRONTEND=noninteractive; umask 000; {} {} < /dev/null", ulimit, cmds.join("\n"));
                if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(dir).uid(uid).env_clear().envs(envs).arg("-c").arg(&exec).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
                    if let Some(out) = child.stdout.take() { spawn_advanced_log_cleaner(out, dir.to_string(), home.clone(), user_id, proj_id, redis_client.clone()); }
                    if let Some(err) = child.stderr.take() { spawn_advanced_log_cleaner(err, dir.to_string(), home.clone(), user_id, proj_id, redis_client); }
                    let _ = tokio::time::timeout(std::time::Duration::from_secs(150), child.wait()).await;
                }
            }
        }
    }
}

pub async fn compile_rust_environment(state: AppState, proj_id: i32, user_id: i32, base_dir: String, port: i32) {
    let user_home = format!("/app/data/user_{}", user_id);
    let sys_user = format!("u_jail_p{}", proj_id); let sys_uid = 10000 + proj_id;

    let username_query: String = sqlx::query_scalar("SELECT username FROM users WHERE id = $1").bind(user_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
    let project_name_query: String = sqlx::query_scalar("SELECT name FROM projects WHERE id = $1").bind(proj_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
    {
        let mut builds = ACTIVE_BUILDS.lock().await;
        builds.insert(proj_id, ActiveBuild { username: username_query.clone(), project_name: project_name_query.clone(), language: "Rust".to_string(), start_time: std::time::Instant::now() });
    }
    trigger_telegram_dashboard(&state).await;
    ensure_jail_user(proj_id, user_id).await;

    let mut active_port = port;
    loop { if std::net::TcpListener::bind(format!("127.0.0.1:{}", active_port)).is_ok() { break; } active_port += 1; }

    let target_files = vec!["Cargo.toml", "src/main.rs", "src/lib.rs"];
    for file_name in target_files {
        let file_path = format!("{}/{}", base_dir, file_name);
        if tokio::fs::metadata(&file_path).await.is_ok() {
            if let Ok(content) = tokio::fs::read_to_string(&file_path).await {
                let mut updated_content = content; let mut changed = false;
                if updated_content.contains(&port.to_string()) { updated_content = updated_content.replace(&port.to_string(), &active_port.to_string()); changed = true; }
                for p in &["8080", "3000", "5000", "8000", "8081", "5001", "4000"] {
                    if updated_content.contains(p) && *p != active_port.to_string() { updated_content = updated_content.replace(p, &active_port.to_string()); changed = true; }
                }
                if changed { let _ = tokio::fs::write(&file_path, updated_content).await; }
            }
        }
    }

    let binary_path = format!("{}/silent_app_bin", base_dir); 
    let mut need_compilation = true;

    if tokio::fs::metadata(&binary_path).await.is_ok() {
        if let Ok(bin_meta) = tokio::fs::metadata(&binary_path).await {
            if let Ok(bin_time) = bin_meta.modified() { 
                if !has_rust_code_changed(&base_dir, bin_time).await { need_compilation = false; } 
            }
        }
    }

    let tmp_cargo_target = format!("/tmp/project_{}_cargo_target", proj_id);
    let global_deps_cache = "/app/data/global_cache/rust_deps"; 
    let private_deps_dir = format!("{}/release/deps", tmp_cargo_target);
    let mut build_failed = false;

    let mut safe_envs = std::env::vars().collect::<Vec<(String, String)>>();
    safe_envs.retain(|(k, _)| { let ku = k.to_uppercase(); !ku.contains("DATABASE") && !ku.contains("SECRET") && !ku.contains("URL") });

    if let Ok(linked_dbs) = sqlx::query("SELECT db_type, internal_url FROM project_databases WHERE project_id = $1").bind(proj_id).fetch_all(&state.pg_pool).await {
        for db_row in linked_dbs {
            let db_type: String = db_row.get("db_type"); let internal_url: String = db_row.get("internal_url");
            if db_type == "postgres" { safe_envs.push(("POSTGRES_URL".to_string(), internal_url.clone())); safe_envs.push(("DATABASE_URL".to_string(), internal_url)); }
            else if db_type == "mongodb" { safe_envs.push(("MONGO_URL".to_string(), internal_url)); }
            else if db_type == "redis" { safe_envs.push(("REDIS_URL".to_string(), internal_url)); }
            else if db_type == "mysql" { safe_envs.push(("MYSQL_URL".to_string(), internal_url)); }
        }
    }

    safe_envs.push(("OMP_NUM_THREADS".to_string(), "1".to_string()));
    safe_envs.push(("RAYON_NUM_THREADS".to_string(), "1".to_string()));

    if need_compilation {
        let _ = tokio::fs::remove_file(&binary_path).await;

        if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
            let log_key = format!("project:{}:history_logs", proj_id); let channel_name = format!("project:{}:updates", proj_id);
            let compile_log = "⚡ [SYSTEM] Code changes detected! Spawning compiler threads to compile binary...\n";
            let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(compile_log).query_async(&mut redis_conn).await;
            let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": compile_log.trim() }).to_string();
            let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut redis_conn).await;
        }

        let permit = RUST_BUILD_SEMAPHORE.acquire().await.unwrap();
        let _ = tokio::fs::create_dir_all(&private_deps_dir).await; let _ = tokio::fs::create_dir_all(global_deps_cache).await;
        let _ = tokio::process::Command::new("sh").arg("-c").arg(format!("cp -rp {}/* {}/ 2>/dev/null || true", global_deps_cache, private_deps_dir)).status().await;

        let base_sys_path = "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin".to_string();
        safe_envs.push(("PATH".to_string(), format!("/root/.cargo/bin:/usr/local/cargo/bin:{}", base_sys_path)));
        safe_envs.push(("HOME".to_string(), user_home.clone())); safe_envs.push(("PORT".to_string(), active_port.to_string()));
        safe_envs.push(("CARGO_HOME".to_string(), "/app/data/global_cache/cargo".to_string())); safe_envs.push(("CARGO_TARGET_DIR".to_string(), tmp_cargo_target.clone()));
        safe_envs.push(("RUSTFLAGS".to_string(), "-C codegen-units=1 -C debuginfo=0".to_string()));

        let rust_compile_cmd = format!(
            "chown -R root:root {base_dir} {tmp_cargo_target} 2>/dev/null; \
             rustup default stable 2>/dev/null || true; \
             ulimit -n 65535 2>/dev/null; \
             cargo build --release --jobs 1 2>&1 && \
             find {tmp_cargo_target}/release -maxdepth 1 -type f -executable -exec cp {{}} {base_dir}/silent_app_bin \\;",
            base_dir = base_dir, tmp_cargo_target = tmp_cargo_target
        );

        if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).env_clear().envs(safe_envs.clone()).arg("-c").arg(&rust_compile_cmd).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
            if let Some(out) = child.stdout.take() { spawn_advanced_log_cleaner(out, base_dir.clone(), user_home.clone(), user_id, proj_id, state.redis_client.clone()); }
            if let Err(_) = tokio::time::timeout(std::time::Duration::from_secs(300), child.wait()).await { let _ = child.kill().await; build_failed = true; }
        }

        if !build_failed && tokio::fs::metadata(&binary_path).await.is_ok() {
            let _ = tokio::process::Command::new("sh").arg("-c").arg(format!("cp -rn {}/* {}/ 2>/dev/null || true", private_deps_dir, global_deps_cache)).status().await;
            let _ = std::process::Command::new("chown").args(&[&format!("{}:{}", sys_user, sys_user), &binary_path]).status();
            let _ = std::process::Command::new("chmod").args(&["755", &binary_path]).status(); 
        } else { build_failed = true; }
        drop(permit);
    } else {

        if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
            let log_key = format!("project:{}:history_logs", proj_id); let channel_name = format!("project:{}:updates", proj_id);
            let skip_log = "🚀 [SYSTEM] No code changes detected. Booting application instantly from cached binary...\n";
            let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(skip_log).query_async(&mut redis_conn).await;
            let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": skip_log.trim() }).to_string();
            let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut redis_conn).await;
        }
    }

    let _ = tokio::fs::remove_dir_all(&tmp_cargo_target).await;
    { let mut builds = ACTIVE_BUILDS.lock().await; builds.remove(&proj_id); }

    if build_failed {
        TOTAL_FAILED_BUILDS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        update_project_status_all(&state, proj_id, "Crashed").await;
        kill_room_surgical(&base_dir, active_port, proj_id).await; trigger_telegram_dashboard(&state).await; return;
    } else { TOTAL_SUCCESS_BUILDS.fetch_add(1, std::sync::atomic::Ordering::Relaxed); }

    let mut runtime_envs = std::env::vars().collect::<Vec<(String, String)>>();
    runtime_envs.retain(|(k, _)| { let ku = k.to_uppercase(); !ku.contains("DATABASE") && !ku.contains("SECRET") && !ku.contains("URL") });
    let _ = std::process::Command::new("chmod").args(&["711", &user_home]).status();
    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
    let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

    let base_sys_path = "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin".to_string();
    runtime_envs.push(("PATH".to_string(), base_sys_path)); runtime_envs.push(("PORT".to_string(), active_port.to_string())); runtime_envs.push(("HOME".to_string(), user_home.clone()));
    runtime_envs.push(("OMP_NUM_THREADS".to_string(), "1".to_string())); runtime_envs.push(("RAYON_NUM_THREADS".to_string(), "1".to_string()));

    update_project_status_all(&state, proj_id, "Online").await;
    trigger_telegram_dashboard(&state).await;

    let start_exec = format!("umask 000; ulimit -n 65535 2>/dev/null; echo $$ > run.pid; exec ./silent_app_bin 2>&1");
    if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).env_clear().envs(runtime_envs).uid(sys_uid as u32).gid(sys_uid as u32).arg("-c").arg(&start_exec).process_group(0).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
        if let Some(out) = child.stdout.take() { spawn_advanced_log_cleaner(out, base_dir.clone(), user_home.clone(), user_id, proj_id, state.redis_client.clone()); }
        if let Some(err) = child.stderr.take() { spawn_security_watchdog(err, proj_id, username_query, base_dir.clone(), active_port, state.clone()); }
        let _ = child.wait().await;
    }
    update_project_status_all(&state, proj_id, "Offline").await;
}

pub async fn compile_php_environment(state: AppState, proj_id: i32, user_id: i32, base_dir: String, port: i32) {
    let user_home = format!("/app/data/user_{}", user_id);
    let sys_user = format!("u_jail_p{}", proj_id); let sys_uid = 10000 + proj_id;

    let username_query: String = sqlx::query_scalar("SELECT username FROM users WHERE id = $1").bind(user_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
    let project_name_query: String = sqlx::query_scalar("SELECT name FROM projects WHERE id = $1").bind(proj_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
    {
        let mut builds = ACTIVE_BUILDS.lock().await;
        builds.insert(proj_id, ActiveBuild { username: username_query.clone(), project_name: project_name_query.clone(), language: "PHP".to_string(), start_time: std::time::Instant::now() });
    }
    trigger_telegram_dashboard(&state).await;
    ensure_jail_user(proj_id, user_id).await;

    let mut active_port = port;
    loop { if std::net::TcpListener::bind(format!("127.0.0.1:{}", active_port)).is_ok() { break; } active_port += 1; }

    let target_files = vec!["index.php", "server.php", "app.php"];
    for file_name in target_files {
        let file_path = format!("{}/{}", base_dir, file_name);
        if tokio::fs::metadata(&file_path).await.is_ok() {
            if let Ok(content) = tokio::fs::read_to_string(&file_path).await {
                let mut updated_content = content; let mut changed = false;
                if updated_content.contains(&port.to_string()) { updated_content = updated_content.replace(&port.to_string(), &active_port.to_string()); changed = true; }
                for p in &["8080", "3000", "5000", "8000", "8081", "5001", "4000"] {
                    if updated_content.contains(p) && *p != active_port.to_string() { updated_content = updated_content.replace(p, &active_port.to_string()); changed = true; }
                }
                if changed { let _ = tokio::fs::write(&file_path, updated_content).await; }
            }
        }
    }

    let base_sys_path = "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin".to_string();
    let mut safe_envs = std::env::vars().collect::<Vec<(String, String)>>();
    safe_envs.retain(|(k, _)| { let ku = k.to_uppercase(); !ku.contains("DATABASE") && !ku.contains("SECRET") && !ku.contains("URL") });
    safe_envs.push(("PATH".to_string(), base_sys_path)); safe_envs.push(("PORT".to_string(), active_port.to_string())); safe_envs.push(("HOME".to_string(), user_home.clone()));

    let ulimit_cmd = "ulimit -n 65535 2>/dev/null; ulimit -u 65535 2>/dev/null;";
    execute_docker(&base_dir, sys_uid as u32, safe_envs.clone(), ulimit_cmd, user_home.clone(), user_id, proj_id, state.redis_client.clone()).await;

    let project_data = sqlx::query("SELECT start_cmd FROM projects WHERE id = $1").bind(proj_id).fetch_one(&state.pg_pool).await.unwrap();
    let mut final_start_cmd: String = project_data.get("start_cmd");
    if final_start_cmd.trim().is_empty() { final_start_cmd = format!("php -S 0.0.0.0:{}", active_port); }

    { let mut builds = ACTIVE_BUILDS.lock().await; builds.remove(&proj_id); }
    TOTAL_SUCCESS_BUILDS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    update_project_status_all(&state, proj_id, "Online").await;
    trigger_telegram_dashboard(&state).await;

    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
    let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

    let start_exec = format!("umask 000; {} echo $$ > run.pid; exec {} 2>&1", ulimit_cmd, final_start_cmd);
    if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).env_clear().envs(safe_envs).uid(sys_uid as u32).gid(sys_uid as u32).arg("-c").arg(&start_exec).process_group(0).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
        if let Some(out) = child.stdout.take() { spawn_advanced_log_cleaner(out, base_dir.clone(), user_home.clone(), user_id, proj_id, state.redis_client.clone()); }
        if let Some(err) = child.stderr.take() { spawn_security_watchdog(err, proj_id, username_query, base_dir.clone(), active_port, state.clone()); }
        let _ = child.wait().await;
    }
    update_project_status_all(&state, proj_id, "Offline").await;
}

pub async fn compile_static_environment(state: AppState, proj_id: i32, user_id: i32, base_dir: String, port: i32) {
    let user_home = format!("/app/data/user_{}", user_id);
    let sys_user = format!("u_jail_p{}", proj_id); let sys_uid = 10000 + proj_id;

    let username_query: String = sqlx::query_scalar("SELECT username FROM users WHERE id = $1").bind(user_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
    let project_name_query: String = sqlx::query_scalar("SELECT name FROM projects WHERE id = $1").bind(proj_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
    {
        let mut builds = ACTIVE_BUILDS.lock().await;
        builds.insert(proj_id, ActiveBuild { username: username_query.clone(), project_name: project_name_query.clone(), language: "Static HTML".to_string(), start_time: std::time::Instant::now() });
    }
    trigger_telegram_dashboard(&state).await;
    ensure_jail_user(proj_id, user_id).await;

    let mut active_port = port;
    loop { if std::net::TcpListener::bind(format!("127.0.0.1:{}", active_port)).is_ok() { break; } active_port += 1; }

    let target_files = vec!["index.html", "main.html", "app.html"];
    for file_name in target_files {
        let file_path = format!("{}/{}", base_dir, file_name);
        if tokio::fs::metadata(&file_path).await.is_ok() {
            if let Ok(content) = tokio::fs::read_to_string(&file_path).await {
                let mut updated_content = content; let mut changed = false;
                if updated_content.contains(&port.to_string()) { updated_content = updated_content.replace(&port.to_string(), &active_port.to_string()); changed = true; }
                for p in &["8080", "3000", "5000", "8000", "8081", "5001", "4000"] {
                    if updated_content.contains(p) && *p != active_port.to_string() { updated_content = updated_content.replace(p, &active_port.to_string()); changed = true; }
                }
                if changed { let _ = tokio::fs::write(&file_path, updated_content).await; }
            }
        }
    }

    let base_sys_path = "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin".to_string();
    let mut safe_envs = std::env::vars().collect::<Vec<(String, String)>>();
    safe_envs.push(("PATH".to_string(), base_sys_path)); safe_envs.push(("PORT".to_string(), active_port.to_string())); safe_envs.push(("HOME".to_string(), user_home.clone()));

    let ulimit_cmd = "ulimit -n 65535 2>/dev/null; ulimit -u 65535 2>/dev/null;";
    execute_docker(&base_dir, sys_uid as u32, safe_envs.clone(), ulimit_cmd, user_home.clone(), user_id, proj_id, state.redis_client.clone()).await;

    let project_data = sqlx::query("SELECT start_cmd FROM projects WHERE id = $1").bind(proj_id).fetch_one(&state.pg_pool).await.unwrap();
    let mut final_start_cmd: String = project_data.get("start_cmd");
    if final_start_cmd.trim().is_empty() || final_start_cmd == "serve" { final_start_cmd = format!("python3 -m http.server {}", active_port); }

    { let mut builds = ACTIVE_BUILDS.lock().await; builds.remove(&proj_id); }
    TOTAL_SUCCESS_BUILDS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    update_project_status_all(&state, proj_id, "Online").await;
    trigger_telegram_dashboard(&state).await;

    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
    let _ = std::process::Command::new("chmod").args(&["-R", "755", &base_dir]).status();

    let start_exec = format!("umask 000; {} echo $$ > run.pid; exec {} 2>&1", ulimit_cmd, final_start_cmd);
    if let Ok(mut child) = tokio::process::Command::new("sh").current_dir(&base_dir).env_clear().envs(safe_envs).uid(sys_uid as u32).gid(sys_uid as u32).arg("-c").arg(&start_exec).process_group(0).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped()).spawn() {
        if let Some(out) = child.stdout.take() { spawn_advanced_log_cleaner(out, base_dir.clone(), user_home.clone(), user_id, proj_id, state.redis_client.clone()); }
        if let Some(err) = child.stderr.take() { spawn_security_watchdog(err, proj_id, username_query, base_dir.clone(), active_port, state.clone()); }
        let _ = child.wait().await;
    }
    update_project_status_all(&state, proj_id, "Offline").await;
}

pub async fn websocket_handler(ws: axum::extract::ws::WebSocketUpgrade, Path(id): Path<String>, State(state): State<AppState>) -> axum::response::Response {
    let p_id = id.parse::<i32>().unwrap_or(0);
    ws.on_upgrade(move |socket| handle_socket_file_stream(socket, state, p_id))
}

pub async fn handle_socket_file_stream(mut socket: axum::extract::ws::WebSocket, state: AppState, target_project_id: i32) {
    if target_project_id == 0 { return; }

    let mut pubsub_conn = match state.redis_client.get_async_connection().await {
        Ok(conn) => conn.into_pubsub(),
        Err(_) => {
            let _ = socket.send(axum::extract::ws::Message::Text(serde_json::json!({ "project_id": target_project_id, "type": "log_update", "value": "❌ [SYSTEM] Connection to log server failed." }).to_string())).await;
            return;
        }
    };

    let channel_name = format!("project:{}:updates", target_project_id);
    if pubsub_conn.subscribe(&channel_name).await.is_err() { return; }

    let mut stream = pubsub_conn.on_message();
    while let Some(msg) = stream.next().await {
        let payload: Result<String, _> = msg.get_payload();
        if let Ok(text_msg) = payload {
            if socket.send(axum::extract::ws::Message::Text(text_msg)).await.is_err() { break; }
        }
    }
}