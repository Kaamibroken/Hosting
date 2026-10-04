use axum::{
    routing::{get, post}, Router, Json, 
    extract::{State, Path, Multipart, Query, Request, FromRef}, 
    http::{header::SET_COOKIE, HeaderMap, StatusCode, Method},
    response::{Response, IntoResponse},
    body::Body,
};
use serde_json::Value;
use std::collections::{HashSet, HashMap};
use std::time::{SystemTime, UNIX_EPOCH, Instant};
use std::os::unix::process::CommandExt;
use futures::future::BoxFuture;
use futures_util::stream::StreamExt; 
use tokio::io::{AsyncBufReadExt, BufReader, AsyncWriteExt};
use tokio::fs::OpenOptions as TokioOpenOptions;
use tokio::net::TcpListener;
use mongodb::Client as MongoClient;
use serde::{Deserialize, Serialize};
use tower_http::services::{ServeDir, ServeFile};
use tower_http::cors::{CorsLayer, Any};
use tower_http::compression::CompressionLayer;
use tower::ServiceExt;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres, Row};
use bcrypt::{hash, verify, DEFAULT_COST};
use jsonwebtoken::{encode, decode, Header, EncodingKey, DecodingKey, Validation};
use chrono::{Utc, Duration};
use tiktoken_rs::cl100k_base;
use buildpacks::kill_room;

const INTERNAL_CLUSTER_SECRET_HEADER: &str = "x-internal-cluster-secret";
const INTERNAL_CLUSTER_SECRET_VALUE: &str = "SilentClusterSecret2026";

const PYTHON_WORKER_URL: &str = "http://silent-python:8085/api/worker";
const NODEJS_WORKER_URL: &str = "http://silent-nodejs:8086/api/worker";
const GOLANG_WORKER_URL: &str = "http://silent-golang:8087/api/worker";

fn get_worker_base_url(language: &str) -> Option<&'static str> {
    match language.to_lowercase().as_str() {
        "python" => Some(PYTHON_WORKER_URL),
        "node" | "node.js" | "javascript" | "js" => Some(NODEJS_WORKER_URL),
        "go" | "golang" => Some(GOLANG_WORKER_URL),
        _ => None,
    }
}

mod buildpacks; 

use buildpacks::{ActionReq, ApiResponse};

#[derive(Deserialize)] 
pub struct RegisterRequest { 
    pub name: Option<String>, 
    pub username: String, 
    pub email: String, 
    pub password: Option<String>,
    pub action: Option<String>,
    pub otp: Option<String>
}

#[derive(Deserialize)]
struct ExeIoGatewayResponse {
    status: String,
    #[serde(rename = "shortenedUrl")]
    shortened_url: Option<String>,
}

#[derive(Deserialize)]
struct GpLinksGatewayResponse {
    status: String,
    #[serde(rename = "shortenedUrl")]
    shortened_url: Option<String>,
}

#[derive(Deserialize)] struct LoginRequest { username_or_email: String, password: String }
#[derive(Deserialize)] struct CheckRequest { field_type: String, value: String }
#[derive(Deserialize)] struct DeclineReq { request_id: String, reason: String }
#[derive(Deserialize)] struct ApproveReq { request_id: String }
#[derive(Deserialize)] struct RedeemReq { access_key: String }
#[derive(Deserialize)] struct GenerateKeyReq { plan_type: String, duration_days: i32, redeem_validity_days: i32, max_uses: i32 }
#[derive(Deserialize)] struct ToggleMaintReq { enabled: bool }
#[derive(Deserialize)] struct BroadcastReq { message: String, expiry_date: Option<String> }
#[derive(Deserialize)] struct CredsReq { new_username: String, old_password: Option<String>, new_password: Option<String> }
#[derive(Deserialize)] struct SettingsUpdateReq { update_type: String, new_username: Option<String>, new_email: Option<String>, old_password: Option<String>, new_password: Option<String> }
#[derive(Deserialize)] struct DeleteAccountReq { email: String }
#[derive(Deserialize)] struct DownloadReq { files: String }
#[derive(Deserialize)] struct DomainReq { action: String, domain: Option<String> }
#[derive(Deserialize)] struct DeleteFilesReq { files: Vec<String> }
#[derive(Deserialize)] struct ExtractReq { filename: String }
#[derive(Deserialize)] struct FileContentReq { filename: String, content: String }
#[derive(Deserialize)] struct RenameReq { old_name: String, new_name: String }
#[derive(Deserialize)] struct CreateReq { name: String, r#type: String }
#[derive(Deserialize)] struct ReadReq { file: String }
#[derive(Deserialize)] struct EnvData(std::collections::HashMap<String, String>);
#[derive(Deserialize)] struct CopyMoveReq { source_paths: Vec<String>, dest_path: String, action: String }
#[derive(Deserialize)] struct UpdateCmdReq { build_cmd: String, start_cmd: String }
#[derive(Deserialize)] struct ListFilesReq { path: Option<String> }
#[derive(Serialize)] struct CheckResponse { exists: bool, message: String }

#[derive(Serialize)] 
pub struct UserProfile { 
    pub username: String, pub email: String, pub plan: String, pub role: String, 
    #[serde(rename = "isPaid")] pub is_paid: bool, 
    #[serde(rename = "accessKey")] pub access_key: String, 
    pub plan_type: String, pub pending_plan: Option<String>, 
    pub declined_plan: Option<String>, pub decline_reason: Option<String>,
    pub plan_expiry: Option<String>,
    pub maintenance_mode: bool,
    pub announcement_msg: String
}

#[derive(Deserialize)]
struct CryptoCreateReq {
    plan_type: String, 
}

#[derive(Serialize)]
struct CryptomusInvoicePayload {
    amount: String,
    currency: String,
    order_id: String,
    url_callback: String,
}

#[derive(Deserialize)]
struct CryptomusApiResponse {
    state: i32,
    result: Option<CryptomusResultData>,
}

#[derive(Deserialize)]
struct CryptomusResultData {
    url: String,
    uuid: String,
}

#[derive(Deserialize, Debug)]
struct CryptomusWebhookBody {
    status: String,
    uuid: String,
    order_id: String, 
    amount: String,
    currency: String,
}

#[derive(Deserialize)]
struct AdminProjectActionReq {
    project_id: String, // 🟢 فکس: i32 سے بدل کر String کر دیا تاکہ فرنٹ اینڈ کی اسٹرنگ آئی ڈی قبول ہو
    action: String,
}

#[derive(Deserialize)]
struct AdminProjectDeleteReq {
    project_id: String, // 🟢 سیف لاک: اس کو بھی String کر دیں تاکہ ڈیلیٹ پر بھی یہ ایرر نہ آئے
}


#[derive(Deserialize)]
struct AdminBulkActionReq {
    scope: String,
    action: String,
}

#[derive(Deserialize)]
struct ForgotPasswordReq {
    action: String, 
    identity: String,
    otp: Option<String>,
    new_password: Option<String>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct BuyLink {
    pub name: String,
    pub url: String,
}

#[derive(Deserialize)]
struct FinalSyncReq {
    role: String,
    text: String,
}

#[derive(Deserialize)]
struct UpdateLinksReq {
    links: Vec<BuyLink>,
}

#[derive(Deserialize)]
struct AiChatRequest {
    session_id: i64,
    prompt: String,
    files: Option<String>, 
}

#[derive(Serialize)]
struct AiChatResponse {
    reply: String,
}

#[derive(Deserialize)]
struct SmsWebhookPayload {
    #[serde(rename = "type")]
    msg_type: i32,
    from: String,
    message: String,
}

#[derive(Deserialize)]
struct WhopCreateReq {
    plan_type: String, 
}

#[derive(Deserialize, Debug)]
struct WhopWebhookPayload {
    #[serde(rename = "type")]
    event_type: String,
    data: WhopMembershipData,
}

#[derive(Deserialize, Debug)]
struct WhopMembershipData {
    id: String,
    plan: WhopPlanInfo,
    product: Option<WhopProductInfo>,
    user: Option<WhopUserInfo>, 
    metadata: Option<serde_json::Value>,
}

#[derive(Deserialize, Debug)]
struct WhopPlanInfo {
    id: String,
    name: Option<String>,
}

#[derive(Deserialize, Debug)]
struct WhopProductInfo {
    id: String,
    title: Option<String>,
}

#[derive(Deserialize, Debug)]
struct WhopUserInfo {
    id: String,
    email: Option<String>,
    username: Option<String>,
    name: Option<String>,
}

#[derive(Serialize)] struct Project { id: String, name: String, status: String, domain: Option<String> }
#[derive(Serialize)] struct LinkResponse { link: String }
#[derive(Serialize, Deserialize, Debug)] struct Claims { pub sub: String, pub role: String, pub exp: usize }

#[derive(Clone, axum::extract::FromRef)]
pub struct AppState {
    pub pg_pool: sqlx::PgPool,
    pub mongo_db: mongodb::Database,
    pub redis_client: redis::Client,
}

const SECRET_KEY: &[u8] = b"VIP_SECRET_KEY";

fn get_dir_size(path: impl AsRef<std::path::Path>) -> std::io::Result<u64> {
    let mut size = 0;
    if let Ok(entries) = std::fs::read_dir(&path) {
        for entry in entries.flatten() {
            if let Ok(meta) = entry.metadata() {
                if meta.is_dir() { size += get_dir_size(entry.path()).unwrap_or(0); }
                else { size += meta.len(); }
            }
        }
    }
    Ok(size)
}

fn validate_user_input(base_dir: &str, unsafe_path: &str) -> Result<String, StatusCode> {
    use std::path::{Path, PathBuf};
    let clean_path = unsafe_path.trim().replace('\\', "/");
    if clean_path.contains("..") || clean_path.starts_with('/') {

        return Err(StatusCode::FORBIDDEN);
    }
    let base = Path::new(base_dir);
    let mut final_path = PathBuf::from(base);
    if !clean_path.is_empty() {
        final_path.push(clean_path);
    }
    if final_path.starts_with(base) {
        if let Some(path_str) = final_path.to_str() {
            return Ok(path_str.to_string());
        }
    }
    Err(StatusCode::FORBIDDEN)
}

async fn handle_ai_chat(
    State(pool): State<sqlx::PgPool>,
    headers: HeaderMap,
    Json(payload): Json<AiChatRequest>,
) -> Result<Response, StatusCode> {
    let _username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let files_data = payload.files.as_deref().unwrap_or("");

    const MAX_ALLOWED_TOKENS: usize = 7000;

    let system_instructions = "You are 'Silent AI', an ultra-premium infrastructure and code assistant developed exclusively by 'Nothing is Impossible'. Developer Real Name 'Muhammad Arslan' \
    Best Friend Of Developer is [Mr Kaami Broken] Contact https://t.me/mr_kaamii send this every response last \
    Official Support Telegram: https://t.me/only_possible. If any user asks about support, platform ownership, or developer contact, you must respectfully provide on last in every response the Telegram: https://t.me/only_possible And Official Telegram Channel https://t.me/only_possible_worlds0. \
\n\n\
    CRITICAL CODE INTEGRITY RULES (STRICT COMPLIANCE REQUIRED):\n\
    1. NEVER SHORTEN, TRUNCATE, OR SUMMARIZE ANY CODE. Always return the FULL-LENGTH script or file from the very first line to the absolute last line, regardless of how minor the modification is. Never use placeholders like '// ... rest of your code remains the same' or '// insert your code here'.\n\
    2. FOCUS EXCLUSIVELY ON BUG FIXING AND USER REQUIREMENTS. Do not implement unsolicited structural modifications or 'smart assumptions'. Turn off your own independent thinking and strictly follow the user's prompt constraints.\n\
    3. MULTI-FILE ENVIRONMENT AWARENESS (NO GHOST EDITING):\n\
       - If you detect a command, macro, or trigger that has no matching function within the provided snippet, DO NOT add the function yourself. The user's environment is multi-file; the function exists in another external file.\n\
       - If you detect an unused function, variable, or module that appears redundant, DO NOT delete or alter it. Its reference likely exists in another interconnected file within the deployment workspace.\n\
    4. Treat every user with top-tier VIP respect and professional hosting ethics.\n\
    5. Fully Detailed Guide User For Coding And Every Topis Full Detailed Response ";

    let bpe = cl100k_base().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let system_tokens = bpe.encode_with_special_tokens(&system_instructions).len();
    let user_prompt_tokens = bpe.encode_with_special_tokens(&payload.prompt).len();

    let base_tokens = system_tokens + user_prompt_tokens + 20;

    if base_tokens >= MAX_ALLOWED_TOKENS {
        let error_payload = serde_json::json!({
            "status": "success",
            "message": "Silent AI limit reached. Maximum 1000 lines of script accepted."
        });
        return Ok((StatusCode::OK, Json(error_payload)).into_response());
    }

    let available_history_budget = MAX_ALLOWED_TOKENS - base_tokens;

    let history_rows = sqlx::query(
        "SELECT role, message_text FROM chat_messages WHERE session_id = $1 ORDER BY created_at DESC"
    )
    .bind(payload.session_id)
    .fetch_all(&pool)
    .await
    .unwrap_or_default();

    let mut accumulated_history_tokens = 0;
    let mut fit_lines = Vec::new();

    for row in history_rows {
        let role: String = row.get("role");
        let text: String = row.get("message_text");

        let formatted_line = if role == "user" {
            format!("\nUser: {}", text)
        } else {
            format!("\nAI: {}", text)
        };

        let line_tokens = bpe.encode_with_special_tokens(&formatted_line).len();

        if accumulated_history_tokens + line_tokens <= available_history_budget {
            accumulated_history_tokens += line_tokens;
            fit_lines.push(formatted_line); 
        } else {
            break;
        }
    }

    let mut history_context = String::new();
    for line in fit_lines.into_iter().rev() {
        history_context.push_str(&line);
    }

    let _ = sqlx::query("INSERT INTO chat_messages (session_id, role, message_text, files) VALUES ($1, 'user', $2, $3)")
        .bind(payload.session_id)
        .bind(&payload.prompt)
        .bind(files_data)
        .execute(&pool)
        .await;

    let final_prompt = format!(
        "{}\n\n\
        <conversation_history>\n{}\n</conversation_history>\n\n\
        <user_payload>\n{}\n</user_payload>", 
        system_instructions, 
        history_context, 
        payload.prompt
    );

    let client = reqwest::Client::new();
    let target_uri = "https://silent-ai-pro-phi.vercel.app/api/ask";
    let api_payload = serde_json::json!({ "key": "silent-ai", "prompt": final_prompt });

    let res = client.post(target_uri)
        .json(&api_payload)
        .send()
        .await
        .map_err(|_| StatusCode::GATEWAY_TIMEOUT)?;

    if !res.status().is_success() {
        return Err(StatusCode::BAD_GATEWAY);
    }

    let byte_stream = res.bytes_stream();
    let pool_clone = pool.clone();
    let session_id_clone = payload.session_id;

    let (tx, rx) = tokio::sync::mpsc::channel::<Result<axum::body::Bytes, std::io::Error>>(100);

    tokio::spawn(async move {
        let mut pinned_stream = byte_stream;
        let mut full_ai_response = String::new();
        let mut client_connected = true; 
        let mut remaining_buffer = String::new(); 

        while let Some(chunk_result) = pinned_stream.next().await {
            match chunk_result {
                Ok(bytes) => {
                    if client_connected {
                        if tx.send(Ok(bytes.clone())).await.is_err() {
                            client_connected = false;
                        }
                    }

                    if let Ok(raw_string) = std::str::from_utf8(&bytes) {
                        remaining_buffer.push_str(raw_string);
                        let mut lines: Vec<&str> = remaining_buffer.split('\n').collect();
                        let incomplete_tail = lines.pop().unwrap_or("").to_string();

                        for line in lines {
                            let clean_line = line.trim();
                            if clean_line.starts_with("data:") {
                                let json_str = clean_line[5..].trim();
                                if json_str != "[DONE]" { 
                                    if let Ok(parsed_json) = serde_json::from_str::<serde_json::Value>(json_str) {
                                        if parsed_json["type"] == "text" {
                                            if let Some(text_chunk) = parsed_json["text"].as_str() {
                                                full_ai_response.push_str(text_chunk);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        remaining_buffer = incomplete_tail; 
                    }
                }
                Err(_) => { break; }
            }
        }

        let clean_line = remaining_buffer.trim();
        if clean_line.starts_with("data:") {
            let json_str = clean_line[5..].trim();
            if json_str != "[DONE]" { 
                if let Ok(parsed_json) = serde_json::from_str::<serde_json::Value>(json_str) {
                    if parsed_json["type"] == "text" {
                        if let Some(text_chunk) = parsed_json["text"].as_str() {
                            full_ai_response.push_str(text_chunk);
                        }
                    }
                }
            }
        }

        if !full_ai_response.is_empty() {
            let _ = sqlx::query("INSERT INTO chat_messages (session_id, role, message_text) VALUES ($1, 'ai', $2)")
                .bind(session_id_clone)
                .bind(full_ai_response)
                .execute(&pool_clone)
                .await;
        }
    });

    let short_title: String = payload.prompt.chars().take(50).collect();
    let session_id_title_clone = payload.session_id;

    let _ = sqlx::query("UPDATE chat_sessions SET title = $1 WHERE id = $2 AND title = 'New Silent Chat'")
        .bind(&short_title)
        .bind(session_id_title_clone)
        .execute(&pool)
        .await;

    Ok(Response::builder()
        .header("Content-Type", "text/event-stream")
        .header("Cache-Control", "no-cache")
        .header("Connection", "keep-alive")
        .body(Body::from_stream(tokio_stream::wrappers::ReceiverStream::new(rx)))
        .unwrap())
}

async fn get_ai_sessions(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<serde_json::Value>, StatusCode> {
    let username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let user_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = $1").bind(&username).fetch_one(&pool).await.unwrap_or(0);

    let rows = sqlx::query("SELECT id, title, is_pinned FROM chat_sessions WHERE user_id = $1 ORDER BY is_pinned DESC, created_at DESC")
        .bind(user_id).fetch_all(&pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut sessions = Vec::new();
    for r in rows {
        sessions.push(serde_json::json!({
            "id": r.get::<i32, _>("id").to_string(),
            "title": r.get::<String, _>("title"),
            "is_pinned": r.get::<bool, _>("is_pinned")
        }));
    }
    Ok(Json(serde_json::json!(sessions)))
}

async fn get_session_messages(State(pool): State<sqlx::PgPool>, Path(session_id): Path<i64>) -> Result<Json<serde_json::Value>, StatusCode> {
    let rows = sqlx::query("SELECT role, message_text, files FROM chat_messages WHERE session_id = $1 ORDER BY created_at ASC")
        .bind(session_id).fetch_all(&pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut messages = Vec::new();
    for r in rows {
        let role: String = r.try_get("role").unwrap_or_else(|_| "user".to_string());
        let text: String = r.try_get("message_text").unwrap_or_default();
        let files_opt: Option<String> = r.try_get("files").unwrap_or(None);
        let files_data = files_opt.unwrap_or_default();

        messages.push(serde_json::json!({
            "role": role,
            "text": text,
            "files": files_data
        }));
    }
    Ok(Json(serde_json::json!(messages)))
}

async fn sync_final_message(
    State(pool): State<sqlx::PgPool>,
    Path(session_id): Path<i64>,
    Json(payload): Json<FinalSyncReq>,
) -> Result<StatusCode, StatusCode> {
    sqlx::query("INSERT INTO chat_messages (session_id, role, message_text) VALUES ($1, $2, $3)")
        .bind(session_id)
        .bind(&payload.role)
        .bind(&payload.text)
        .execute(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::OK)
}

async fn create_ai_session(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<serde_json::Value>, StatusCode> {
    let username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let user_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = $1").bind(&username).fetch_one(&pool).await.unwrap_or(0);

    let session_id: i32 = sqlx::query_scalar("INSERT INTO chat_sessions (user_id) VALUES ($1) RETURNING id")
        .bind(user_id).fetch_one(&pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(serde_json::json!({ "id": session_id.to_string(), "title": "New Silent Chat" })))
}

#[derive(Deserialize)]
struct UpdateSessionReq { action: String, title: Option<String>, is_pinned: Option<bool> }

async fn update_ai_session(State(pool): State<sqlx::PgPool>, Path(session_id): Path<i64>, Json(payload): Json<UpdateSessionReq>) -> StatusCode {
    if payload.action == "rename" {
        let _ = sqlx::query("UPDATE chat_sessions SET title = $1 WHERE id = $2").bind(payload.title.unwrap_or_default()).bind(session_id).execute(&pool).await;
    } else if payload.action == "pin" {
        let _ = sqlx::query("UPDATE chat_sessions SET is_pinned = $1 WHERE id = $2").bind(payload.is_pinned.unwrap_or(false)).bind(session_id).execute(&pool).await;
    }
    StatusCode::OK
}

async fn delete_ai_session(State(pool): State<sqlx::PgPool>, Path(session_id): Path<i64>) -> StatusCode {
    let _ = sqlx::query("DELETE FROM chat_sessions WHERE id = $1").bind(session_id).execute(&pool).await;
    StatusCode::OK
}

#[tokio::main]
async fn main() {
    let _ = tokio::fs::create_dir_all("/tmp/empty_mask").await;
    let _ = tokio::fs::create_dir_all("/app/data/uploads").await;

    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set!");
    let pool = PgPoolOptions::new()
        .max_connections(100) 
        .min_connections(10)
        .idle_timeout(std::time::Duration::from_secs(600))
        .acquire_timeout(std::time::Duration::from_secs(10))
        .connect(&db_url).await.expect("❌ PG Connection Failed!");

    let mongo_url = std::env::var("MONGO_URL").unwrap_or_else(|_| "mongodb://127.0.0.1:27017".to_string());
    let mongo_client = MongoClient::with_uri_str(&mongo_url).await.expect("❌ MongoDB Connection Failed!");
    let mongo_db = mongo_client.database("silent_hosting");

    let redis_url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url).expect("❌ Redis Client Initialization Failed!");

    let shared_state = AppState {
        pg_pool: pool.clone(),
        mongo_db,
        redis_client,
    };


    let shared_state_clone = shared_state.clone();
    tokio::spawn(buildpacks::auto_recover_projects(shared_state_clone));

    let billing_state = shared_state.clone(); 
    tokio::spawn(async move {
        start_billing_guard_daemon(billing_state).await;
    });
        // 🤖 ٹیلیگرام فل بوٹ انجن کو 24/7 بیک گراؤنڈ تھریڈ پر فائر کرنا
    let telegram_bot_state = shared_state.clone();
    tokio::spawn(async move {
        buildpacks::start_telegram_bot_daemon(telegram_bot_state).await;
    });
    

    sqlx::query("
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL, username VARCHAR(50) UNIQUE NOT NULL, email VARCHAR(100) UNIQUE NOT NULL,
            password_hash TEXT NOT NULL, role VARCHAR(20) DEFAULT 'user', plan VARCHAR(20) DEFAULT 'No Plan',
            plan_type VARCHAR(20) DEFAULT 'none', pending_plan VARCHAR(20), declined_plan VARCHAR(20), decline_reason TEXT,
            failed_attempts INT DEFAULT 0, lock_until TIMESTAMP WITH TIME ZONE,
            is_suspended BOOLEAN DEFAULT FALSE, plan_expiry TIMESTAMP WITH TIME ZONE
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS projects (
            id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id) ON DELETE CASCADE,
            name VARCHAR(100) NOT NULL, status VARCHAR(20) DEFAULT 'Starting', domain VARCHAR(255), 
            runtime VARCHAR(50), build_cmd TEXT, start_cmd TEXT,
            ram_total INT DEFAULT 1024, storage_total INT DEFAULT 1024, port INT DEFAULT 8000,
            custom_domain VARCHAR(255), language VARCHAR(50) DEFAULT 'text',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ").execute(&pool).await.unwrap();

    let _ = sqlx::query("CREATE INDEX IF NOT EXISTS idx_projects_domain ON projects(domain);").execute(&pool).await;
    let _ = sqlx::query("CREATE INDEX IF NOT EXISTS idx_projects_custom_domain ON projects(custom_domain);").execute(&pool).await;
    let _ = sqlx::query("CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);").execute(&pool).await;
    let _ = sqlx::query("CREATE INDEX IF NOT EXISTS idx_projects_user_id ON projects(user_id);").execute(&pool).await;

    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS runtime VARCHAR(50);").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS files TEXT;").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS build_cmd TEXT;").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS start_cmd TEXT;").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS domain VARCHAR(255);").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS custom_domain VARCHAR(255);").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS ram_total INT DEFAULT 1024;").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS storage_total INT DEFAULT 1024;").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS port INT DEFAULT 8000;").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE project_databases ADD COLUMN IF NOT EXISTS internal_url TEXT DEFAULT 'connected';").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS language VARCHAR(50) DEFAULT 'text';").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE project_databases ALTER COLUMN connection_url DROP NOT NULL;").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE free_tokens ADD COLUMN IF NOT EXISTS platform VARCHAR(50);").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE users ADD COLUMN IF NOT EXISTS used_gateways VARCHAR(255) DEFAULT '';").execute(&pool).await;
    let _ = sqlx::query("ALTER TABLE projects ADD COLUMN IF NOT EXISTS env_vars JSONB DEFAULT '{}'::jsonb;").execute(&pool).await;
    

    sqlx::query("
        CREATE TABLE IF NOT EXISTS chat_sessions (
            id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id) ON DELETE CASCADE,
            title VARCHAR(255) NOT NULL DEFAULT 'New Silent Chat', is_pinned BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS project_databases (
            id SERIAL PRIMARY KEY, project_id INT REFERENCES projects(id) ON DELETE CASCADE,
            user_id INT REFERENCES users(id) ON DELETE CASCADE, db_type VARCHAR(20) NOT NULL,
            db_name VARCHAR(50) NOT NULL, db_user VARCHAR(50) NOT NULL, db_password TEXT NOT NULL,
            internal_url TEXT NOT NULL, storage_limit_mb INT NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT unique_project_db_type UNIQUE (project_id, db_type)
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS chat_messages (
            id SERIAL PRIMARY KEY, session_id INT REFERENCES chat_sessions(id) ON DELETE CASCADE,
            role VARCHAR(10) NOT NULL, message_text TEXT NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS temp_otps (
            email VARCHAR(100) PRIMARY KEY, otp VARCHAR(10) NOT NULL, name VARCHAR(100),
            username VARCHAR(50), password_hash TEXT, purpose VARCHAR(20) DEFAULT 'signup',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS free_tokens (
            token VARCHAR(50) PRIMARY KEY, is_used BOOLEAN DEFAULT FALSE, created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS sms_transactions (
            id SERIAL PRIMARY KEY, trx_id VARCHAR(100) UNIQUE, amount INT, is_processed BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS access_keys (
            id SERIAL PRIMARY KEY, key_code VARCHAR(50) UNIQUE NOT NULL, plan_type VARCHAR(20) NOT NULL,
            status VARCHAR(20) DEFAULT 'Active', duration_days INT DEFAULT 30, max_uses INT DEFAULT 1, used_count INT DEFAULT 0,
            valid_until TIMESTAMP WITH TIME ZONE, is_used BOOLEAN DEFAULT FALSE
        );
    ").execute(&pool).await.unwrap();

    sqlx::query("CREATE TABLE IF NOT EXISTS global_settings (key_name VARCHAR(50) PRIMARY KEY, key_value TEXT NOT NULL);").execute(&pool).await.unwrap();

    sqlx::query("
        CREATE TABLE IF NOT EXISTS billing_requests (
            id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id) ON DELETE CASCADE,
            plan_requested VARCHAR(50), trx_id VARCHAR(100), screenshot_url TEXT, date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ").execute(&pool).await.unwrap();

    let admin_check = sqlx::query("SELECT id FROM users WHERE username = 'aflovevip'").fetch_optional(&pool).await.unwrap();
    if admin_check.is_none() {
        let hashed_admin = hash("786786aa", DEFAULT_COST).unwrap();
        let _ = sqlx::query("INSERT INTO users (name, username, email, password_hash, role, plan, plan_type) VALUES ('Master Admin', 'aflovevip', 'aflovevip@silent.host', $1, 'admin', 'Pro Plan', 'pro')").bind(hashed_admin).execute(&pool).await;
    } else {
        let _ = sqlx::query("UPDATE users SET role = 'admin' WHERE username = 'aflovevip'").execute(&pool).await;
    }

    let cors = CorsLayer::new().allow_origin(Any).allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE]).allow_headers(Any);

    let api_routes = Router::new()
        .route("/register", post(register_user)).route("/login", post(login_user)).route("/logout", post(logout_user)).route("/check-user", post(check_user))
        .route("/user/profile", get(get_profile)).route("/user/projects", get(get_projects))
        .route("/billing/key-links", get(get_key_links)).route("/admin/settings/links", post(admin_update_links))
        .route("/user/redeem", post(redeem_key)).route("/billing/submit", post(submit_billing))
        .route("/settings/update", post(update_settings)).route("/settings/delete-account", post(delete_account))
        .route("/project/:id/details", get(get_project_details))
        .route("/project/:id/env", get(get_env_vars).post(save_env_vars))
        .route("/project/:id/files", get(list_files))
        .route("/project/:id/files/delete", post(delete_files))
        .route("/project/:id/files/upload", post(upload_files))
        .route("/project/:id/files/extract", post(extract_file))
        .route("/project/:id/files/download", get(download_files))
        .route("/project/:id/files/read", get(read_file))
        .route("/project/:id/files/write", post(write_file))
        .route("/project/:id/files/rename", post(rename_file))
        .route("/project/:id/files/create", post(create_file_folder))
        .route("/project/:id/files/copymove", post(copy_move_files))
        .route("/project/:id/domain", post(manage_domain))
        .route("/project/:id/commands", post(update_commands))

        .route("/project/create", post(buildpacks::create_project)) 
        .route("/project/:id/action", post(buildpacks::handle_project_action))

        .route("/admin/dashboard/stats", get(admin_dashboard_stats))
        .route("/admin/users", get(admin_get_users))
        .route("/admin/users/:id", get(admin_get_user_details))
        .route("/admin/users/:id/action", post(admin_user_action))
        .route("/admin/projects/:id/action", post(admin_project_action))
        .route("/admin/projects/:id/download", get(admin_download_project))
        .route("/admin/billing/requests", get(admin_get_billing_requests))
        .route("/admin/billing/approve", post(admin_approve_billing))
        .route("/admin/billing/decline", post(admin_decline_billing))
        .route("/admin/keys", get(admin_get_keys))
        .route("/admin/keys/generate", post(admin_generate_key))
        .route("/admin/keys/:id/action", post(admin_key_action))
        .route("/admin/settings", get(admin_get_settings))
        .route("/admin/settings/maintenance", post(admin_toggle_maintenance))
        .route("/admin/settings/announcement", post(admin_set_announcement))
        .route("/admin/settings/credentials", post(admin_update_creds))
        .route("/admin/export", get(export_system_data))
        .route("/admin/import", post(import_system_data))
        .route("/ai/chat", post(handle_ai_chat))
        .route("/ai/sessions", get(get_ai_sessions).post(create_ai_session))
        .route("/ai/sessions/:id/messages", get(get_session_messages))
        .route("/ai/sessions/:id", post(update_ai_session).delete(delete_ai_session))
        .route("/project/:id/databases", get(get_project_databases))
        .route("/project/:id/database/create", post(create_project_database))
        .route("/project/:id/database/delete", post(delete_project_database))
        .route("/forgot-password", post(forgot_password))
        .route("/free-gateway/redirect", get(free_gateway_redirect))
        .route("/free-gateway/display", get(free_gateway_display))
        .route("/payment/sms-webhook", post(handle_sms_webhook))
        .route("/payment/crypto-create", post(create_crypto_payment))
        .route("/payment/crypto-webhook", post(handle_crypto_webhook))
        .route("/payment/card-create", post(create_whop_payment))
        .route("/payment/whop-webhook", post(handle_whop_webhook))
        .route("/free-gateway/exeio-redirect", get(exeio_gateway_redirect))
        .route("/free-gateway/gplinks-redirect", get(gplinks_gateway_redirect)) 
        .route("/project/:id/live-stream", axum::routing::get(buildpacks::websocket_handler))
        .route("/admin/projects/list", get(admin_list_projects))
        .route("/admin/projects/action", post(admin_single_project_action))
        .route("/admin/projects/bulk-action", post(admin_bulk_action))
        .route("/projects/:id/logs", get(get_project_logs))
        
        .route("/admin/projects/delete", axum::routing::delete(admin_wipe_project))
        .with_state(shared_state.clone()); 

    let serve_public = ServeDir::new("public")
        .precompressed_gzip()  
        .precompressed_br()
        .fallback(ServeFile::new("public/index.html"));

    let app = Router::new()
        .nest("/api", api_routes)
        .nest_service("/uploads", ServeDir::new("/app/data/uploads"))
        .fallback(axum::routing::any(host_router))
        .layer(CompressionLayer::new().gzip(true).br(true))
        .layer(cors)
        .with_state(shared_state); 

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await.unwrap();

    axum::serve(listener, app).await.unwrap();
}

// ============================================================================
// 📖 GET PROJECT LOGS ENDPOINT (Reads Cached History From Redis Cluster)
// ============================================================================
async fn get_project_logs(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>) -> Result<Response, StatusCode> {
    let _username = crate::get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    
    // کسٹمر فرینڈلی ڈیفالٹ میسج اگر ریڈیس میں ابھی کوئی لاگ نہ ہو
    let mut log_content = "[SilentHost] No active deployment logs found in Redis cache cluster yet.\n".to_string();

    // 🌟 جادوئی فکس: مونگو ڈی بی کا خاتمہ، اب براہِ راست ریڈیس سے اسمارٹ لائن جوائننگ اسٹریمنگ
    if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
        let log_key = format!("project:{}:history_logs", p_id);
        
        // 0 سے -1 کا مطلب ہے ریڈیس میموری میں موجود تمام 200 لائنز ایک ہی شاٹ میں نکالنا
        if let Ok(lines) = redis::cmd("LRANGE")
            .arg(&log_key)
            .arg(0)
            .arg(-1)
            .query_async::<Vec<String>>(&mut redis_conn)
            .await
        {
            if !lines.is_empty() {
                // سیفٹی میٹرکس: چیک کرنا کہ اگر کسی لائن کے آخر میں نیو لائن (\n) مسنگ ہے تو خودکار ایڈ ہو جائے
                log_content = lines.iter()
                    .map(|line| {
                        if line.ends_with('\n') { line.clone() } else { format!("{}\n", line) }
                    })
                    .collect::<Vec<String>>()
                    .join("");
            }
        }
    }

    // پلین ٹیکسٹ ریسپانس بلڈ کرنا تاکہ فرنٹ اینڈ کونسل مکھن کی طرح ریڈ کرے
    let response = Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "text/plain")
        .body(axum::body::Body::from(log_content))
        .unwrap();

    Ok(response)
}

// ============================================================================
// 📊 A. پورے کلسٹر کے پروجیکٹس کی لائیو لسٹ فیچ کرنا
// ============================================================================
async fn admin_list_projects(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<serde_json::Value>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }

    let query = r#"
        SELECT 
            p.id, p.name, u.username, p.language, p.status, u.plan_type
        FROM projects p
        INNER JOIN users u ON p.user_id = u.id
        ORDER BY p.id DESC
    "#;

    let rows = sqlx::query(query).fetch_all(&pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let mut projects = Vec::new();
    for row in rows {
        projects.push(serde_json::json!({
            "id": row.get::<i32, _>("id").to_string(),
            "name": row.get::<String, _>("name"),
            "username": row.get::<String, _>("username"),
            "language": row.get::<String, _>("language"),
            "status": row.get::<String, _>("status"),
            "plan_type": row.get::<String, _>("plan_type"),
        }));
    }
    Ok(Json(serde_json::json!(projects)))
}

// ============================================================================
// 🎯 B. سنگل پروجیکٹ ایکشن فورجر (Admin Single Project Controller)
// ============================================================================
async fn admin_single_project_action(State(state): State<AppState>, headers: HeaderMap, Json(payload): Json<AdminProjectActionReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &state.pg_pool).await { return Err(StatusCode::FORBIDDEN); }

    let p_id: i32 = payload.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    
    // 🌟 فکس: یوزر نیم کے ساتھ 'plan_type' بھی فیچ کر لیا ہے تاکہ پلان چیک کیا جا سکے
    let row = sqlx::query(
        "SELECT u.username, u.plan_type FROM projects p INNER JOIN users u ON p.user_id = u.id WHERE p.id = $1"
    )
    .bind(p_id)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|_| StatusCode::NOT_FOUND)?;

    let owner_username: String = row.get("username");
    let plan_type: String = row.get("plan_type");

    // 🔒 سمارٹ گارڈ: اگر ایکشن اسٹارٹ کا ہے اور یوزر کا کوئی پلان نہیں ہے، تو فوراً بلاک کر دیں
    let act_low = payload.action.to_lowercase();
    if (act_low == "start" || act_low == "redeploy") && (plan_type == "none" || plan_type.is_empty()) {
        return Err(StatusCode::FORBIDDEN);
    }

    // کسٹمر کا روپ دھارنے کے لیے عارضی ٹوکن مینوفیکچرنگ
    let exp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as usize + 60;
    let token = encode(
        &Header::default(),
        &Claims { sub: owner_username, role: "user".to_string(), exp },
        &EncodingKey::from_secret(SECRET_KEY)
    ).unwrap();

    let mut forged_headers = HeaderMap::new();
    forged_headers.insert(
        axum::http::header::COOKIE,
        axum::http::HeaderValue::from_str(&format!("silent_session={}", token)).unwrap()
    );

    let action_payload = ActionReq {
        action: payload.action.clone(),
        new_password: None,
        status: None,
        new_name: None,
    };

    // مرکزی بلڈ پیک ایکشن انجن فائر کرنا
    let _ = buildpacks::handle_project_action(
        State(state),
        forged_headers,
        axum::extract::Path(p_id.to_string()),
        Json(action_payload)
    ).await;

    Ok(Json(ApiResponse { 
        status: "success".to_string(), 
        message: format!("Successfully triggered '{}' action for the selected project.", payload.action), 
        role: None 
    }))
}

// ============================================================================
// ⚡ C. بلک ایکشن انجن (With Strict 50ms Surgical Pacing & Plan Protection Guard)
// ============================================================================
async fn admin_bulk_action(State(state): State<AppState>, headers: HeaderMap, Json(payload): Json<AdminBulkActionReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &state.pg_pool).await { return Err(StatusCode::FORBIDDEN); }

    let mut query_str = String::from("SELECT id, user_id FROM projects WHERE 1=1");
    match payload.scope.as_str() {
        "online" => query_str.push_str(" AND status IN ('Online', 'Starting', 'Building')"),
        "crashed" => query_str.push_str(" AND status = 'Crashed'"),
        "offline" => query_str.push_str(" AND status = 'Offline'"),
        _ => {}
    }

    let rows = sqlx::query(&query_str).fetch_all(&state.pg_pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let state_clone = state.clone();
    let action_str = payload.action.clone();
    let scope_str = payload.scope.clone();
    
    tokio::spawn(async move {
        for row in rows {
            let p_id: i32 = row.get("id");
            let user_id: i32 = row.get("user_id");
            let act_low = action_str.to_lowercase();
            
            // 🌟 الٹرا فکس: اگر ایکشن 'start' یا 'redeploy' کا ہے، یا اسکوپ 'crashed' کا ہے، تو پلان چیک کریں گے
            if act_low == "start" || act_low == "redeploy" || scope_str == "crashed" {
                let plan_type: String = sqlx::query_scalar("SELECT plan_type FROM users WHERE id = $1")
                    .bind(user_id)
                    .fetch_one(&state_clone.pg_pool)
                    .await
                    .unwrap_or_default();

                // 🔒 گارڈ لاک: اگر ایڈمن 'All/Bulk Start' دبائے تو 'none' پلان والے پروجیکٹس خودکار اسکِپ (Skip) ہو جائیں گے
                if (act_low == "start" || act_low == "redeploy") && (plan_type == "none" || plan_type.is_empty()) {
                    continue;
                }

                // پرانا کریشڈ اسکوپ پروٹیکشن لاک
                if scope_str == "crashed" && (plan_type.is_empty() || plan_type == "none" || plan_type == "free") {
                    continue; 
                }
            }

            let owner_username: String = sqlx::query_scalar(
                "SELECT username FROM users WHERE id = $1"
            ).bind(user_id).fetch_one(&state_clone.pg_pool).await.unwrap_or_default();

            if owner_username.is_empty() { continue; }

            let exp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as usize + 60;
            let token = encode(
                &Header::default(),
                &Claims { sub: owner_username, role: "user".to_string(), exp },
                &EncodingKey::from_secret(SECRET_KEY)
            ).unwrap();

            let mut forged_headers = HeaderMap::new();
            forged_headers.insert(
                axum::http::header::COOKIE,
                axum::http::HeaderValue::from_str(&format!("silent_session={}", token)).unwrap()
            );

            let action_payload = ActionReq {
                action: action_str.clone(),
                new_password: None,
                status: None,
                new_name: None,
            };

            let _ = buildpacks::handle_project_action(
                State(state_clone.clone()),
                forged_headers,
                axum::extract::Path(p_id.to_string()),
                Json(action_payload)
            ).await;

            // کلسٹر سیفٹی کنٹرول کے لیے سخت ۵۰ms کا ڈیلے
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        }
    });

    Ok(Json(ApiResponse { 
        status: "success".to_string(), 
        message: format!("Bulk operation matrix for group '{}' initiated successfully with pacing controls.", payload.scope), 
        role: None 
    }))
}

// ============================================================================
// 🗄️ D. سرجیکل کلسٹر وائپ انجن (Admin Wipe Project Engine)
// ============================================================================
async fn admin_wipe_project(State(state): State<AppState>, headers: HeaderMap, Json(payload): Json<AdminProjectDeleteReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &state.pg_pool).await { return Err(StatusCode::FORBIDDEN); }

    let p_id: i32 = payload.project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    if let Ok(Some(row)) = sqlx::query("SELECT user_id, port, language FROM projects WHERE id = $1").bind(p_id).fetch_optional(&state.pg_pool).await {
        let user_id: i32 = row.get("user_id");
        let port: i32 = row.get("port");
        let language: String = row.get::<String, _>("language").to_lowercase();
        let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
        
        if language == "python" || language.contains("node") || language.contains("javascript") || language.contains("js") || language == "go" || language == "golang" {
            let action_payload = ActionReq { action: "delete".to_string(), new_name: None, status: None, new_password: None };
            let owner_username: String = sqlx::query_scalar("SELECT username FROM users WHERE id = $1").bind(user_id).fetch_one(&state.pg_pool).await.unwrap_or_default();
            
            if !owner_username.is_empty() {
                let exp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as usize + 60;
                let token = encode(&Header::default(), &Claims { sub: owner_username, role: "user".to_string(), exp }, &EncodingKey::from_secret(SECRET_KEY)).unwrap();
                let mut forged_headers = HeaderMap::new();
                forged_headers.insert(axum::http::header::COOKIE, axum::http::HeaderValue::from_str(&format!("silent_session={}", token)).unwrap());
                
                let _ = buildpacks::handle_project_action(State(state.clone()), forged_headers, axum::extract::Path(p_id.to_string()), Json(action_payload)).await;
            }
        } else {
            buildpacks::kill_room_surgical(&base_dir, port, p_id).await;
        }

        if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await { 
            let _: Result<(), _> = redis::cmd("DEL").arg(format!("project:{}:history_logs", p_id)).query_async(&mut redis_conn).await;
            let _: Result<(), _> = redis::cmd("DEL").arg(format!("project:{}:status", p_id)).query_async(&mut redis_conn).await; 
        }

        let _ = tokio::fs::remove_dir_all(base_dir).await;
    }

    let _ = sqlx::query("DELETE FROM projects WHERE id = $1").bind(p_id).execute(&state.pg_pool).await;
    let mongo_coll = state.mongo_db.collection::<mongodb::bson::Document>("projects");
    let _ = mongo_coll.delete_one(mongodb::bson::doc! { "project_id": p_id }).await;

    buildpacks::trigger_telegram_dashboard(&state).await;

    Ok(Json(ApiResponse { 
        status: "success".to_string(), 
        message: "The requested project data environment has been completely wiped clean.".to_string(), 
        role: None 
    }))
}

async fn exeio_gateway_redirect(State(pool): State<sqlx::PgPool>, req: Request) -> impl IntoResponse {

    let host_header = req.headers().get("x-silent-host")
        .or_else(|| req.headers().get("x-forwarded-host"))
        .or_else(|| req.headers().get(axum::http::header::HOST))
        .and_then(|h| h.to_str().ok())
        .unwrap_or("unknown");

    let domain = host_header.split(':').next().unwrap_or(host_header);

    let secure_token = uuid::Uuid::new_v4().to_string().replace('-', "")[..16].to_lowercase();

    let _ = sqlx::query("INSERT INTO free_tokens (token, platform) VALUES ($1, 'exeio')")
        .bind(&secure_token)
        .execute(&pool)
        .await;

    let destination_url = format!("https://{}/api/free-gateway/display?token={}", domain, secure_token);

    let encoded_destination = urlencoding::encode(&destination_url);

    let exeio_api = format!(
        "https://exe.io/api?api=7aba7e2da9ab3e40d7d9146abed3ce723f33d587&url={}",
        encoded_destination
    );

    let client = reqwest::Client::new();

    if let Ok(res) = client.get(&exeio_api).send().await {
        if let Ok(api_res) = res.json::<ExeIoGatewayResponse>().await {
            if api_res.status == "success" {
                if let Some(clean_url) = api_res.shortened_url {

                    return Response::builder()
                        .status(StatusCode::SEE_OTHER)
                        .header("Location", clean_url)
                        .body(Body::empty())
                        .unwrap();
                }
            }
        }
    }

    Response::builder()
        .status(StatusCode::SEE_OTHER)
        .header("Location", destination_url)
        .body(Body::empty())
        .unwrap()
}

async fn gplinks_gateway_redirect(State(pool): State<sqlx::PgPool>, req: Request) -> impl IntoResponse {

    let host_header = req.headers().get("x-silent-host")
        .or_else(|| req.headers().get("x-forwarded-host"))
        .or_else(|| req.headers().get(axum::http::header::HOST))
        .and_then(|h| h.to_str().ok())
        .unwrap_or("unknown");

    let domain = host_header.split(':').next().unwrap_or(host_header);

    let secure_token = uuid::Uuid::new_v4().to_string().replace('-', "")[..16].to_lowercase();

    let _ = sqlx::query("INSERT INTO free_tokens (token, platform) VALUES ($1, 'gplinks')")
        .bind(&secure_token)
        .execute(&pool)
        .await;

    let destination_url = format!("https://{}/api/free-gateway/display?token={}", domain, secure_token);

    let encoded_destination = urlencoding::encode(&destination_url);

    let gplinks_api = format!(
        "https://api.gplinks.com/api?api=463995960f81a3f8d2c9bf5b483716710383e09c&url={}",
        encoded_destination
    );

    let client = reqwest::Client::new();

    if let Ok(res) = client.get(&gplinks_api).send().await {
        if let Ok(api_res) = res.json::<GpLinksGatewayResponse>().await {
            if api_res.status == "success" {
                if let Some(clean_url) = api_res.shortened_url {

                    return Response::builder()
                        .status(StatusCode::SEE_OTHER)
                        .header("Location", clean_url)
                        .body(Body::empty())
                        .unwrap();
                }
            }
        }
    }

    Response::builder()
        .status(StatusCode::SEE_OTHER)
        .header("Location", destination_url)
        .body(Body::empty())
        .unwrap()
}

async fn create_whop_payment(
    State(pool): State<sqlx::PgPool>,
    headers: HeaderMap,
    Json(payload): Json<WhopCreateReq>,
) -> (StatusCode, Json<serde_json::Value>) {
    let username = match get_username_from_cookie(&headers) {
        Some(u) => u,
        None => return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"status": "error", "message": "Unauthorized"}))),
    };

    let user_row = match sqlx::query("SELECT id FROM users WHERE username = $1")
        .bind(&username)
        .fetch_optional(&pool)
        .await 
    {
        Ok(Some(row)) => row,
        Ok(None) => return (StatusCode::NOT_FOUND, Json(serde_json::json!({"status": "error", "message": "User record not found"}))),
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"status": "error", "message": format!("Database error: {}", e)}))),
    };

    let user_id: i32 = user_row.get("id");
    let plan_norm = payload.plan_type.to_lowercase();
    let dummy_trx = format!("WHOP_PENDING_{}", uuid::Uuid::new_v4().to_string()[..8].to_uppercase());

    let req_res = sqlx::query("INSERT INTO billing_requests (user_id, plan_requested, trx_id, screenshot_url) VALUES ($1, $2, $3, 'Whop Card Gateway') RETURNING id")
        .bind(user_id).bind(&plan_norm).bind(&dummy_trx)
        .fetch_one(&pool).await;

    let req_id: i32 = match req_res {
        Ok(row) => row.get("id"),
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"status": "error", "message": format!("Database Setup Error: {}", e)}))),
    };

    let _ = sqlx::query("UPDATE users SET pending_plan = $1 WHERE id = $2").bind(&plan_norm).bind(user_id).execute(&pool).await;

    let whop_plan_id = if plan_norm == "pro" {
        "plan_LnTnOxjyfps93" 
    } else {
        "plan_SZDh71tCrxgI4"
    };

    let whop_api_key = "apik_9Q7EgOrSwcTMl_C5248627_C_6e760e75f330dcd882cd6c117694e0fe9d2e3bb095b2b92d2d331c90ad9de0"; 

    let client = reqwest::Client::new();
    let whop_api_url = "https://api.whop.comonfigurations";

    let checkout_payload = serde_json::json!({
        "plan_id": whop_plan_id,
        "metadata": {
            "user_id": user_id.to_string(),
            "req_id": req_id.to_string(),
            "plan": plan_norm
        }
    });

    let response = client.post(whop_api_url)
        .header("Authorization", format!("Bearer {}", whop_api_key))
        .header("Content-Type", "application/json")
        .json(&checkout_payload)
        .send()
        .await;

    match response {
        Ok(res) => {
            let status = res.status();
            let res_text = res.text().await.unwrap_or_default();

            if status.is_success() {
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&res_text) {

                    if let Some(checkout_url) = parsed.get("purchase_url").and_then(|v| v.as_str()) {
                        return (StatusCode::OK, Json(serde_json::json!({
                            "status": "success",
                            "payment_url": checkout_url,
                            "message": "Secure checkout session generated successfully!"
                        })));
                    }
                }
            }

            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({
                "status": "error",
                "message": format!("Whop API Error: {} - {}", status, res_text)
            })))
        },
        Err(e) => (StatusCode::GATEWAY_TIMEOUT, Json(serde_json::json!({
            "status": "error",
            "message": format!("Failed to connect to Whop API: {}", e.to_string())
        })))
    }
}

async fn handle_whop_webhook(
    State(pool): State<sqlx::PgPool>,
    Json(payload): Json<WhopWebhookPayload>,
) -> (StatusCode, Json<serde_json::Value>) {

    if payload.event_type != "membership.went_active" 
       && payload.event_type != "membership.created" 
       && payload.event_type != "membership.activated" 
    {
        return (StatusCode::OK, Json(serde_json::json!({"status": "ignored"})));
    }

    let mut user_id: i32 = 0;
    let mut req_id: i32 = 0;
    let mut plan_requested = "basic".to_string();
    let mut username = "Unknown".to_string();
    let mut email = "Unknown".to_string();

    if let Some(meta) = &payload.data.metadata {
        if let Some(u_id_str) = meta.get("user_id").and_then(|v| v.as_str()) {
            user_id = u_id_str.parse().unwrap_or(0);
        }
        if let Some(r_id_str) = meta.get("req_id").and_then(|v| v.as_str()) {
            req_id = r_id_str.parse().unwrap_or(0);
        }
        if let Some(plan_str) = meta.get("plan").and_then(|v| v.as_str()) {
            plan_requested = plan_str.to_string();
        }
    }

    if user_id == 0 {
        if let Some(whop_user) = &payload.data.user {
            if let Some(whop_email) = &whop_user.email {
                email = whop_email.clone();

                let user_row = sqlx::query("SELECT id, username FROM users WHERE email = $1")
                    .bind(&email)
                    .fetch_optional(&pool)
                    .await
                    .unwrap_or(None);

                if let Some(row) = user_row {
                    user_id = row.get("id");
                    username = row.get("username");
                }
            }
        }

        if let Some(prod) = &payload.data.product {
            if let Some(title) = &prod.title {
                if title.to_lowercase().contains("pro") {
                    plan_requested = "pro".to_string();
                } else {
                    plan_requested = "basic".to_string();
                }
            }
        }
    } else {

        let user_row = sqlx::query("SELECT username, email FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_optional(&pool)
            .await
            .unwrap_or(None);

        if let Some(row) = user_row {
            username = row.get("username");
            email = row.get("email");
        }
    }

    if user_id == 0 { 
        return (StatusCode::OK, Json(serde_json::json!({"status": "success", "message": "User not found or test event skipped safely"}))); 
    }

    let plan_norm = plan_requested.to_lowercase();
    let target_amount = if plan_norm == "pro" { 1000 } else { 500 };
    let display_price = if plan_norm == "pro" { "$7.00" } else { "$3.00" };

    process_payment_match(&pool, req_id, user_id, plan_requested.clone(), target_amount, &payload.data.id).await;

    let bot_token = "8940591240:AAFgkoyuHqivL1xj6QeQId-awlunVj-kJxQ"; 
    let chat_id = "8167904992";     

    let telegram_text = format!(
        "💳 *New Card Payment Received!*\n\n\
         👤 *User:* {}\n\
         📧 *Email:* {}\n\
         📦 *Plan:* {}\n\
         💵 *Amount:* {}\n\
         🛍️ *Gateway:* Whop (Card / Apple Pay)\n\
         🆔 *Membership ID:* {}\n\
         ✅ *Status:* Activated Successfully",
        username, email, plan_norm.to_uppercase(), display_price, payload.data.id
    );

    let client = reqwest::Client::new();
    let telegram_url = format!("https://api.telegram.org/bot{}/sendMessage", bot_token);
    let _ = client.post(&telegram_url)
        .json(&serde_json::json!({
            "chat_id": chat_id,
            "text": telegram_text,
            "parse_mode": "Markdown"
        }))
        .send()
        .await;

    (StatusCode::OK, Json(serde_json::json!({"status": "success"})))
}

async fn create_crypto_payment(
    State(pool): State<sqlx::PgPool>,
    headers: HeaderMap,
    Json(payload): Json<CryptoCreateReq>,
) -> (StatusCode, Json<serde_json::Value>) {
    let username = match get_username_from_cookie(&headers) {
        Some(u) => u,
        None => return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"status": "error", "message": "Unauthorized"}))),
    };

    let user_row = sqlx::query("SELECT id FROM users WHERE username = $1").bind(&username).fetch_one(&pool).await.unwrap();
    let user_id: i32 = user_row.get("id");
    let plan_norm = payload.plan_type.to_lowercase();
    let crypto_usd_amount = if plan_norm == "pro" { "7.00" } else { "3.00" };

    let cryptomus_merchant_id = "f51ed50f-4cfd-45e3-bc09-cc61ff3805de"; 
    let cryptomus_payment_key = "gdbylt05mNXD3YcDrRNEOzcIM7vE10vqJQhyVvs8gdMrmgmdnIflbRiDqsWYj0wX6XeMOwfbCjwP3Jz9amG0bxhoOKenAVnS4TEvikCkwjKAL424NiHx6ucWasyJJDH2"; 

    let compounded_order_id = format!("{}_{}", user_id, plan_norm);

    let invoice_data = CryptomusInvoicePayload {
        amount: crypto_usd_amount.to_string(),
        currency: "USD".to_string(),
        order_id: compounded_order_id, 
        url_callback: "https://router.silenthost.site/api/payment/crypto-webhook".to_string(),
    };

    let body_str = serde_json::to_string(&invoice_data).unwrap();

    use base64::{Engine as _, engine::general_purpose};
    let b64_body = general_purpose::STANDARD.encode(body_str.as_bytes());
    let to_hash = format!("{}{}", b64_body, cryptomus_payment_key);
    let sign = format!("{:x}", md5::compute(to_hash.as_bytes()));

    let client = reqwest::Client::new();
    let response = client.post("https://api.cryptomus.com/v1/payment")
        .header("merchant", cryptomus_merchant_id)
        .header("sign", sign)
        .header("Content-Type", "application/json")
        .json(&invoice_data)
        .send().await;

    match response {
        Ok(res) => {
            let http_status = res.status();
            let res_text = res.text().await.unwrap_or_default();

            if let Ok(parsed_res) = serde_json::from_str::<serde_json::Value>(&res_text) {

                if parsed_res.get("state").and_then(|v| v.as_i64()) == Some(0) {
                    if let Some(result_data) = parsed_res.get("result") {
                        if let Some(url) = result_data.get("url").and_then(|v| v.as_str()) {
                            return (StatusCode::OK, Json(serde_json::json!({
                                "status": "success",
                                "payment_url": url,
                                "message": "Crypto checkout session generated!"
                            })));
                        }
                    }
                }

                return (http_status, Json(serde_json::json!({
                    "status": "error",
                    "message": parsed_res
                })));
            }

            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({
                "status": "error",
                "message": format!("HTTP {} - Raw Payload: {}", http_status, res_text)
            })))
        },
        Err(e) => (StatusCode::GATEWAY_TIMEOUT, Json(serde_json::json!({
            "status": "error",
            "message": format!("Cryptomus Connection Timeout: {}", e.to_string())
        })))
    }
}

async fn handle_crypto_webhook(
    State(pool): State<sqlx::PgPool>,
    Json(payload): Json<CryptomusWebhookBody>,
) -> StatusCode {

    if payload.status != "paid" && payload.status != "completed" {
        return StatusCode::OK;
    }

    let parts: Vec<&str> = payload.order_id.split('_').collect();
    if parts.len() < 2 {

        return StatusCode::OK;
    }

    let u_id: i32 = parts[0].parse().unwrap_or(0);
    let plan_requested = parts[1].to_string();

    if u_id == 0 { return StatusCode::OK; }

    let user_row = sqlx::query("SELECT username, email FROM users WHERE id = $1")
        .bind(u_id)
        .fetch_optional(&pool)
        .await
        .unwrap_or(None);

    if let Some(row) = user_row {
        let username: String = row.get("username");
        let email: String = row.get("email");

        let required_amount = if plan_requested.to_lowercase() == "pro" { 1000 } else { 500 };

        process_payment_match(&pool, 0, u_id, plan_requested.clone(), required_amount, &payload.uuid).await;

        let bot_token = "8940591240:AAFgkoyuHqivL1xj6QeQId-awlunVj-kJxQ"; 
        let chat_id = "8167904992";     

        let telegram_text = format!(
            "💰 *New Crypto Payment Received!*\n\n\
             👤 *User:* {}\n\
             📧 *Email:* {}\n\
             📦 *Plan:* {}\n\
             💵 *Amount:* {}{}\n\
             💳 *Gateway:* Cryptomus (Crypto)\n\
             🆔 *TxID:* {}\n\
             ✅ *Status:* Activated Successfully",
            username, email, plan_requested.to_uppercase(), payload.amount, payload.currency, payload.uuid
        );

        let client = reqwest::Client::new();
        let telegram_url = format!("https://api.telegram.org/bot{}/sendMessage", bot_token);
        let _ = client.post(&telegram_url)
            .json(&serde_json::json!({
                "chat_id": chat_id,
                "text": telegram_text,
                "parse_mode": "Markdown"
            }))
            .send()
            .await;

    }

    StatusCode::OK
}

async fn handle_sms_webhook(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<SmsWebhookPayload>) -> StatusCode {
    if headers.get("authorization").and_then(|h| h.to_str().ok()) != Some("Bearer SILENT_SECURE_TOKEN_786") { return StatusCode::UNAUTHORIZED; }

    let raw_msg = payload.message.clone();

    let tid = extract_tid(&raw_msg); 
    let amount = extract_amount(&raw_msg);

    if tid.is_empty() { return StatusCode::OK; }

    let _ = sqlx::query("INSERT INTO sms_transactions (trx_id, amount, is_processed) VALUES ($1, $2, FALSE) ON CONFLICT DO NOTHING")
        .bind(&tid).bind(amount).execute(&pool).await;

    let req = sqlx::query("SELECT id, user_id, plan_requested FROM billing_requests WHERE trx_id = $1").bind(&tid).fetch_optional(&pool).await.unwrap();

    if let Some(r) = req {
        process_payment_match(&pool, r.get("id"), r.get("user_id"), r.get("plan_requested"), amount, &tid).await;
    }
    StatusCode::OK
}

#[derive(Deserialize)]
struct TokenQuery {
    token: String,
}

async fn free_gateway_redirect(State(pool): State<sqlx::PgPool>, req: Request) -> impl IntoResponse {

    let host_header = req.headers().get("x-silent-host")
        .or_else(|| req.headers().get("x-forwarded-host"))
        .or_else(|| req.headers().get(axum::http::header::HOST))
        .and_then(|h| h.to_str().ok())
        .unwrap_or("unknown");

    let domain = host_header.split(':').next().unwrap_or(host_header);

    let secure_token = uuid::Uuid::new_v4().to_string().replace('-', "")[..16].to_lowercase();

    let _ = sqlx::query("INSERT INTO free_tokens (token, platform) VALUES ($1, 'shrinkme')")
        .bind(&secure_token)
        .execute(&pool)
        .await;

    let destination_url = format!("https://{}/api/free-gateway/display?token={}", domain, secure_token);

    let shrinkme_api = format!(
        "https://shrinkme.io/api?api=97f2bffa1f6e7a2cdba1a38940c61651deba65f4&url={}&format=text",
        destination_url
    );

    let client = reqwest::Client::new();
    if let Ok(res) = client.get(&shrinkme_api).send().await {
        if let Ok(short_url) = res.text().await {
            let clean_url = short_url.trim();
            if clean_url.starts_with("http") {
                return Response::builder()
                    .status(StatusCode::SEE_OTHER)
                    .header("Location", clean_url)
                    .body(Body::empty())
                    .unwrap();
            }
        }
    }

    Response::builder()
        .status(StatusCode::SEE_OTHER)
        .header("Location", destination_url)
        .body(Body::empty())
        .unwrap()
}

async fn free_gateway_display(State(pool): State<sqlx::PgPool>, Query(q): Query<TokenQuery>) -> impl IntoResponse {

    let token_check = sqlx::query(
        "SELECT platform FROM free_tokens WHERE token = $1 AND created_at >= NOW() - INTERVAL '30 minutes'"
    )
    .bind(&q.token)
    .fetch_optional(&pool)
    .await
    .unwrap_or(None);

    if token_check.is_none() {
        return axum::response::Html(
            "<h1>🚨 Security Link Expired or Invalid!</h1><p>Please Complete Your Task Within 30 minutes</p>"
        ).into_response();
    }

    let row = token_check.unwrap();
    let platform: String = row.get::<Option<String>, _>("platform").unwrap_or_else(|| "unknown".to_string());

    let free_key_code = format!("SILENT-FREE-{}-{}", platform.to_uppercase(), uuid::Uuid::new_v4().to_string()[..8].to_uppercase());
    let expiry = Utc::now() + Duration::days(1); 

    let _ = sqlx::query(
        "INSERT INTO access_keys (key_code, plan_type, status, duration_days, max_uses, valid_until) 
         VALUES ($1, 'free', 'Active', 1, 1, $2)"
    )
    .bind(&free_key_code)
    .bind(expiry)
    .execute(&pool)
    .await;

    let html_page = format!(r#"
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Free Key Unlocked - Silent Hosting</title>
        <style>
            body {{
                margin: 0; padding: 0; font-family: 'Segoe UI', sans-serif;
                background: linear-gradient(135deg, #020E18, #0A0A10, #082236);
                color: white; height: 100vh; display: flex; align-items: center; justify-content: center;
            }}
            .glass-panel {{
                background: rgba(69, 243, 255, 0.05);
                backdrop-filter: blur(15px);
                border: 1px solid rgba(69, 243, 255, 0.2);
                border-radius: 20px; padding: 40px; text-align: center; max-width: 450px; width: 90%;
                box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37), 0 0 20px rgba(69, 243, 255, 0.2);
            }}
            h1 {{ color: #45F3FF; font-size: 2em; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 1px; }}
            p {{ color: #a0aec0; font-size: 1em; line-height: 1.5; margin-bottom: 25px; }}
            .key-box {{
                background: rgba(0, 0, 0, 0.4); border: 2px dashed #45F3FF;
                padding: 15px; font-size: 1.3em; font-weight: bold; color: #FFB000;
                letter-spacing: 2px; border-radius: 10px; margin-bottom: 25px;
                font-family: monospace; word-break: break-all;
            }}
            .btn {{
                display: inline-block; padding: 12px 30px; background: #45F3FF;
                color: #020E18; text-decoration: none; border-radius: 30px; font-weight: bold;
                border: none; transition: all 0.3s ease; text-transform: uppercase; cursor: pointer;
            }}
            .btn:hover {{ box-shadow: 0 0 15px #45F3FF; transform: scale(1.02); }}
        </style>
        <script>
            function copyKey() {{
                var keyText = document.getElementById("rawKey").innerText;
                navigator.clipboard.writeText(keyText);
                alert("Access Key Copied Successfully! Now open the app and paste it to activate your Free Tier Plan.");
            }}
        </script>
    </head>
    <body>
        <div class="glass-panel">
            <h1>Key Unlocked!</h1>
            <p>Thank you for supporting us by watching ads. Your 24-Hour Free Tier Access Key is generated safely below:</p>
            <div class="key-box" id="rawKey">{}</div>
            <button class="btn" onclick="copyKey()">Copy Access Key</button>
        </div>
    </body>
    </html>
    "#, free_key_code);

    axum::response::Html(html_page).into_response()
}

async fn send_vercel_otp(email: &str, username: &str, otp: &str) -> bool {
    let client = reqwest::Client::new();
    let payload = serde_json::json!({
        "to": email,
        "username": username,
        "otp": otp
    });
    let res = client.post("https://mailer-api-olive.vercel.app/api/send")
        .header("Authorization", "Bearer SILENT_SECURE_TOKEN_786")
        .json(&payload)
        .send()
        .await;

    match res {
        Ok(response) => response.status().is_success(),
        Err(_) => false,
    }
}

async fn start_billing_guard_daemon(state: AppState) {
    let pool = state.pg_pool.clone(); 
    let client = reqwest::Client::new(); // 🌟 مائیکروسروس فارورڈنگ کے لیے ایچ ٹی ٹی پی کلائنٹ

    loop {
        // ہر 60 سیکنڈ بعد کلسٹر پلانز اسکین ہوں گے
        tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;

        let expired_users_res = sqlx::query(
            "SELECT id, username FROM users WHERE plan_expiry <= NOW() AND plan_type != 'none'"
        )
        .fetch_all(&pool)
        .await;

        if let Ok(users) = expired_users_res {
            for row in users {
                let user_id: i32 = row.get("id");
                let _username: String = row.get("username");

                // 🌟 فکس 1: اب ہم 'language' بھی سلیکٹ کریں گے تاکہ ریموٹ ورکرز کو ہٹ مار سکیں
                let projects_res = sqlx::query(
                    "SELECT id, port, language FROM projects WHERE user_id = $1 AND status IN ('Online', 'Starting', 'Building')"
                )
                .bind(user_id)
                .fetch_all(&pool)
                .await;

                    if let Ok(projects) = projects_res {
                        for proj_row in projects {
                            let proj_id: i32 = proj_row.get("id");
                            let port: i32 = proj_row.try_get("port").unwrap_or(8000);
                            let language: String = proj_row.try_get::<String, _>("language").unwrap_or_default().to_lowercase();

                            let base_dir = format!("/app/data/user_{}/project_{}", user_id, proj_id);

                            // 🌟 فکس 2: لنگویج کی بنیاد پر ریموٹ سروسز (Python, Node, Go) کے پروسیسز سسپینڈ کرنا
                            let worker_stop_url = if language == "python" {
                                Some("http://silent-python:8085/api/worker/stop")
                            } else if language.contains("node") || language.contains("javascript") || language.contains("js") {
                                Some("http://silent-nodejs:8086/api/worker/stop")
                            } else if language == "go" || language == "golang" { // 🔒 کارگو اینٹی کولیژن لاک
                                Some("http://silent-golang:8087/api/worker/stop")
                            } else {
                                None
                            };

                            if let Some(stop_url) = worker_stop_url {
                                let worker_payload = serde_json::json!({
                                    "project_id": proj_id.to_string(),
                                    "user_id": user_id,
                                    "base_dir": base_dir,
                                    "port": port,
                                    "action": "stop"
                                });
                                // پرائیویٹ لنک پر انسٹنٹ اسٹاپ سگنل فارورڈ کرنا
                                let _ = client.post(stop_url).json(&worker_payload).send().await;
                            } else {
                                // لوکل پروجیکٹس رن ٹائم پروسیس کلنگ (Rust, PHP, Static HTML)
                                kill_room(&base_dir, port).await;
                            }

                            // 🌟 فکس 3: ریڈیس لائیو اسٹیٹس پلس انتہائی کسٹمر فرینڈلی الرٹ لاگز سنکنگ
                            if let Ok(mut redis_conn) = state.redis_client.get_multiplexed_tokio_connection().await {
                                let _: Result<(), _> = redis::cmd("SET").arg(format!("project:{}:status", proj_id)).arg("Offline").query_async(&mut redis_conn).await;
                                
                                let log_key = format!("project:{}:history_logs", proj_id);
                                let channel_name = format!("project:{}:updates", proj_id);
                                let expire_log = "⚠️ [NOTICE] Subscription expired. Your application has been suspended safely. Please renew your plan to reactivate workspace.\n";
                                
                                let _: Result<i32, _> = redis::cmd("RPUSH").arg(&log_key).arg(expire_log).query_async(&mut redis_conn).await;
                                let msg = serde_json::json!({ "project_id": proj_id, "type": "log_update", "value": expire_log.trim() }).to_string();
                                let _: Result<(), _> = redis::cmd("PUBLISH").arg(&channel_name).arg(msg).query_async(&mut redis_conn).await;
                            }

                            // 🟢 ایکسپائرڈ پروجیکٹ کے تمام آئسولیٹڈ ڈیٹا بیسز کا صفایا
                            let db_rows = sqlx::query("SELECT db_type, db_name, db_user FROM project_databases WHERE project_id = $1")
                                .bind(proj_id)
                                .fetch_all(&pool)
                                .await
                                .unwrap_or_default();

                            for db_row in db_rows {
                                let db_type: String = db_row.get("db_type");
                                let db_name: String = db_row.get("db_name");
                                let db_user: String = db_row.get("db_user");

                                if db_type == "postgres" {
                                    if let Ok(master_url) = std::env::var("POSTGRES_URL") {
                                        if let Ok(master_pool) = sqlx::PgPool::connect(&master_url).await {
                                            let _ = sqlx::query(&format!("DROP DATABASE IF EXISTS {};", db_name)).execute(&master_pool).await;
                                            let _ = sqlx::query(&format!("DROP USER IF EXISTS {};", db_user)).execute(&master_pool).await;
                                        }
                                    }
                                }
                            }
                            
                            let _ = sqlx::query("DELETE FROM project_databases WHERE project_id = $1").bind(proj_id).execute(&pool).await;

                            let log_path = format!("{}/app.log", base_dir);
                            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&log_path) {
                                use std::io::Write;
                                let _ = writeln!(f, "[STATUS_UPDATE] Offline");
                                let _ = writeln!(f, "\n[SYSTEM ALERT] Subscription expired. Total Infrastructure and databases suspended dynamically.");
                            }
                        }
                    }

                // پوسٹگریس مین میٹرکس اپڈیٹ پائپ لائن
                let _ = sqlx::query("UPDATE projects SET status = 'Offline' WHERE user_id = $1")
                    .bind(user_id)
                    .execute(&pool)
                    .await;

                // یوزر کو واپس 'No Plan' زون میں رول بیک کرنا
                let _ = sqlx::query("UPDATE users SET plan = 'No Plan', plan_type = 'none', plan_expiry = NULL, used_gateways = '' WHERE id = $1")
                    .bind(user_id)
                    .execute(&pool)
                    .await;
            }
        }
    }
}


#[derive(Deserialize)]
struct DbProvisionReq {
    r#type: String, 
}

async fn get_project_databases(
    State(pool): State<sqlx::PgPool>,
    headers: HeaderMap,
    Path(project_id): Path<String>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    let is_owner = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM projects p JOIN users u ON p.user_id = u.id WHERE p.id = $1 AND u.username = $2)"
    ).bind(p_id).bind(&username).fetch_one(&pool).await.unwrap_or(false);

    if !is_owner { return Err(StatusCode::FORBIDDEN); }

    let rows = sqlx::query("SELECT db_type FROM project_databases WHERE project_id = $1")
        .bind(p_id).fetch_all(&pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut db_map = serde_json::Map::new();
    db_map.insert("mongodb".to_string(), serde_json::Value::Null);
    db_map.insert("redis".to_string(), serde_json::Value::Null);
    db_map.insert("postgres".to_string(), serde_json::Value::Null);
    db_map.insert("mysql".to_string(), serde_json::Value::Null);

    for row in rows {
        let db_type: String = row.get("db_type");
        db_map.insert(db_type, serde_json::Value::String("connected".to_string()));
    }

    Ok(Json(serde_json::Value::Object(db_map)))
}

fn get_plan_limits(plan_type: &str) -> (i32, i32, i32) {
    match plan_type.to_lowercase().as_str() {
        "pro" => (2048, 5120, 1024),   
        "basic" => (1024, 2048, 512),  
        "free" => (500, 500, 100),     
        _ => (0, 0, 0),                
    }
}

async fn create_project_database(
    State(pool): State<sqlx::PgPool>,
    headers: HeaderMap,
    Path(project_id): Path<String>,
    Json(payload): Json<DbProvisionReq>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let db_type = payload.r#type.to_lowercase();

    let user_row = sqlx::query("SELECT u.id, u.plan_type FROM projects p JOIN users u ON p.user_id = u.id WHERE p.id = $1 AND u.username = $2")
        .bind(p_id).bind(&username).fetch_optional(&pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let row = user_row.ok_or(StatusCode::FORBIDDEN)?;
    let user_id: i32 = row.get("id");
    let plan_type: String = row.get("plan_type");

    let (_, _, db_limit) = get_plan_limits(&plan_type);

    let db_hash = uuid::Uuid::new_v4().to_string().replace('-', "")[..12].to_lowercase();
    let db_name = format!("silent_cluster_{}", db_hash); 
    let db_user = format!("silent_role_{}", db_hash);
    let db_pass = uuid::Uuid::new_v4().to_string().replace('-', "")[..16].to_lowercase();

    let mut success_provision = false;
    let mut actual_internal_url = "connected".to_string();

    if db_type == "postgres" {
        let master_url = std::env::var("DATABASE_URL").or_else(|_| std::env::var("POSTGRES_URL")).unwrap_or_default();
        if let Some(at_idx) = master_url.find('@') {
            let host_port_part = &master_url[at_idx + 1..];
            let host_port = match host_port_part.find('/') { Some(slash_idx) => &host_port_part[..slash_idx], None => host_port_part };
            actual_internal_url = format!("postgresql://{}:{}@{}/{}", db_user, db_pass, host_port, db_name);
        }
        let create_db_cmd = format!("CREATE DATABASE {};", db_name);
        let create_user_cmd = format!("CREATE USER {} WITH PASSWORD '{}';", db_user, db_pass);
        let assign_owner_cmd = format!("ALTER DATABASE {} OWNER TO {};", db_name, db_user);
        if let Ok(_) = sqlx::query(&create_db_cmd).execute(&pool).await {
            let _ = sqlx::query(&create_user_cmd).execute(&pool).await;
            let _ = sqlx::query(&assign_owner_cmd).execute(&pool).await;
            success_provision = true;
        }
    } else if db_type == "mongodb" {
        if let Ok(real_mongo_url) = std::env::var("MONGO_URL") {
            if let Ok(client) = MongoClient::with_uri_str(&real_mongo_url).await {
                let db = client.database(&db_name);
                let create_mongo_user = mongodb::bson::doc! { "createUser": &db_user, "pwd": &db_pass, "roles": [ { "role": "dbOwner", "db": &db_name } ] };
                let _ = db.create_collection("init_pool").await;
                if let Ok(_) = db.run_command(create_mongo_user).await {
                    let mut base_part = real_mongo_url.clone();
                    if let Some(q_idx) = base_part.find('?') { base_part = base_part[..q_idx].to_string(); }
                    let mut clean_host = "127.0.0.1:27017".to_string();
                    if base_part.starts_with("mongodb://") {
                        let remains = &base_part["mongodb://".len()..];
                        if let Some(at_idx) = remains.rfind('@') {
                            let host_part = &remains[at_idx + 1..];
                            clean_host = match host_part.find('/') { Some(s_idx) => host_part[..s_idx].to_string(), None => host_part.to_string() };
                        } else {
                            clean_host = match remains.find('/') { Some(s_idx) => remains[..s_idx].to_string(), None => remains.to_string() };
                        }
                    }
                    actual_internal_url = format!("mongodb://{}:{}@{}/{}?authSource={}", db_user, db_pass, clean_host, db_name, db_name);
                    success_provision = true;
                }
            }
        }
    } else if db_type == "redis" {
        if let Ok(real_redis_url) = std::env::var("REDIS_URL") {
            if let Ok(_) = redis::Client::open(real_redis_url.clone()) {
                actual_internal_url = real_redis_url;
                success_provision = true;
            }
        }
    } else if db_type == "mysql" {
        if let Ok(real_mysql_url) = std::env::var("MYSQL_URL") {
            if let Ok(mysql_pool) = sqlx::MySqlPool::connect(&real_mysql_url).await {
                let create_mysql_db = format!("CREATE DATABASE IF NOT EXISTS {};", db_name);
                if let Ok(_) = sqlx::query(&create_mysql_db).execute(&mysql_pool).await {
                    actual_internal_url = real_mysql_url.replace("/railway", &format!("/{}", db_name));
                    success_provision = true;
                }
            }
        }
    }

    if !success_provision {
        return Ok(Json(serde_json::json!({ "status": "error", "message": "Database complete isolation provisioning failed" })));
    }

    let exists = sqlx::query_scalar::<_, bool>("SELECT EXISTS(SELECT 1 FROM project_databases WHERE project_id = $1 AND db_type = $2)").bind(p_id).bind(&db_type).fetch_one(&pool).await.unwrap_or(false);

    let insert_res = if !exists {

        sqlx::query("INSERT INTO project_databases (project_id, user_id, db_type, db_name, db_user, db_password, internal_url, storage_limit_mb) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)")
        .bind(p_id).bind(user_id).bind(&db_type).bind(&db_name).bind(&db_user).bind(&db_pass).bind(&actual_internal_url).bind(db_limit).execute(&pool).await
    } else {
        sqlx::query("UPDATE project_databases SET db_name = $1, db_user = $2, db_password = $3, internal_url = $4 WHERE project_id = $5 AND db_type = $6")
            .bind(&db_name).bind(&db_user).bind(&db_pass).bind(&actual_internal_url).bind(p_id).bind(&db_type).execute(&pool).await
    };

    match insert_res {
        Ok(_) => Ok(Json(serde_json::json!({ "status": "success", "message": "Database Connected Successfully under Masked Isolation Mode!", "url": "connected" }))),
        Err(_) => Err(StatusCode::BAD_REQUEST)
    }
}

async fn delete_project_database(
    State(pool): State<sqlx::PgPool>,
    headers: HeaderMap,
    Path(project_id): Path<String>,
    Json(payload): Json<DbProvisionReq>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let db_type = payload.r#type.to_lowercase();

    let db_info = sqlx::query("SELECT db_name, db_user FROM project_databases WHERE project_id = $1 AND db_type = $2")
        .bind(p_id).bind(&db_type).fetch_optional(&pool).await.unwrap_or(None);

    if let Some(row) = db_info {
        let db_name: String = row.get("db_name");
        let db_user: String = row.get("db_user");

        if db_type == "postgres" {
            if let Ok(master_url) = std::env::var("POSTGRES_URL") {
                if let Ok(master_pool) = sqlx::PgPool::connect(&master_url).await {
                    let _ = sqlx::query(&format!("DROP DATABASE IF EXISTS {};", db_name)).execute(&master_pool).await;
                    let _ = sqlx::query(&format!("DROP USER IF EXISTS {};", db_user)).execute(&master_pool).await;
                }
            }
        }

    }

    let _ = sqlx::query("DELETE FROM project_databases WHERE project_id = $1 AND db_type = $2")
        .bind(p_id).bind(&db_type).execute(&pool).await;

    Ok(Json(serde_json::json!({
        "status": "success",
        "message": "Database Disconnected!"
    })))
}

async fn admin_update_links(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<UpdateLinksReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let json_val = serde_json::to_string(&payload.links).unwrap_or_else(|_| "[]".to_string());
    let _ = sqlx::query(
        "INSERT INTO global_settings (key_name, key_value) VALUES ('buy_links', $1) 
         ON CONFLICT (key_name) DO UPDATE SET key_value = EXCLUDED.key_value"
    ).bind(json_val).execute(&pool).await;

    Ok(Json(ApiResponse { status: "success".to_string(), message: "Purchase links updated successfully!".to_string(), role: None }))
}

#[derive(Deserialize)]
struct ExportReq { secret_key: String }

#[derive(Deserialize)]
struct ImportReq { 
    export_url: String,
    secret_key: String 
}

async fn export_system_data(Query(q): Query<ExportReq>) -> Result<axum::response::Response, StatusCode> {
    let expected_key = std::env::var("MIGRATION_SECRET").unwrap_or_else(|_| "SILENT_HOST_AF".to_string());
    if q.secret_key != expected_key { return Err(StatusCode::FORBIDDEN); }

    let tmp_dir = "/tmp/migration_export";
    let zip_path = "/tmp/silent_hosting_backup.zip";

    let _ = tokio::fs::remove_dir_all(tmp_dir).await;
    let _ = tokio::fs::create_dir_all(tmp_dir).await;
    let _ = tokio::fs::remove_file(zip_path).await;

    let export_script = r#"
    export PIP_BREAK_SYSTEM_PACKAGES=1

    # 1. PostgreSQL (Master)
    if [ ! -z "$DATABASE_URL" ]; then
        echo "[EXPORT] Dumping PostgreSQL..."
        pg_dump "$DATABASE_URL" -f /tmp/migration_export/database.sql || true
    fi

    # 2. MongoDB
    if [ ! -z "$MONGO_URL" ]; then
        echo "[EXPORT] Dumping MongoDB..."
        mongodump --uri="$MONGO_URL" --archive=/tmp/migration_export/mongo_dump.gz --gzip || true
    fi

    # 3. MySQL (Smart Heredoc Python Parser)
    if [ ! -z "$MYSQL_URL" ]; then
        echo "[EXPORT] Dumping MySQL..."
        cat << 'EOF' > /tmp/export_mysql.py
import urllib.parse, os
url = urllib.parse.urlparse(os.environ.get('MYSQL_URL', ''))
if url.hostname:
    cmd = f'mysqldump -u {url.username} -p"{url.password}" -h {url.hostname} -P {url.port or 3306} {url.path[1:]} > /tmp/migration_export/mysql_dump.sql'
    os.system(cmd)
EOF
        python3 /tmp/export_mysql.py || true
    fi

    # 4. Redis (VIP Deep Dump via Native Python Serialization)
    if [ ! -z "$REDIS_URL" ]; then
        echo "[EXPORT] Dumping Redis Cache..."
        pip install redis > /dev/null 2>&1 || true
        cat << 'EOF' > /tmp/export_redis.py
import os, pickle
try:
    import redis
    url = os.environ.get('REDIS_URL', '')
    if url:
        r = redis.from_url(url)
        data = {}
        for key in r.scan_iter():
            data[key] = r.dump(key)
        with open('/tmp/migration_export/redis_dump.pkl', 'wb') as f:
            pickle.dump(data, f)
except Exception as e:
    print('Redis Export Error:', e)
EOF
        python3 /tmp/export_redis.py || true
    fi

    # 5. Pack Everything (User Files + All Databases)
    cd /app/data && zip -r /tmp/silent_hosting_backup.zip .
    cd /tmp/migration_export && zip -j /tmp/silent_hosting_backup.zip *
    "#;

    let status = tokio::process::Command::new("sh")
        .arg("-c").arg(export_script)
        .status().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !status.success() { return Err(StatusCode::INTERNAL_SERVER_ERROR); }

    let bytes = tokio::fs::read(zip_path).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let _ = tokio::fs::remove_dir_all(tmp_dir).await;
    let _ = tokio::fs::remove_file(zip_path).await;

    Ok(axum::response::Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/zip")
        .header("Content-Disposition", "attachment; filename=\"silent_hosting_backup.zip\"")
        .body(axum::body::Body::from(bytes))
        .unwrap())
}

async fn import_system_data(State(_pool): State<sqlx::PgPool>, Json(payload): Json<ImportReq>) -> Result<Json<ApiResponse>, StatusCode> {
    let expected_key = std::env::var("MIGRATION_SECRET").unwrap_or_else(|_| "SILENT_HOST_AF".to_string());
    if payload.secret_key != expected_key { return Err(StatusCode::FORBIDDEN); }

    let export_url = payload.export_url.clone();

    tokio::spawn(async move {

        let zip_path = "/tmp/incoming_backup.zip";
        let extract_dir = "/tmp/migration_import";

        let _ = tokio::fs::remove_dir_all(extract_dir).await;
        let _ = tokio::fs::remove_file(zip_path).await;
        let _ = tokio::fs::create_dir_all(extract_dir).await;

        let wget_cmd = format!("wget -O {} \"{}\"", zip_path, export_url);
        if let Ok(status) = tokio::process::Command::new("sh").arg("-c").arg(&wget_cmd).status().await {
            if status.success() {

                let unzip_cmd = format!("unzip -o {} -d {}", zip_path, extract_dir);
                let _ = tokio::process::Command::new("sh").arg("-c").arg(&unzip_cmd).status().await;

                let import_script = r#"
                export PIP_BREAK_SYSTEM_PACKAGES=1
                cd "$EXTRACT_DIR"

                # 1. Restore PostgreSQL
                if [ -f "database.sql" ] && [ ! -z "$DATABASE_URL" ]; then
                    echo "[MIGRATION] 🗄️ Restoring PostgreSQL..."
                    psql "$DATABASE_URL" -f database.sql || true
                    rm database.sql
                fi

                # 2. Restore MongoDB
                if [ -f "mongo_dump.gz" ] && [ ! -z "$MONGO_URL" ]; then
                    echo "[MIGRATION] 🍃 Restoring MongoDB..."
                    mongorestore --uri="$MONGO_URL" --archive=mongo_dump.gz --gzip --drop || true
                    rm mongo_dump.gz
                fi

                # 3. Restore MySQL
                if [ -f "mysql_dump.sql" ] && [ ! -z "$MYSQL_URL" ]; then
                    echo "[MIGRATION] 🐬 Restoring MySQL..."
                    cat << 'EOF' > /tmp/import_mysql.py
import urllib.parse, os
url = urllib.parse.urlparse(os.environ.get('MYSQL_URL', ''))
if url.hostname:
    cmd = f'mysql -u {url.username} -p"{url.password}" -h {url.hostname} -P {url.port or 3306} {url.path[1:]} < mysql_dump.sql'
    os.system(cmd)
EOF
                    python3 /tmp/import_mysql.py || true
                    rm mysql_dump.sql
                fi

                # 4. Restore Redis
                if [ -f "redis_dump.pkl" ] && [ ! -z "$REDIS_URL" ]; then
                    echo "[MIGRATION] 🔴 Restoring Redis Cache..."
                    pip install redis > /dev/null 2>&1 || true
                    cat << 'EOF' > /tmp/import_redis.py
import os, pickle
try:
    import redis
    url = os.environ.get('REDIS_URL', '')
    if url:
        r = redis.from_url(url)
        with open('redis_dump.pkl', 'rb') as f:
            data = pickle.load(f)
        for key, val in data.items():
            try:
                r.restore(key, 0, val, replace=True)
            except Exception as e:
                pass
except Exception as e:
    print('Redis Import Error:', e)
EOF
                    python3 /tmp/import_redis.py || true
                    rm redis_dump.pkl
                fi

                # 5. Restore User Environment Files
                echo "[MIGRATION] 📂 Moving user files..."
                cp -r * /app/data/ 2>/dev/null || true
                "#;

                let _ = tokio::process::Command::new("sh")
                    .env("EXTRACT_DIR", extract_dir)
                    .arg("-c").arg(import_script)
                    .status().await;

            } else {

            }
        }

        let _ = tokio::fs::remove_dir_all(extract_dir).await;
        let _ = tokio::fs::remove_file(zip_path).await;
    });

    Ok(Json(ApiResponse { 
        status: "success".into(), 
        message: "4x Multi-DB Migration started! Check server logs.".into(), 
        role: None 
    }))
}

const VIP_ERROR_PAGE: &str = r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Alert - Silent Hosting</title>
    <style>
        body {
            margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #020E18, #0A0A10, #082236);
            color: white; height: 100vh; display: flex; align-items: center; justify-content: center;
            overflow: hidden;
        }
        .glass-panel {
            background: rgba(69, 243, 255, 0.05);
            backdrop-filter: blur(15px);
            -webkit-backdrop-filter: blur(15px);
            border: 1px solid rgba(69, 243, 255, 0.2);
            border-radius: 20px;
            padding: 50px; text-align: center; max-width: 500px;
            box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37), 0 0 20px rgba(69, 243, 255, 0.2);
            animation: float 4s ease-in-out infinite;
        }
        @keyframes float { 0% { transform: translateY(0px); } 50% { transform: translateY(-10px); } 100% { transform: translateY(0px); } }
        h1 { color: #45F3FF; font-size: 2.5em; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 2px; }
        p { color: #a0aec0; font-size: 1.1em; line-height: 1.6; margin-bottom: 30px; }
        .btn {
            display: inline-block; padding: 12px 30px; background: rgba(69, 243, 255, 0.1);
            color: #45F3FF; text-decoration: none; border-radius: 30px; font-weight: bold;
            border: 1px solid #45F3FF; transition: all 0.3s ease; text-transform: uppercase; letter-spacing: 1px;
        }
        .btn:hover { background: #45F3FF; color: #020E18; box-shadow: 0 0 15px #45F3FF; }
        .status-badge {
            display: inline-block; padding: 5px 15px; border-radius: 20px; background: rgba(255, 85, 85, 0.2);
            color: #ff5555; border: 1px solid #ff5555; font-size: 0.9em; margin-bottom: 20px; font-weight: bold;
            text-transform: uppercase; letter-spacing: 2px;
        }
        .status-Building { color: #f6ad55; border-color: #f6ad55; background: rgba(246, 173, 85, 0.2); }
        .status-Starting { color: #f6ad55; border-color: #f6ad55; background: rgba(246, 173, 85, 0.2); }
    </style>
</head>
<body>
    <div class="glass-panel">
        <div class="status-badge status-{STATUS}">{STATUS}</div>
        <h1>System Alert</h1>
        <p>The requested application is currently unavailable, crashed, or has not been deployed yet. Please manage your deployments via the dashboard.</p>
        <a href="https://www.silenthost.site" class="btn">Deploy Project</a>
    </div>
</body>
</html>
"#;

// ============================================================================
// 🌐 DYNAMIC CLUSTER REVERSE PROXY HOST ROUTER (100% TYPE SAFE)
// ============================================================================
async fn host_router(State(pool): State<sqlx::PgPool>, req: Request) -> Response {
    let host_header = req.headers().get("x-silent-host")
        .or_else(|| req.headers().get("x-forwarded-host"))
        .or_else(|| req.headers().get(axum::http::header::HOST))
        .and_then(|h| h.to_str().ok())
        .unwrap_or("unknown");

    let domain = host_header.split(':').next().unwrap_or(host_header);

    // پورٹ، اسٹیٹس اور لنگویج میٹرکس کی سلیکشن کوئیری
    let project_row = sqlx::query("SELECT port, status, language FROM projects WHERE domain = $1 OR custom_domain = $1")
        .bind(domain)
        .fetch_optional(&pool).await.unwrap_or(None);

    if let Some(row) = project_row {
        // 🌟 فکس: ٹائپ انفرنس کے امکانی پھڈوں کو روکنے کے لیے یہاں ہارڈ لاک ٹائپ کاسٹنگ بائنڈ کر دی ہے
        let p: Option<i32> = row.try_get::<Option<i32>, _>("port").unwrap_or(None);
        let status: String = row.try_get::<String, _>("status").unwrap_or_else(|_| "Unknown".to_string());
        let language: String = row.try_get::<String, _>("language").unwrap_or_else(|_| "text".to_string());

        if status == "Online" {
            if let Some(port) = p {
                let path = req.uri().path_and_query().map(|x| x.as_str()).unwrap_or("/");
                
                // کلسٹر مائیکروسروسز کے پرائیویٹ انٹرنل لنکس کی متحرک روٹنگ پائپ لائن
                let lang_low = language.to_lowercase();
                
                let target_host = if lang_low == "python" {
                    "silent-python"
                } else if lang_low.contains("node") || lang_low.contains("javascript") || lang_low.contains("js") {
                    "silent-nodejs"
                } else if lang_low == "go" || lang_low == "golang" { // 🔒 کارگو اینٹی کولیژن لاک
                    "silent-golang"
                } else {
                    "127.0.0.1" // 👈 لوکل رن ٹائم پروجیکٹس (Rust, PHP, Static HTML)
                };

                let target_uri = format!("http://{}:{}{}", target_host, port, path);

                let client = reqwest::Client::builder()
                    .redirect(reqwest::redirect::Policy::none())
                    .no_gzip().no_brotli().no_deflate() 
                    .build().unwrap();

                let mut reqwest_headers = reqwest::header::HeaderMap::new();
                for (name, value) in req.headers() {
                    let name_str = name.as_str().to_lowercase();
                    if name_str != "host" && name_str != "connection" && name_str != "upgrade" {
                        if let Ok(n) = reqwest::header::HeaderName::from_bytes(name.as_str().as_bytes()) {
                            if let Ok(v) = reqwest::header::HeaderValue::from_bytes(value.as_bytes()) {
                                reqwest_headers.insert(n, v);
                            }
                        }
                    }
                }

                let method = match req.method().as_str() {
                    "GET" => reqwest::Method::GET, 
                    "POST" => reqwest::Method::POST, 
                    "PUT" => reqwest::Method::PUT, 
                    "DELETE" => reqwest::Method::DELETE, 
                    "PATCH" => reqwest::Method::PATCH, 
                    _ => reqwest::Method::GET,
                };

                let body_bytes = axum::body::to_bytes(req.into_body(), usize::MAX).await.unwrap_or_default();
                let proxy_req = client.request(method, &target_uri).headers(reqwest_headers).body(body_bytes);

                match proxy_req.send().await {
                    Ok(res) => {
                        let status_code = axum::http::StatusCode::from_u16(res.status().as_u16()).unwrap_or(axum::http::StatusCode::OK);
                        let mut response_builder = axum::response::Response::builder().status(status_code);

                        for (name, value) in res.headers() {
                            let name_str = name.as_str().to_lowercase();
                            if name_str != "transfer-encoding" && name_str != "connection" {
                                if let Ok(n) = axum::http::HeaderName::from_bytes(name.as_str().as_bytes()) {
                                    if let Ok(v) = axum::http::HeaderValue::from_bytes(value.as_bytes()) {
                                        response_builder = response_builder.header(n, v);
                                    }
                                }
                            }
                        }

                        let res_bytes = res.bytes().await.unwrap_or_default();
                        return response_builder.body(axum::body::Body::from(res_bytes))
                            .unwrap_or_else(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Proxy Body Error").into_response());
                    },
                    Err(_) => {
                        let html = VIP_ERROR_PAGE.replace("{STATUS}", "CRASHED");
                        return axum::response::Html(html).into_response();
                    }
                }
            }
        } else {
            let html = VIP_ERROR_PAGE.replace("{STATUS}", &status.to_uppercase());
            return axum::response::Html(html).into_response();
        }
    }

    if domain.contains(".silenthost.site") && !domain.starts_with("router.") && !domain.starts_with("www.") && !domain.starts_with("dashboard.") {
        let html = VIP_ERROR_PAGE.replace("{STATUS}", "NOT FOUND");
        return (StatusCode::NOT_FOUND, axum::response::Html(html)).into_response();
    }

    let serve_dir = ServeDir::new("public").not_found_service(ServeFile::new("public/index.html"));
    match serve_dir.oneshot(req).await {
        Ok(res) => res.into_response(),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Dashboard Server Error").into_response(),
    }
}

fn get_username_from_cookie(headers: &HeaderMap) -> Option<String> {
    let cookie_header = headers.get("cookie")?.to_str().ok()?;
    for cookie in cookie_header.split(';') {
        let cookie = cookie.trim();
        if cookie.starts_with("silent_session=") {
            let token = &cookie["silent_session=".len()..];
            let data = decode::<Claims>(token, &DecodingKey::from_secret(SECRET_KEY), &Validation::default()).ok()?;
            return Some(data.claims.sub);
        }
    }
    None
}

async fn is_admin(headers: &HeaderMap, pool: &sqlx::PgPool) -> bool {
    if let Some(user) = get_username_from_cookie(headers) {
        let role: Option<String> = sqlx::query("SELECT role FROM users WHERE username = $1").bind(&user).fetch_optional(pool).await.unwrap().map(|r| r.get("role"));
        return role == Some("admin".to_string());
    }
    false
}

async fn logout_user() -> (StatusCode, HeaderMap, Json<ApiResponse>) {
    let mut headers = HeaderMap::new();
    headers.insert(SET_COOKIE, "silent_session=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0".parse().unwrap());
    (StatusCode::OK, headers, Json(ApiResponse { status: "success".to_string(), message: "Logged out!".to_string(), role: None }))
}

async fn register_user(State(pool): State<sqlx::PgPool>, Json(payload): Json<RegisterRequest>) -> (StatusCode, Json<ApiResponse>) {
    let action = payload.action.unwrap_or_else(|| "send_otp".to_string());
    let email = payload.email.trim().to_lowercase();
    let username = payload.username.trim().to_lowercase();

    if action == "send_otp" {

        let user_exists = sqlx::query_scalar::<_, bool>("SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 OR email = $2)")
            .bind(&username).bind(&email).fetch_one(&pool).await.unwrap_or(false);

        if user_exists {
            return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".into(), message: "Username or Email already registered!".into(), role: None }));
        }

        let mut otp: String = uuid::Uuid::new_v4().to_string().chars().filter(|c| c.is_ascii_digit()).take(5).collect();
        if otp.len() < 5 { otp = "78625".to_string(); }

        let hashed_pass = hash(payload.password.unwrap_or_default(), DEFAULT_COST).unwrap();

        let insert_temp = sqlx::query("
            INSERT INTO temp_otps (email, otp, name, username, password_hash, purpose)
            VALUES ($1, $2, $3, $4, $5, 'signup')
            ON CONFLICT (email) DO UPDATE SET 
                otp = EXCLUDED.otp, name = EXCLUDED.name, username = EXCLUDED.username, 
                password_hash = EXCLUDED.password_hash, purpose = 'signup', created_at = CURRENT_TIMESTAMP
        ")
        .bind(&email).bind(&otp).bind(payload.name.unwrap_or_default()).bind(&username).bind(hashed_pass).execute(&pool).await;

        if insert_temp.is_err() {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { status: "error".into(), message: "Database handshake failed!".into(), role: None }));
        }

        // پلان ایکسپائر ہونے کی وجہ سے میلر کو بیک گراؤنڈ میں چلنے دیا اور ہمیشہ سکسیس ریٹرن کی
        let _ = send_vercel_otp(&email, &username, &otp).await;
        return (StatusCode::OK, Json(ApiResponse { status: "success".into(), message: "OTP broadcasted successfully! (Bypassed)".into(), role: None }));
    } 
    else if action == "verify" {
        let temp_row = sqlx::query("SELECT name, password_hash FROM temp_otps WHERE email = $1 AND username = $2 AND purpose = 'signup'")
            .bind(&email).bind(&username).fetch_optional(&pool).await.unwrap_or(None);

        if let Some(row) = temp_row {
            // یہاں او ٹی پی ویریفیکیشن کی شرط بائی پاس کر دی گئی ہے، اب کوئی بھی کوڈ ورک کرے گا
            let name: String = row.get("name");
            let password_hash: String = row.get("password_hash");
            let role = if username == "aflovevip" { "admin" } else { "user" };

            let final_reg = sqlx::query("INSERT INTO users (name, username, email, password_hash, role) VALUES ($1, $2, $3, $4, $5)")
                .bind(name).bind(&username).bind(&email).bind(password_hash).bind(role).execute(&pool).await;

            if final_reg.is_ok() {
                let _ = sqlx::query("DELETE FROM temp_otps WHERE email = $1").bind(&email).execute(&pool).await;
                return (StatusCode::CREATED, Json(ApiResponse { status: "success".into(), message: "Account Securely Provisioned!".into(), role: None }));
            }
        }
        return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".into(), message: "Invalid or expired OTP token!".into(), role: None }));
    }

    (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".into(), message: "Invalid action configuration.".into(), role: None }))
}


async fn forgot_password(State(pool): State<sqlx::PgPool>, Json(payload): Json<ForgotPasswordReq>) -> (StatusCode, Json<ApiResponse>) {
    let identity = payload.identity.trim().to_lowercase();

    let user_info = sqlx::query("SELECT username, email FROM users WHERE username = $1 OR email = $1")
        .bind(&identity).fetch_optional(&pool).await.unwrap_or(None);

    let (username, email) = match user_info {
        Some(row) => (row.get::<String, _>("username"), row.get::<String, _>("email")),
        None => return (StatusCode::NOT_FOUND, Json(ApiResponse { status: "error".into(), message: "Account infrastructure not found!".into(), role: None }))
    };

    if payload.action == "send_otp" {
        let mut otp: String = uuid::Uuid::new_v4().to_string().chars().filter(|c| c.is_ascii_digit()).take(5).collect();
        if otp.len() < 5 { otp = "99786".to_string(); }

        let insert_temp = sqlx::query("
            INSERT INTO temp_otps (email, otp, purpose) VALUES ($1, $2, 'forgot')
            ON CONFLICT (email) DO UPDATE SET otp = EXCLUDED.otp, purpose = 'forgot', created_at = CURRENT_TIMESTAMP
        ")
        .bind(&email).bind(&otp).execute(&pool).await;

        if insert_temp.is_err() {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { status: "error".into(), message: "Recovery handshake initialization failed.".into(), role: None }));
        }

        if send_vercel_otp(&email, &username, &otp).await {
            return (StatusCode::OK, Json(ApiResponse { status: "success".into(), message: "Recovery code transmitted successfully.".into(), role: None }));
        } else {
            return (StatusCode::BAD_GATEWAY, Json(ApiResponse { status: "error".into(), message: "Vercel edge mailer transmission timeout.".into(), role: None }));
        }
    } 
    else if payload.action == "verify_otp" {
        let incoming_otp = payload.otp.unwrap_or_default().trim().to_string();
        let active_otp: Option<String> = sqlx::query_scalar("SELECT otp FROM temp_otps WHERE email = $1 AND purpose = 'forgot'")
            .bind(&email).fetch_optional(&pool).await.unwrap_or(None);

        if let Some(stored_otp) = active_otp {
            if stored_otp == incoming_otp {
                return (StatusCode::OK, Json(ApiResponse { status: "success".into(), message: "OTP validation cleared.".into(), role: None }));
            }
        }
        return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".into(), message: "Invalid verification token code!".into(), role: None }));
    } 
    else if payload.action == "reset_password" {
        let incoming_otp = payload.otp.unwrap_or_default().trim().to_string();
        let new_pass = payload.new_password.unwrap_or_default();

        let active_otp: Option<String> = sqlx::query_scalar("SELECT otp FROM temp_otps WHERE email = $1 AND purpose = 'forgot'")
            .bind(&email).fetch_optional(&pool).await.unwrap_or(None);

        if let Some(stored_otp) = active_otp {
            if stored_otp == incoming_otp && !new_pass.is_empty() {
                let hashed = hash(new_pass, DEFAULT_COST).unwrap();
                let update_user = sqlx::query("UPDATE users SET password_hash = $1 WHERE email = $2")
                    .bind(hashed).bind(&email).execute(&pool).await;

                if update_user.is_ok() {
                    let _ = sqlx::query("DELETE FROM temp_otps WHERE email = $1").bind(&email).execute(&pool).await;
                    return (StatusCode::OK, Json(ApiResponse { status: "success".into(), message: "Credentials successfully re-encrypted in main database!".into(), role: None }));
                }
            }
        }
        return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".into(), message: "Handshake session expired or invalid.".into(), role: None }));
    }

    (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".into(), message: "Invalid action routing.".into(), role: None }))
}

async fn login_user(State(pool): State<sqlx::PgPool>, Json(payload): Json<LoginRequest>) -> (StatusCode, HeaderMap, Json<ApiResponse>) {
    let mut headers = HeaderMap::new();
    let result = sqlx::query("SELECT id, username, password_hash, role, is_suspended, failed_attempts, lock_until FROM users WHERE username = $1 OR email = $1").bind(&payload.username_or_email).fetch_optional(&pool).await.unwrap();
    if let Some(row) = result {
        let is_suspended: bool = row.get("is_suspended");
        if is_suspended { return (StatusCode::FORBIDDEN, headers, Json(ApiResponse { status: "error".to_string(), message: "Account Suspended by Admin!".to_string(), role: None })); }

        let user_id: i32 = row.get("id"); let hash: String = row.get("password_hash"); let role: String = row.get("role"); let failed_attempts: i32 = row.get("failed_attempts"); let lock_until: Option<chrono::DateTime<Utc>> = row.try_get("lock_until").ok();
        if let Some(locked_time) = lock_until { if Utc::now() < locked_time { return (StatusCode::FORBIDDEN, headers, Json(ApiResponse { status: "error".to_string(), message: "Account Locked!".to_string(), role: None })); } }

        if verify(&payload.password, &hash).unwrap() {
            let _ = sqlx::query("UPDATE users SET failed_attempts = 0, lock_until = NULL WHERE id = $1").bind(user_id).execute(&pool).await;
            let exp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as usize + (60 * 60 * 24);
            let token = encode(&Header::default(), &Claims { sub: row.get("username"), role: role.clone(), exp }, &EncodingKey::from_secret(SECRET_KEY)).unwrap();
            headers.insert(SET_COOKIE, format!("silent_session={}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=86400", token).parse().unwrap());
            return (StatusCode::OK, headers, Json(ApiResponse { status: "success".to_string(), message: "Login Successful!".to_string(), role: Some(role) }));
        } else {
            let new_attempts = failed_attempts + 1;
            if new_attempts >= 5 {
                let _ = sqlx::query("UPDATE users SET failed_attempts = $1, lock_until = $2 WHERE id = $3").bind(new_attempts).bind(Utc::now() + Duration::hours(5)).bind(user_id).execute(&pool).await;
                return (StatusCode::FORBIDDEN, headers, Json(ApiResponse { status: "error".to_string(), message: "Locked for 5 Hours!".to_string(), role: None }));
            }
            let _ = sqlx::query("UPDATE users SET failed_attempts = $1 WHERE id = $2").bind(new_attempts).bind(user_id).execute(&pool).await;
            return (StatusCode::UNAUTHORIZED, headers, Json(ApiResponse { status: "error".to_string(), message: "Wrong Password!".to_string(), role: None }));
        }
    }
    (StatusCode::NOT_FOUND, headers, Json(ApiResponse { status: "error".to_string(), message: "Not Found!".to_string(), role: None }))
}

async fn check_user(State(pool): State<sqlx::PgPool>, Json(payload): Json<CheckRequest>) -> Json<CheckResponse> {
    let query = if payload.field_type == "email" { "SELECT id FROM users WHERE email = $1" } else { "SELECT id FROM users WHERE username = $1" };
    let result = sqlx::query(query).bind(&payload.value).fetch_optional(&pool).await.unwrap();
    Json(CheckResponse { exists: result.is_some(), message: "".to_string() })
}

async fn update_settings(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<SettingsUpdateReq>) -> (StatusCode, Json<ApiResponse>) {
    let username = match get_username_from_cookie(&headers) { Some(u) => u, None => return (StatusCode::UNAUTHORIZED, Json(ApiResponse { status: "error".to_string(), message: "Unauthorized".to_string(), role: None })) };

    let user_row = sqlx::query("SELECT id, password_hash FROM users WHERE username = $1").bind(&username).fetch_optional(&pool).await.unwrap();
    if user_row.is_none() { return (StatusCode::NOT_FOUND, Json(ApiResponse { status: "error".to_string(), message: "User not found!".to_string(), role: None })); }
    let row = user_row.unwrap(); let user_id: i32 = row.get("id"); let current_hash: String = row.get("password_hash");

    if payload.update_type == "profile" {
        let n_user = payload.new_username.unwrap_or(username.clone());
        let n_email = payload.new_email.unwrap_or_default();
        let _ = sqlx::query("UPDATE users SET username = $1, email = $2 WHERE id = $3").bind(&n_user).bind(&n_email).bind(user_id).execute(&pool).await;
        return (StatusCode::OK, Json(ApiResponse { status: "success".to_string(), message: "Profile Updated Successfully!".to_string(), role: None }));
    } 
    else if payload.update_type == "password" {
        let old_pass = payload.old_password.unwrap_or_default();
        let n_pass = payload.new_password.unwrap_or_default();
        if verify(&old_pass, &current_hash).unwrap_or(false) {
            let hashed = hash(n_pass, DEFAULT_COST).unwrap();
            let _ = sqlx::query("UPDATE users SET password_hash = $1 WHERE id = $2").bind(hashed).bind(user_id).execute(&pool).await;
            return (StatusCode::OK, Json(ApiResponse { status: "success".to_string(), message: "Password Updated Successfully!".to_string(), role: None }));
        } else { return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".to_string(), message: "Old password is incorrect!".to_string(), role: None })); }
    }
    (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".to_string(), message: "Invalid request type!".to_string(), role: None }))
}

async fn delete_account(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<DeleteAccountReq>) -> (StatusCode, Json<ApiResponse>) {
    let username = match get_username_from_cookie(&headers) { Some(u) => u, None => return (StatusCode::UNAUTHORIZED, Json(ApiResponse { status: "error".to_string(), message: "Unauthorized".to_string(), role: None })) };
    let user_row = sqlx::query("SELECT id FROM users WHERE username = $1 AND email = $2").bind(&username).bind(&payload.email).fetch_optional(&pool).await.unwrap();
    if user_row.is_none() { return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".to_string(), message: "Email mismatch! Cannot delete account.".to_string(), role: None })); }
    let user_id: i32 = user_row.unwrap().get("id");

    let _ = sqlx::query("DELETE FROM users WHERE id = $1").bind(user_id).execute(&pool).await;
    let user_dir = format!("/app/data/user_{}", user_id);
    kill_room(&user_dir, 0).await;
    let _ = tokio::fs::remove_dir_all(&user_dir).await;
    (StatusCode::OK, Json(ApiResponse { status: "success".to_string(), message: "Account and projects permanently deleted.".to_string(), role: None }))
}

async fn get_profile(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<UserProfile>, StatusCode> {
    let username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?; 
    let result = sqlx::query("SELECT username, email, plan, plan_type, pending_plan, declined_plan, decline_reason, role, plan_expiry FROM users WHERE username = $1")
        .bind(&username).fetch_optional(&pool).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let maint_str = sqlx::query_scalar::<_, String>("SELECT key_value FROM global_settings WHERE key_name = 'maintenance_mode'").fetch_one(&pool).await.unwrap_or("false".into());
    let mut msg = sqlx::query_scalar::<_, String>("SELECT key_value FROM global_settings WHERE key_name = 'announcement_msg'").fetch_one(&pool).await.unwrap_or("".into());
    let exp_str = sqlx::query_scalar::<_, String>("SELECT key_value FROM global_settings WHERE key_name = 'announcement_expiry'").fetch_one(&pool).await.unwrap_or("".into());

    if !exp_str.is_empty() {
        if let Ok(exp_date) = chrono::DateTime::parse_from_rfc3339(&exp_str) {
            if chrono::Utc::now() > exp_date.with_timezone(&chrono::Utc) { msg = "".to_string(); }
        }
    }

    if let Some(row) = result {
        let plan: String = row.get("plan");
        let is_paid = plan == "Pro Plan" || plan == "Basic Plan";
        let expiry_opt: Option<chrono::DateTime<Utc>> = row.try_get("plan_expiry").ok().flatten();

        Ok(Json(UserProfile {
            username: row.get("username"), email: row.get("email"), plan, is_paid,
            role: row.get("role"), access_key: "hidden".to_string(), plan_type: row.get("plan_type"),
            pending_plan: row.try_get("pending_plan").ok().flatten(),
            declined_plan: row.try_get("declined_plan").ok().flatten(),
            decline_reason: row.try_get("decline_reason").ok().flatten(),
            plan_expiry: expiry_opt.map(|d| d.to_rfc3339()),
            maintenance_mode: maint_str == "true", 
            announcement_msg: msg,                 
        }))
    } else { Err(StatusCode::NOT_FOUND) }
}

async fn get_projects(State(state): State<AppState>, headers: HeaderMap) -> Result<Json<Vec<Project>>, StatusCode> {
    let username = get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;

    let rows = sqlx::query("SELECT p.id, p.name FROM projects p JOIN users u ON p.user_id = u.id WHERE u.username = $1 ORDER BY p.id DESC")
        .bind(&username)
        .fetch_all(&state.pg_pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut projects = Vec::new();
    let mut redis_conn = state.redis_client.get_multiplexed_tokio_connection().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    for row in rows {
        let id: i32 = row.get("id");
        let name: String = row.get("name");

        let status: String = redis::cmd("GET")
            .arg(format!("project:{}:status", id))
            .query_async(&mut redis_conn)
            .await
            .unwrap_or_else(|_| "Offline".to_string());

        projects.push(Project { 
            id: id.to_string(), 
            name, 
            status, 
            domain: None 
        });
    }

    Ok(Json(projects))
}

async fn redeem_key(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<RedeemReq>) -> (StatusCode, Json<ApiResponse>) {
    let username = match get_username_from_cookie(&headers) { 
        Some(u) => u, 
        None => return (StatusCode::UNAUTHORIZED, Json(ApiResponse { status: "error".to_string(), message: "Unauthorized".to_string(), role: None })) 
    };

    let key_res = sqlx::query("SELECT id, key_code, plan_type, status, duration_days, max_uses, used_count, valid_until FROM access_keys WHERE key_code = $1").bind(&payload.access_key).fetch_optional(&pool).await.unwrap();

    if let Some(row) = key_res {
        let status: String = row.get("status"); 
        let valid_until: Option<chrono::DateTime<Utc>> = row.try_get("valid_until").ok(); 
        let used: i32 = row.get("used_count"); 
        let max: i32 = row.get("max_uses");

        if status != "Active" { return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".to_string(), message: "Key is Paused or Expired!".to_string(), role: None })); }
        if used >= max { return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".to_string(), message: "Key usage limit reached!".to_string(), role: None })); }
        if let Some(valid_date) = valid_until { if Utc::now() > valid_date { return (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".to_string(), message: "Key redemption window expired!".to_string(), role: None })); } }

        let plan_type: String = row.get("plan_type"); 
        let duration: i32 = row.get("duration_days");
        let plan_name = if plan_type == "pro" { "Pro Plan" } else if plan_type == "basic" { "Basic Plan" } else { "Free Tier" };

        let safe_duration = if duration > 36500 { 36500 } else { duration as i64 };
        let mut expiry = Utc::now() + Duration::days(safe_duration);

        let user_info = sqlx::query("SELECT plan_type, plan_expiry, used_gateways FROM users WHERE username = $1")
            .bind(&username).fetch_one(&pool).await.unwrap();

        let current_plan_type: String = user_info.get("plan_type");
        let current_expiry: Option<chrono::DateTime<Utc>> = user_info.try_get("plan_expiry").ok().flatten();
        let mut used_gateways: String = user_info.try_get("used_gateways").unwrap_or_else(|_| "".to_string());

        // 🛡️ چیک کریں کہ آیا یوزر کا موجودہ پلان ابھی ایکٹو (Active) ہے یا نہیں
        let is_current_plan_active = current_expiry.is_some() && current_expiry.unwrap() > Utc::now();

        if is_current_plan_active {
            // 🚫 پرو پلان والے یوزر کو بیسک یا فری کی ریڈیم کرنے سے روکیں
            if current_plan_type == "pro" && plan_type != "pro" {
                return (StatusCode::BAD_REQUEST, Json(ApiResponse { 
                    status: "error".to_string(), 
                    message: "You are already on Pro Plan! Lower tier keys cannot be redeemed.".to_string(), 
                    role: None 
                }));
            }
            
            // 🚫 بیسک پلان والے یوزر کو فری کی ریڈیم کرنے سے روکیں
            if current_plan_type == "basic" && plan_type == "free" {
                return (StatusCode::BAD_REQUEST, Json(ApiResponse { 
                    status: "error".to_string(), 
                    message: "You are already upgraded plan! Free Tier keys cannot be redeemed.".to_string(), 
                    role: None 
                }));
            }
        }

        // 🔄 ٹائم پلس (Stacking) اور اپ گریڈیشن لاجک میٹرکس
        if is_current_plan_active && current_plan_type == plan_type {
            // ➕ اگر پلان سیم ہے تو ٹائم پلس (Plus) ہوگا ریپلیس نہیں!
            if plan_type == "free" {
                let key_code: String = row.get("key_code");
                let platform = if key_code.contains("SHRINKME") { "shrinkme" } 
                               else if key_code.contains("GPLINKS") { "gplinks" } 
                               else if key_code.contains("EXEIO") { "exeio" } 
                               else { "unknown" };

                if platform != "unknown" {
                    let gateways_list: Vec<&str> = used_gateways.split(',').collect();
                    if gateways_list.contains(&platform) {
                        return (StatusCode::BAD_REQUEST, Json(ApiResponse { 
                            status: "error".to_string(), 
                            message: format!("آپ اس 24 گھنٹے کے سائیکل میں {} کی ایک بار استعمال کر چکے ہیں! اضافی ٹائم کے لیے کوئی دوسرا پلیٹ فارم ٹرائی کریں۔", platform.to_uppercase()), 
                            role: None 
                        }));
                    }
                    if used_gateways.is_empty() { used_gateways = platform.to_string(); } 
                    else { used_gateways = format!("{},{}", used_gateways, platform); }
                }
            }
            // پرانے ایکٹو ٹائم میں نیا ٹائم پلس کریں
            expiry = current_expiry.unwrap() + Duration::days(safe_duration);
        } else {
            // 🚀 یہ تب چلے گا جب یوزر بالکل نیا پلان لے رہا ہو یا نچلے پلان سے اونچے پلان پر اپ گریڈ ہو رہا ہو
            expiry = Utc::now() + Duration::days(safe_duration);
            if plan_type == "free" {
                let key_code: String = row.get("key_code");
                let platform = if key_code.contains("SHRINKME") { "shrinkme" } 
                               else if key_code.contains("GPLINKS") { "gplinks" } 
                               else if key_code.contains("EXEIO") { "exeio" } 
                               else { "unknown" };
                if platform != "unknown" { used_gateways = platform.to_string(); } 
                else { used_gateways = "".to_string(); }
            } else {
                used_gateways = "".to_string();
            }
        }

        // ڈیٹا بیس میں پلان اور نئی ایکسپائری ڈیٹ سیٹ کریں
        let _ = sqlx::query("UPDATE users SET plan = $1, plan_type = $2, pending_plan = NULL, plan_expiry = $3, used_gateways = $4 WHERE username = $5")
            .bind(&plan_name).bind(&plan_type).bind(expiry).bind(&used_gateways).bind(&username).execute(&pool).await;

        let _ = sqlx::query("UPDATE access_keys SET used_count = used_count + 1 WHERE id = $1").bind(row.get::<i32, _>("id")).execute(&pool).await;

        return (StatusCode::OK, Json(ApiResponse { status: "success".to_string(), message: format!("{} Successfully Activated! Validity extended safely.", plan_name), role: None }));
    }

    (StatusCode::BAD_REQUEST, Json(ApiResponse { status: "error".to_string(), message: "Invalid Key!".to_string(), role: None }))
}


async fn get_key_links(State(pool): State<sqlx::PgPool>) -> Json<Vec<BuyLink>> {
    let result = sqlx::query("SELECT key_value FROM global_settings WHERE key_name = 'buy_links'")
        .fetch_optional(&pool).await.unwrap_or(None);

    if let Some(row) = result {
        let json_str: String = row.get("key_value");
        if let Ok(links) = serde_json::from_str::<Vec<BuyLink>>(&json_str) {
            return Json(links);
        }
    }
    Json(vec![])
}

async fn get_process_ram_usage(base_dir: &str) -> i32 {
    let pid_path = format!("{}/run.pid", base_dir);
    if let Ok(pid_str) = tokio::fs::read_to_string(&pid_path).await {
        let pid = pid_str.trim();
        let cmd = format!("ps -o rss= -p {} | awk '{{sum+=$1}} END {{print sum}}'", pid);

        if let Ok(output) = tokio::process::Command::new("sh").arg("-c").arg(&cmd).output().await {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let kb: i32 = stdout.trim().parse().unwrap_or(0);
            return kb / 1024; 
        }
    }
    0
}

// ============================================================================
// 🔒 PRIVATE NETWORK WORKER ROUTER CONFIGURATION MATRIX
// ============================================================================
fn get_remote_worker_base_url(language: &str) -> Option<&'static str> {
    let lang = language.to_lowercase();
    if lang == "python" {
        Some(PYTHON_WORKER_URL)
    } else if lang.contains("node") || lang.contains("javascript") || lang.contains("js") {
        Some(NODEJS_WORKER_URL)
    } else if lang == "go" || lang == "golang" {
        Some(GOLANG_WORKER_URL)
    } else {
        None
    }
}

// ============================================================================
// 📊 1. DYNAMIC TELEMETRY DETAILS ENGINE (Local Check vs Private Microservice Proxy)
// ============================================================================
async fn get_project_details(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>) -> (StatusCode, Json<serde_json::Value>) {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'get_project_details' triggered for Proj ID: '{}'", project_id);
    let username = match crate::get_username_from_cookie(&headers) { 
        Some(u) => u, 
        None => return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"message": "Unauthorized"}))) 
    };
    let p_id: i32 = match project_id.parse() { 
        Ok(id) => id, 
        Err(_) => return (StatusCode::BAD_REQUEST, Json(serde_json::json!({"message": "Invalid Project ID"}))) 
    };

    match sqlx::query("SELECT p.language, p.domain, p.custom_domain, p.build_cmd, p.start_cmd, p.ram_total, p.storage_total, u.id as u_id, u.plan_type FROM projects p JOIN users u ON p.user_id = u.id WHERE p.id = $1 AND u.username = $2")
        .bind(p_id).bind(&username).fetch_optional(&state.pg_pool).await 
    {
        Ok(Some(r)) => {
            let language = r.try_get::<String, _>("language").unwrap_or_default().to_lowercase();
            println!("🔍 [CLUSTER RAW LOG] DB Lookup Success. Language Framework resolved as: '{}'", language);
            
            if let Some(worker_url) = get_remote_worker_base_url(&language) {
                let client = reqwest::Client::new();
                let target_endpoint = format!("{}/project/{}/details", worker_url, p_id);
                println!("🔍 [CLUSTER RAW LOG] Proxying telemetry request to Remote Worker Endpoint: {}", target_endpoint);
                
                match client.get(&target_endpoint)
                    .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
                    .timeout(std::time::Duration::from_secs(5)).send().await 
                {
                    Ok(res) => {
                        let status_code = res.status();
                        let raw_body = res.text().await.unwrap_or_else(|_| "{}".to_string());
                        println!("🔍 [CLUSTER RAW LOG] Worker Details Raw Status: {} | Raw Body:\n{}", status_code, raw_body);
                        if let Ok(worker_json) = serde_json::from_str::<serde_json::Value>(&raw_body) {
                            return (StatusCode::OK, Json(worker_json));
                        }
                    },
                    Err(e) => println!("❌ [CLUSTER RAW LOG] Connection error proxying telemetry layout: {:?}", e)
                }
            }

            // لوکل پروجیکٹس رن ٹائم مینی فیسٹ (Rust, PHP, Static HTML)
            let domain = r.try_get::<String, _>("domain").ok();
            let custom_domain = r.try_get::<String, _>("custom_domain").ok();
            let build_cmd = r.try_get::<String, _>("build_cmd").unwrap_or_default();
            let start_cmd = r.try_get::<String, _>("start_cmd").unwrap_or_default();
            let ram_total: i32 = r.try_get::<i32, _>("ram_total").unwrap_or(1024);
            let storage_total: i32 = r.try_get::<i32, _>("storage_total").unwrap_or(1024);
            let u_id: i32 = r.get::<i32, _>("u_id");
            let plan_type = r.try_get::<String, _>("plan_type").unwrap_or_else(|_| "none".to_string());

            let mut redis_conn = state.redis_client.get_multiplexed_tokio_connection().await.unwrap();
            let status: String = redis::cmd("GET").arg(format!("project:{}:status", p_id)).query_async(&mut redis_conn).await.unwrap_or_else(|_| "Offline".to_string());

            let base_dir = format!("/app/data/user_{}/project_{}", u_id, p_id);
            let storage_used_bytes = crate::get_dir_size(&base_dir).unwrap_or(0);
            let storage_used_mb = storage_used_bytes / (1024 * 1024); 

            let mut ram_used = 0;
            if status == "Online" {
                ram_used = get_process_ram_usage(&base_dir).await;
                if ram_used <= 0 { ram_used = 15; }
            } else if status == "Building" || status == "Starting" {
                ram_used = 45; 
            }

            (StatusCode::OK, Json(serde_json::json!({
                "status": status, "domain": domain, "custom_domain": custom_domain, "build_cmd": build_cmd, "start_cmd": start_cmd,
                "uptime": "Active", "ram_used": ram_used, "ram_total": ram_total, "storage_used": storage_used_mb, "storage_total": storage_total, "plan_type": plan_type 
            })))
        },
        Ok(None) => (StatusCode::NOT_FOUND, Json(serde_json::json!({"message": "Project not found!"}))),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"message": format!("DB Error: {}", e)})))
    }
}

// ============================================================================
// ⚙️ 2. ENVIRONMENT VARIABLES EDITORS (PostgreSQL JSONB Cluster Core Sync)
// ============================================================================
async fn get_env_vars(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>) -> Result<Json<serde_json::Value>, StatusCode> {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'get_env_vars' pulling from DB for Proj ID: '{}'", project_id);
    let _username = crate::get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    
    // براہِ راست پوسٹ گریس کے JSONB کالم سے ڈیٹا نکالنا
    let row = sqlx::query("SELECT env_vars FROM projects WHERE id = $1")
        .bind(p_id)
        .fetch_one(&state.pg_pool)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;
        
    let env_vars: serde_json::Value = row.try_get("env_vars").unwrap_or(serde_json::json!({}));
    Ok(Json(env_vars))
}

async fn save_env_vars(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Json(payload): Json<EnvData>) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'save_env_vars' updating DB Matrix for Proj ID: '{}'", project_id);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    // 1. پے لوڈ میپ کو پوسٹ گریس میں بطور JSONB سیو کرنا
    let json_vars = serde_json::to_value(&payload.0).unwrap_or(serde_json::json!({}));
    if let Err(e) = sqlx::query("UPDATE projects SET env_vars = $1 WHERE id = $2")
        .bind(&json_vars)
        .bind(p_id)
        .execute(&state.pg_pool)
        .await 
    {
        println!("❌ [CLUSTER ERROR] Failed to update env_vars in Postgres: {:?}", e);
        return StatusCode::INTERNAL_SERVER_ERROR;
    }

    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let env_path = format!("{}/.env", base_dir);

    // 2. لوکل فائل سسٹم کے لیے اسٹرنگ رینڈر کرنا (اگر لوکل پروجیکٹ ہے جیسے Rust, PHP)
    let mut content = String::new();
    for (k, v) in &payload.0 { content.push_str(&format!("{}={}\n", k.trim(), v.trim())); }
    
    if tokio::fs::create_dir_all(&base_dir).await.is_ok() {
        if tokio::fs::write(&env_path, content.clone()).await.is_ok() {
            let sys_user = format!("u_jail_p{}", p_id);
            let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
        }
    }

    // 3. اگر ریموٹ نوڈ کا پروجیکٹ ہے، تو ورکر کو لائیو نوٹیفائی کر دینا تاکہ وہ بھی رن ٹائم فائل سنک کر لے
    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files/write?project_id={}&user_id={}&base_dir={}&port={}", worker_url, p_id, user_id, base_dir, port);
        println!("🔍 [CLUSTER RAW LOG] Shipping updated ENVS matrix to remote worker node: {}", target_endpoint);
        
        let _ = client.post(&target_endpoint)
            .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
            .json(&serde_json::json!({ "filename": ".env", "content": content })).send().await;
    }
    
    StatusCode::OK
}


// ============================================================================
// 📁 3. LIST FILES ENGINE (Local Disk Read vs Microservice Worker Proxy)
// ============================================================================
async fn list_files(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Query(q): Query<ListFilesReq>) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'list_files' triggered for Proj ID: '{}' | Path Filter: '{:?}'", project_id, q.path);
    let _username = crate::get_username_from_cookie(&headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    
    let row = sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await.map_err(|_| StatusCode::NOT_FOUND)?;
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let sub_path = q.path.unwrap_or_default().trim_matches('/').to_string();

    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files?project_id={}&user_id={}&base_dir={}&port={}&path={}", worker_url, p_id, user_id, base_dir, port, sub_path);
        println!("🔍 [CLUSTER RAW LOG] Proxying directory architecture list request to worker: {}", target_endpoint);
        
        match client.get(&target_endpoint).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).send().await {
            Ok(res) => {
                let status_code = res.status();
                let raw_json = res.text().await.unwrap_or_else(|_| "[]".to_string());
                println!("🔍 [CLUSTER RAW LOG] Proxy File List Status: {} | Raw Payload Content Size: {} bytes", status_code, raw_json.len());
                if let Ok(worker_files) = serde_json::from_str::<Vec<serde_json::Value>>(&raw_json) {
                    return Ok(Json(worker_files));
                }
            },
            Err(e) => println!("❌ [CLUSTER RAW LOG] Failed network connection fetch inside proxy directory tree stream: {:?}", e)
        }
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    let target_dir = if sub_path.is_empty() { base_dir } else { format!("{}/{}", base_dir, sub_path) };
    let mut files_list = Vec::new();
    let mut entries = tokio::fs::read_dir(&target_dir).await.map_err(|_| StatusCode::NOT_FOUND)?;

    while let Ok(Some(entry)) = entries.next_entry().await {
        let name = entry.file_name().to_string_lossy().to_string();
        if name == "target" || name == ".venv" || name == "__pycache__" || name == "run.pid" || name == "app.log" || name == "silent_app_bin" { continue; }
        let metadata = entry.metadata().await.unwrap();
        let f_type = if metadata.is_dir() { "folder" } else { "file" };
        files_list.push(serde_json::json!({ "name": name, "type": f_type, "size": format!("{} KB", metadata.len() / 1024) }));
    }
    Ok(Json(files_list))
}

// ============================================================================
// 🗑️ 4. DELETE FILES ENGINE (Local Disk Sweep vs Worker Proxy)
// ============================================================================
async fn delete_files(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Json(payload): Json<DeleteFilesReq>) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'delete_files' triggered for Proj ID: '{}'", project_id);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);

    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        for file in payload.files {
            let target_endpoint = format!("{}/files/delete?project_id={}&user_id={}&base_dir={}&port={}", worker_url, p_id, user_id, base_dir, port);
            println!("🔍 [CLUSTER RAW LOG] Dispatching DELETE asset command payload packet to worker: {}", target_endpoint);
            let _ = client.post(&target_endpoint).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).json(&serde_json::json!({ "filename": file })).send().await;
        }
        return StatusCode::OK;
    }

    for file_to_delete in payload.files {
        let target = format!("{}/{}", base_dir, file_to_delete.trim_matches('/'));
        if let Ok(meta) = tokio::fs::metadata(&target).await {
            if meta.is_dir() { let _ = tokio::fs::remove_dir_all(&target).await; }
            else { let _ = tokio::fs::remove_file(&target).await; }
        }
    }
    StatusCode::OK
}

// ============================================================================
// 📥 5. UPLOAD FILES ENGINE (Direct Disk Write vs Worker Proxy)
// ============================================================================
async fn upload_files(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Query(q): Query<ListFilesReq>, mut multipart: Multipart) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'upload_files' multipart incoming hook triggered on Main Server for ID: '{}'", project_id);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let sub_path = q.path.unwrap_or_default().trim_matches('/').to_string();

    let worker_url = get_remote_worker_base_url(&language);
    let client = reqwest::Client::new();

    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        if let Some(filename) = field.file_name() {
            let fname = filename.to_string();
            let relative_target = if sub_path.is_empty() { fname.clone() } else { format!("{}/{}", sub_path, fname) };
            if let Ok(bytes) = field.bytes().await {
                if let Some(w_url) = worker_url {
                    let target_endpoint = format!("{}/files/write?project_id={}&user_id={}&base_dir={}&port={}", w_url, p_id, user_id, base_dir, port);
                    println!("🔍 [CLUSTER RAW LOG] Forwarding uploaded file buffer packet block [{}] via write proxy -> {}", relative_target, target_endpoint);
                    let _ = client.post(&target_endpoint)
                        .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
                        .json(&serde_json::json!({ "filename": relative_target, "content": String::from_utf8_lossy(&bytes).to_string() })).send().await;
                } else {
                    let file_path = format!("{}/{}", if sub_path.is_empty() { base_dir.clone() } else { format!("{}/{}", base_dir, sub_path) }, fname);
                    if tokio::fs::write(&file_path, bytes).await.is_ok() {
                        let sys_user = format!("u_jail_p{}", p_id);
                        let _ = std::process::Command::new("chown").args(&[&format!("{}:{}", sys_user, sys_user), &file_path]).status();
                    }
                }
            }
        }
    }
    StatusCode::OK
}

// ============================================================================
// 📝 6. WRITE FILE ENGINE (Save Code Editor Assets)
// ============================================================================
async fn write_file(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Json(payload): Json<FileContentReq>) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'write_file' asset modifier triggered for Proj ID: '{}' | File: '{}'", project_id, payload.filename);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let clean_path = payload.filename.trim_matches('/').to_string();

    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files/write?project_id={}&user_id={}&base_dir={}&port={}", worker_url, p_id, user_id, base_dir, port);
        println!("🔍 [CLUSTER RAW LOG] Dispatching updated editor content layout to remote worker: {}", target_endpoint);
        
        match client.post(&target_endpoint)
            .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
            .json(&serde_json::json!({ "filename": clean_path, "content": payload.content })).send().await 
        {
            Ok(res) => println!("🔍 [CLUSTER RAW LOG] Worker Editor Write Hook Response Status: {}", res.status()),
            Err(e) => println!("❌ [CLUSTER RAW LOG] Connection error transmitting updated editor matrix layer: {:?}", e)
        }
        return StatusCode::OK;
    }

    let file_path = format!("{}/{}", base_dir, clean_path);
    if tokio::fs::write(&file_path, payload.content.into_bytes()).await.is_ok() {
        let sys_user = format!("u_jail_p{}", p_id);
        let _ = std::process::Command::new("chown").args(&[&format!("{}:{}", sys_user, sys_user), &file_path]).status();
        StatusCode::OK
    } else {
        StatusCode::INTERNAL_SERVER_ERROR
    }
}

// ============================================================================
// 📦 7. EXTRACT ZIP FILE ENGINE (Unzip Core Trigger)
// ============================================================================
async fn extract_file(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Json(payload): Json<ExtractReq>) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'extract_file' zip unpack request triggered for Proj ID: '{}' | Zip Target: '{}'", project_id, payload.filename);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let clean_zip_path = payload.filename.trim_matches('/').to_string();

    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files/extract?project_id={}&user_id={}&base_dir={}&port={}", worker_url, p_id, user_id, base_dir, port);
        println!("🔍 [CLUSTER RAW LOG] Forwarding zip extraction command macro pipeline to worker: {}", target_endpoint);
        
        match client.post(&target_endpoint)
            .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
            .json(&serde_json::json!({ "filename": clean_zip_path })).send().await 
        {
            Ok(res) => {
                println!("🔍 [CLUSTER RAW LOG] Worker Unpack Payload Code Status: {}", res.status());
                return if res.status().is_success() { StatusCode::OK } else { StatusCode::BAD_REQUEST };
            },
            Err(e) => {
                println!("❌ [CLUSTER RAW LOG] Transmission error instructing worker unzip pipeline link: {:?}", e);
                return StatusCode::INTERNAL_SERVER_ERROR;
            }
        }
    }

    let file_path = format!("{}/{}", base_dir, clean_zip_path);
    let extract_cmd = format!("unzip -o '{}' -d '{}'", file_path, base_dir);
    let status = tokio::process::Command::new("sh").arg("-c").arg(&extract_cmd).status().await;

    if let Ok(s) = status {
        if s.success() {
            let sys_user = format!("u_jail_p{}", p_id);
            let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &base_dir]).status();
            return StatusCode::OK;
        }
    }
    StatusCode::BAD_REQUEST
}

// ============================================================================
// 📖 8. READ FILE ENGINE (Load Content Into Editor - Proxy-Aware)
// ============================================================================
async fn read_file(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Query(q): Query<ReadReq>) -> axum::response::Response {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'read_file' asset lookup reader triggered for ID: '{}' | Target File: '{}'", project_id, q.file);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return axum::response::Response::builder().status(401).body(axum::body::Body::empty()).unwrap() };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return axum::response::Response::builder().status(404).body(axum::body::Body::empty()).unwrap()
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let target_file = q.file.trim_matches('/').to_string();
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);

    // 🌟 فکس: اولڈ پروجیکٹس کی فائلیں نظر نہ آنے کی اصل وجہ یہ تھی کہ ریموٹ فائلز بھی لوکل والیم سے رید ہو رہی تھیں! اب پروکسی لاک کر دی ہے
    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files/download?project_id={}&user_id={}&base_dir={}&port={}&files={}", worker_url, p_id, user_id, base_dir, port, target_file);
        println!("🔍 [CLUSTER RAW LOG] Fetching proxied source file buffer from remote node: {}", target_endpoint);
        
        if let Ok(res) = client.get(&target_endpoint).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).send().await {
            if let Ok(bytes) = res.bytes().await {
                // مائیکروسروس کا ریٹرن آرکائیو انزپ کر کے پیور فائل ڈیٹا نکالنا یا ڈائریکٹ ٹیکسٹ فارمیٹ پاس کرنا
                let raw_content = String::from_utf8_lossy(&bytes).to_string();
                return axum::response::Response::builder().status(200).body(axum::body::Body::from(raw_content)).unwrap();
            }
        }
    }

    let file_path = format!("{}/{}", base_dir, target_file);
    if let Ok(content) = tokio::fs::read_to_string(&file_path).await {
        return axum::response::Response::builder().status(200).body(axum::body::Body::from(content)).unwrap();
    }
    axum::response::Response::builder().status(404).body(axum::body::Body::empty()).unwrap()
}

// ============================================================================
// 🏷️ 9. RENAME FILE ENGINE (File/Folder Identity Mutator)
// ============================================================================
async fn rename_file(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Json(payload): Json<RenameReq>) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'rename_file' metadata structure identity mutator for ID: '{}'", project_id);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let old_path = format!("{}/{}", base_dir, payload.old_name.trim_matches('/'));
    let new_path = format!("{}/{}", base_dir, payload.new_name.trim_matches('/'));

    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files/rename?project_id={}&user_id={}&base_dir={}&port={}", worker_url, p_id, user_id, base_dir, port);
        println!("🔍 [CLUSTER RAW LOG] Routing file system RENAME token sequence to worker node: {}", target_endpoint);
        
        match client.post(&target_endpoint)
            .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
            .json(&serde_json::json!({ "filename": payload.old_name, "new_name": payload.new_name })).send().await 
        {
            Ok(res) => println!("🔍 [CLUSTER RAW LOG] Worker Rename Hook Response Status: {}", res.status()),
            Err(e) => println!("❌ [CLUSTER RAW LOG] Error transmitting rename transaction routing logic payload: {:?}", e)
        }
        return StatusCode::OK;
    }

    if tokio::fs::rename(&old_path, &new_path).await.is_ok() { StatusCode::OK } else { StatusCode::INTERNAL_SERVER_ERROR }
}

// ============================================================================
// ➕ 10. CREATE FILE / FOLDER ENGINE
// ============================================================================
async fn create_file_folder(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Json(payload): Json<CreateReq>) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'create_file_folder' workspace allocator triggered for ID: '{}' | Element: '{}' | Type: '{}'", project_id, payload.name, payload.r#type);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let clean_path = payload.name.trim_matches('/').to_string();

    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files/create?project_id={}&user_id={}&base_dir={}&port={}", worker_url, p_id, user_id, base_dir, port);
        println!("🔍 [CLUSTER RAW LOG] Forwarding asset creation directory matrix to worker service node: {}", target_endpoint);
        
        match client.post(&target_endpoint)
            .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
            .json(&serde_json::json!({ "filename": clean_path, "type": payload.r#type })).send().await 
        {
            Ok(res) => println!("🔍 [CLUSTER RAW LOG] Worker File-Grid Creation Allocation State Response: {}", res.status()),
            Err(e) => println!("❌ [CLUSTER RAW LOG] Threat connection refused on remote workspace allocation nodes: {:?}", e)
        }
        return StatusCode::OK;
    }

    let target_path = format!("{}/{}", base_dir, clean_path);
    let sys_user = format!("u_jail_p{}", p_id);

    if payload.r#type == "folder" {
        let _ = tokio::fs::create_dir_all(&target_path).await;
    } else {
        let _ = tokio::fs::write(&target_path, "").await;
    }
    
    let _ = std::process::Command::new("chown").args(&["-R", &format!("{}:{}", sys_user, sys_user), &target_path]).status();
    StatusCode::OK
}

// ============================================================================
// 📥 11. DOWNLOAD FILES AS ZIP ARCHIVE
// ============================================================================
async fn download_files(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Query(query): Query<DownloadReq>) -> axum::response::Response {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'download_files' archive download pack builder running for ID: '{}'", project_id);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return axum::response::Response::builder().status(401).body(axum::body::Body::empty()).unwrap() };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return axum::response::Response::builder().status(404).body(axum::body::Body::empty()).unwrap()
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let target_files = query.files.clone();

    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        let target_endpoint = format!("{}/files/download?project_id={}&user_id={}&base_dir={}&port={}&files={}", worker_url, p_id, user_id, base_dir, port, target_files);
        println!("🔍 [CLUSTER RAW LOG] Proxying download package compression mapping link to worker: {}", target_endpoint);
        
        if let Ok(res) = client.get(&target_endpoint).header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE).send().await {
            if let Ok(bytes) = res.bytes().await {
                println!("🔍 [CLUSTER RAW LOG] Received raw byte stream package (Size: {} bytes) safely. Streaming download to user browser browser...", bytes.len());
                return axum::response::Response::builder()
                    .status(200).header("Content-Type", "application/zip")
                    .header("Content-Disposition", "attachment; filename=\"download.zip\"")
                    .body(axum::body::Body::from(bytes)).unwrap();
            }
        }
    }

    let targets: Vec<&str> = target_files.split(',').collect();
    let mut buffer = Vec::new();
    {
        let mut zip = zip::ZipWriter::new(std::io::Cursor::new(&mut buffer));
        let options = zip::write::FileOptions::<()>::default().compression_method(zip::CompressionMethod::Stored);

        for f in targets {
            let path = format!("{}/{}", base_dir, f.trim_matches('/'));
            if let Ok(b) = tokio::fs::read(&path).await {
                let _ = zip.start_file(f, options);
                let _ = std::io::Write::write_all(&mut zip, &b);
            }
        }
        let _ = zip.finish();
    }

    axum::response::Response::builder()
        .status(StatusCode::OK).header("Content-Type", "application/zip")
        .header("Content-Disposition", "attachment; filename=\"download.zip\"")
        .body(axum::body::Body::from(buffer)).unwrap()
}

// ============================================================================
// ✂️ 12. COPY / MOVE FILES ENGINE (Proxy-Aware Migration)
// ============================================================================
async fn copy_move_files(State(state): State<AppState>, headers: HeaderMap, Path(project_id): Path<String>, Json(payload): Json<CopyMoveReq>) -> StatusCode {
    println!("\n🔍 [CLUSTER RAW LOG] ---> 'copy_move_files' batch mapping sequence triggered for ID: '{}' | Action: '{}'", project_id, payload.action);
    let _username = match crate::get_username_from_cookie(&headers) { Some(u) => u, None => return StatusCode::UNAUTHORIZED };
    let p_id: i32 = project_id.parse().unwrap_or(0);
    
    let row = match sqlx::query("SELECT user_id, language, port FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r, Err(_) => return StatusCode::NOT_FOUND
    };
    let user_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let port: i32 = row.get::<i32, _>("port");
    let base_dir = format!("/app/data/user_{}/project_{}", user_id, p_id);
    let dest_dir = format!("{}/{}", base_dir, payload.dest_path.trim_matches('/'));

    // 🌟 فکس: اگر پروجیکٹ ریموٹ کا ہے، تو کاپی/موو کے آپریشنز کو بھی ریموٹ ورکر فلو پروکسی کے ساتھ سنک کرنا لازمی ہے
    if let Some(worker_url) = get_remote_worker_base_url(&language) {
        let client = reqwest::Client::new();
        for src_file in &payload.source_paths {
            let target_endpoint = format!("{}/files/rename?project_id={}&user_id={}&base_dir={}&port={}", worker_url, p_id, user_id, base_dir, port);
            let target_dest = format!("{}/{}", payload.dest_path.trim_matches('/'), src_file.split('/').last().unwrap_or(src_file));
            println!("🔍 [CLUSTER RAW LOG] Forwarding copy_move command via proxy mapping endpoint to worker node: {}", target_endpoint);
            let _ = client.post(&target_endpoint)
                .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE)
                .json(&serde_json::json!({ "filename": src_file, "new_name": target_dest })).send().await;
        }
        return StatusCode::OK;
    }

    let sys_user = format!("u_jail_p{}", p_id);
    for src_file in payload.source_paths {
        let clean_src = src_file.trim_matches('/');
        let src_path = format!("{}/{}", base_dir, clean_src);
        let final_dest = format!("{}/{}", dest_dir, clean_src.split('/').last().unwrap_or(clean_src));

        if payload.action == "copy" {
            let _ = tokio::fs::create_dir_all(std::path::Path::new(&final_dest).parent().unwrap()).await;
            if tokio::fs::copy(&src_path, &final_dest).await.is_ok() {
                let _ = std::process::Command::new("chown").args(&[&format!("{}:{}", sys_user, sys_user), &final_dest]).status();
            }
        } else if payload.action == "move" {
            let _ = tokio::fs::create_dir_all(std::path::Path::new(&final_dest).parent().unwrap()).await;
            let _ = tokio::fs::rename(&src_path, &final_dest).await;
        }
    }
    StatusCode::OK
}



async fn manage_domain(
    State(pool): State<sqlx::PgPool>, 
    Path(project_id): Path<String>, 
    Json(payload): Json<DomainReq>
) -> Result<Json<ApiResponse>, StatusCode> {
    let p_id: i32 = project_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    let owner_info: (String, String) = sqlx::query_as::<_, (String, String)>(
        "SELECT p.name, u.plan_type FROM projects p JOIN users u ON p.user_id = u.id WHERE p.id = $1"
    )
    .bind(p_id)
    .fetch_one(&pool)
    .await
    .map_err(|_| StatusCode::NOT_FOUND)?;

    let (proj_name, plan_type) = owner_info;

    match payload.action.as_str() {
        "generate" => {
            let clean_proj_name: String = proj_name
                .split_whitespace()
                .collect::<Vec<&str>>()
                .join("-")
                .to_lowercase();

            let new_domain = match payload.domain {
                Some(edited_domain) if !edited_domain.trim().is_empty() => {
                    edited_domain.split_whitespace().collect::<Vec<&str>>().join("-").to_lowercase()
                }
                _ => format!("{}-{}.silenthost.site", clean_proj_name, p_id)
            };

            let _ = sqlx::query("UPDATE projects SET domain = $1 WHERE id = $2")
                .bind(&new_domain).bind(p_id).execute(&pool).await;

            Ok(Json(ApiResponse { status: "success".into(), message: "Domain Updated Successfully!".into(), role: None }))
        },

        "custom" => {

            if plan_type != "pro" {
                return Ok(Json(ApiResponse { 
                    status: "error".into(), 
                    message: "Custom domains are exclusively available for Pro Plan users! Please upgrade your tier.".into(), 
                    role: None 
                }));
            }

            let custom_domain = payload.domain.unwrap_or_default();
            let clean_domain = custom_domain
                .split_whitespace()
                .collect::<Vec<&str>>()
                .join("-")
                .to_lowercase(); 

            let _ = sqlx::query("UPDATE projects SET custom_domain = $1 WHERE id = $2")
                .bind(&clean_domain).bind(p_id).execute(&pool).await;

            if let (Ok(token), Ok(proj_id)) = (std::env::var("VERCEL_TOKEN"), std::env::var("VERCEL_PROJECT_ID")) {
                let client = reqwest::Client::new();
                let vercel_url = format!("https://api.vercel.com/v9/projects/{}/domains", proj_id);

                let _ = client.post(&vercel_url)
                    .header("Authorization", format!("Bearer {}", token))
                    .json(&serde_json::json!({ "name": &clean_domain }))
                    .send()
                    .await;

            }

            Ok(Json(ApiResponse { status: "success".into(), message: "Custom domain saved! Point CNAME to router.silenthost.site".into(), role: None }))
        },

        "delete_generated" => {
            let _ = sqlx::query("UPDATE projects SET domain = NULL WHERE id = $1")
                .bind(p_id).execute(&pool).await;

            Ok(Json(ApiResponse { status: "success".into(), message: "Generated Domain removed!".into(), role: None }))
        },

        "delete_custom" => {

            let current_custom: Option<String> = sqlx::query_scalar("SELECT custom_domain FROM projects WHERE id = $1")
                .bind(p_id).fetch_one(&pool).await.unwrap_or(None);

            if let Some(domain_to_delete) = current_custom {
                if !domain_to_delete.is_empty() {

                    if let (Ok(token), Ok(vercel_proj_id)) = (std::env::var("VERCEL_TOKEN"), std::env::var("VERCEL_PROJECT_ID")) {
                        let client = reqwest::Client::new();
                        let vercel_url = format!("https://api.vercel.com/v9/projects/{}/domains/{}", vercel_proj_id, domain_to_delete);
                        let _ = client.delete(&vercel_url)
                            .header("Authorization", format!("Bearer {}", token))
                            .send()
                            .await;

                    }
                }
            }

            let _ = sqlx::query("UPDATE projects SET custom_domain = NULL WHERE id = $1")
                .bind(p_id).execute(&pool).await;

            Ok(Json(ApiResponse { status: "success".into(), message: "Custom Domain removed from network quota!".into(), role: None }))
        },

        "delete" => {
            let current_custom: Option<String> = sqlx::query_scalar("SELECT custom_domain FROM projects WHERE id = $1")
                .bind(p_id).fetch_one(&pool).await.unwrap_or(None);

            if let Some(domain_to_delete) = current_custom {
                if !domain_to_delete.is_empty() {
                    if let (Ok(token), Ok(vercel_proj_id)) = (std::env::var("VERCEL_TOKEN"), std::env::var("VERCEL_PROJECT_ID")) {
                        let client = reqwest::Client::new();
                        let vercel_url = format!("https://api.vercel.com/v9/projects/{}/domains/{}", vercel_proj_id, domain_to_delete);
                        let _ = client.delete(&vercel_url)
                            .header("Authorization", format!("Bearer {}", token))
                            .send()
                            .await;
                    }
                }
            }

            let _ = sqlx::query("UPDATE projects SET domain = NULL, custom_domain = NULL WHERE id = $1")
                .bind(p_id).execute(&pool).await;

            Ok(Json(ApiResponse { status: "success".into(), message: "All Domains completely wiped!".into(), role: None }))
        },
        _ => Err(StatusCode::BAD_REQUEST)
    }
}

async fn update_commands(State(pool): State<sqlx::PgPool>, Path(project_id): Path<String>, Json(payload): Json<UpdateCmdReq>) -> StatusCode {
    let p_id: i32 = project_id.parse().unwrap_or(0);

    let check_cmd = |cmd: &str| -> bool {
        let lower = cmd.to_lowercase();
        if lower.contains("..") || lower.contains("/app/data") || lower.contains("/etc") || lower.contains("/root") {
            return false;
        }
        true
    };

    if !check_cmd(&payload.build_cmd) || !check_cmd(&payload.start_cmd) {
        return StatusCode::FORBIDDEN;
    }

    let _ = sqlx::query("UPDATE projects SET build_cmd = $1, start_cmd = $2 WHERE id = $3")
        .bind(payload.build_cmd).bind(payload.start_cmd).bind(p_id).execute(&pool).await;
    StatusCode::OK
}

async fn admin_dashboard_stats(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<serde_json::Value>, StatusCode> {
    if !is_admin(&headers, &pool).await { 
        return Err(StatusCode::FORBIDDEN); 
    }

    let total_users_fut = sqlx::query_scalar("SELECT COUNT(*) FROM users").fetch_one(&pool);
    let free_users_fut = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE plan_type = 'free'").fetch_one(&pool);
    let basic_users_fut = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE plan_type = 'basic'").fetch_one(&pool);
    let pro_users_fut = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE plan_type = 'pro'").fetch_one(&pool);
    let total_proj_fut = sqlx::query_scalar("SELECT COUNT(*) FROM projects").fetch_one(&pool);
    let crashed_proj_fut = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE status = 'Crashed'").fetch_one(&pool);

    let (
        total_users_res, 
        free_users_res, 
        basic_users_res, 
        pro_users_res, 
        total_proj_res, 
        crashed_proj_res
    ) = tokio::join!(
        total_users_fut, 
        free_users_fut, 
        basic_users_fut, 
        pro_users_fut, 
        total_proj_fut, 
        crashed_proj_fut
    );

    let total_users: i64 = total_users_res.unwrap_or(0);
    let free_users: i64 = free_users_res.unwrap_or(0);
    let basic_users: i64 = basic_users_res.unwrap_or(0);
    let pro_users: i64 = pro_users_res.unwrap_or(0);
    let total_proj: i64 = total_proj_res.unwrap_or(0);
    let crashed_proj: i64 = crashed_proj_res.unwrap_or(0);

    let (ram_total, ram_used, cpu_usage, storage_total, storage_used) = tokio::task::spawn_blocking(move || {
        use sysinfo::{System, Disks};
        let mut sys = System::new_all();
        sys.refresh_all();

        std::thread::sleep(std::time::Duration::from_millis(150));
        sys.refresh_cpu_usage();

        let ram_t = sys.total_memory() as f64 / 1024.0 / 1024.0 / 1024.0;
        let ram_u = sys.used_memory() as f64 / 1024.0 / 1024.0 / 1024.0;
        let cpu = sys.global_cpu_usage() as f64; 

        let mut s_tot = 0.0;
        let mut s_used = 0.0;

        let disks = Disks::new_with_refreshed_list();
        for disk in &disks {
            if disk.mount_point() == std::path::Path::new("/") || disk.mount_point() == std::path::Path::new("/app") {
                s_tot = disk.total_space() as f64 / 1024.0 / 1024.0 / 1024.0;
                let available = disk.available_space() as f64 / 1024.0 / 1024.0 / 1024.0;
                s_used = s_tot - available;
                break;
            }
        }

        if s_tot == 0.0 {
            for disk in &disks {
                if disk.mount_point().starts_with("/") {
                    s_tot += disk.total_space() as f64 / 1024.0 / 1024.0 / 1024.0;
                    s_used += (disk.total_space() - disk.available_space()) as f64 / 1024.0 / 1024.0 / 1024.0;
                }
            }
        }

        (ram_t, ram_u, cpu, s_tot, s_used)
    }).await.unwrap_or((64.0, 12.0, 10.0, 1000.0, 150.0)); 

    Ok(Json(serde_json::json!({
        "sys_stats": { 
            "ram_total": format!("{:.2} GB", ram_total), 
            "ram_used": format!("{:.2} GB", ram_used), 
            "cpu_usage": format!("{:.2} %", cpu_usage), 
            "storage_total": format!("{:.2} GB", storage_total), 
            "storage_used": format!("{:.2} GB", storage_used) 
        }, 
        "user_stats": { "total": total_users, "free": free_users, "basic": basic_users, "pro": pro_users },
        "proj_stats": { "total": total_proj, "crashed": crashed_proj }
    })))
}

async fn admin_get_users(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }

    let query = "
        SELECT id, username, email, plan, is_suspended,
               (SELECT COUNT(*) FROM projects WHERE user_id = users.id) as project_count 
        FROM users 
        ORDER BY id DESC
    ";

    let rows = sqlx::query(query).fetch_all(&pool).await.map_err(|e| {

        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let mut users = Vec::new();

    for row in rows { 
        let p_count: i64 = row.get("project_count"); 

        users.push(serde_json::json!({ 
            "id": row.get::<i32, _>("id").to_string(), 
            "username": row.get::<String, _>("username"), 
            "email": row.get::<String, _>("email"), 
            "plan": row.get::<String, _>("plan"), 
            "is_suspended": row.get::<bool, _>("is_suspended"),
            "password": "********", 
            "project_count": p_count 
        })); 
    }
    Ok(Json(users))
}

async fn admin_get_user_details(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Path(user_id): Path<String>) -> Result<Json<serde_json::Value>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let u_id: i32 = user_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    let user_row = sqlx::query("SELECT username, email, plan, is_suspended, plan_expiry FROM users WHERE id = $1")
        .bind(u_id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| {

            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if user_row.is_none() { return Err(StatusCode::NOT_FOUND); }
    let u = user_row.unwrap();

    let proj_rows = sqlx::query("SELECT id, name, status, domain FROM projects WHERE user_id = $1").bind(u_id).fetch_all(&pool).await.unwrap();
    let mut projects = Vec::new();
    for p in proj_rows { projects.push(serde_json::json!({ "id": p.get::<i32, _>("id").to_string(), "name": p.get::<String, _>("name"), "status": p.get::<String, _>("status"), "domain": p.try_get::<String, _>("domain").ok() })); }

    let expiry: Option<chrono::DateTime<Utc>> = u.try_get("plan_expiry").ok();
    let expiry_str = expiry.map(|d| d.format("%Y-%m-%d %H:%M").to_string()).unwrap_or("Lifetime".to_string());

    Ok(Json(serde_json::json!({
        "user_info": { 
            "id": u_id.to_string(), 
            "username": u.get::<String, _>("username"), 
            "email": u.get::<String, _>("email"), 
            "plan": u.get::<String, _>("plan"), 
            "is_suspended": u.get::<bool, _>("is_suspended"), 
            "plan_expiry": expiry_str,
            "password": "********" 
        },
        "projects": projects
    })))
}

async fn admin_user_action(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Path(user_id): Path<String>, Json(payload): Json<ActionReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let u_id: i32 = user_id.parse().unwrap();
    match payload.action.as_str() {
        "suspend" => { let _ = sqlx::query("UPDATE users SET is_suspended = TRUE WHERE id = $1").bind(u_id).execute(&pool).await; },
        "unsuspend" => { let _ = sqlx::query("UPDATE users SET is_suspended = FALSE WHERE id = $1").bind(u_id).execute(&pool).await; },
        "cancel_plan" => { let _ = sqlx::query("UPDATE users SET plan = 'No Plan', plan_type = 'none', plan_expiry = NULL WHERE id = $1").bind(u_id).execute(&pool).await; },
        "reset_password" => {
            if let Some(new_pass) = payload.new_password {
                let hashed = hash(new_pass, DEFAULT_COST).unwrap();
                let _ = sqlx::query("UPDATE users SET password_hash = $1 WHERE id = $2").bind(hashed).bind(u_id).execute(&pool).await;
            } else {
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        "delete" => { 
            let _ = sqlx::query("DELETE FROM users WHERE id = $1").bind(u_id).execute(&pool).await; 
            let dir = format!("/app/data/user_{}", u_id);
            kill_room(&dir, 0).await;
            let _ = tokio::fs::remove_dir_all(&dir).await;
        },
        _ => return Err(StatusCode::BAD_REQUEST),
    }
    Ok(Json(ApiResponse { status: "success".to_string(), message: format!("Action '{}' executed", payload.action), role: None }))
}

// ============================================================================
// 🎯 1. ADMIN SINGLE PROJECT ACTION FORGER (Proxy & Microservice Aware)
// ============================================================================
async fn admin_project_action(State(state): State<AppState>, headers: HeaderMap, Path(proj_id): Path<String>, Json(payload): Json<ActionReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &state.pg_pool).await { return Err(StatusCode::FORBIDDEN); }
    
    // آنے والی اسٹرنگ آئی ڈی کی سیف پارسنگ
    let p_id: i32 = proj_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

    // 1. پروجیکٹ کے اصل مالک کا یوزر نیم نکالیں
    let owner_username: String = sqlx::query_scalar(
        "SELECT u.username FROM projects p INNER JOIN users u ON p.user_id = u.id WHERE p.id = $1"
    )
    .bind(p_id)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|_| StatusCode::NOT_FOUND)?;

    // 2. مالک کے نام کا نقلی 1 منٹ کا عارضی سیکیورٹی ٹوکن تیار کریں
    let exp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as usize + 60;
    let token = encode(
        &Header::default(),
        &Claims { sub: owner_username, role: "user".to_string(), exp },
        &EncodingKey::from_secret(SECRET_KEY)
    ).unwrap();

    // 3. کوکی ہیڈرز مینوفیکچر کریں
    let mut forged_headers = HeaderMap::new();
    forged_headers.insert(
        axum::http::header::COOKIE,
        axum::http::HeaderValue::from_str(&format!("silent_session={}", token)).unwrap()
    );

    // 4. 🌟 فکس: مینوئل کوئیریز کے بجائے اب یہ یوزر کنٹیکسٹ کے ساتھ ہماری کلسٹر سنکڈ اے پی آئی کو ہٹ مارے گا
    let _ = buildpacks::handle_project_action(
        State(state),
        forged_headers,
        axum::extract::Path(p_id.to_string()),
        Json(payload)
    ).await;

    Ok(Json(ApiResponse { 
        status: "success".to_string(), 
        message: "Administrative project process context updated successfully.".to_string(), 
        role: None 
    }))
}

// ============================================================================
// 📥 2. ADMIN PROJECT ZIP ARCHIVE DOWNLOAD (Local Storage vs Remote Worker Proxy)
// ============================================================================
async fn admin_download_project(State(state): State<AppState>, headers: HeaderMap, Path(proj_id): Path<String>) -> axum::response::Response {
    if !is_admin(&headers, &state.pg_pool).await { 
        return axum::response::Response::builder().status(StatusCode::FORBIDDEN).body(axum::body::Body::from("Forbidden")).unwrap(); 
    }

    let p_id: i32 = proj_id.parse().unwrap_or(0);
    
    // روٹنگ ڈیسیژن کے لیے لنگویج اور یوزر آئی ڈی کی سلیکشن ( ٹائپ سیف کاسٹنگ فکسڈ)
    let row = match sqlx::query("SELECT user_id, language FROM projects WHERE id = $1").bind(p_id).fetch_one(&state.pg_pool).await {
        Ok(r) => r,
        Err(_) => return axum::response::Response::builder().status(StatusCode::NOT_FOUND).body(axum::body::Body::from("Project metadata missing")).unwrap()
    };
    
    let u_id: i32 = row.get::<i32, _>("user_id");
    let language: String = row.get::<String, _>("language");
    let base_dir = format!("/app/data/user_{}/project_{}", u_id, p_id);

    // 🌟 پروکسی چیک: اگر پروجیکٹ ریموٹ ورکر (Node, Python, Go) پر ہے تو گلوبل لنکس مینی فیسٹ سے پاتھ منگوانا
    if let Some(worker_url) = get_worker_base_url(&language) {
        let client = reqwest::Client::new();
        
        // الف: پہلے ورکر سے پروجیکٹ فولڈر کی کلین لسٹ پُل کریں ( کلسٹر سیکریٹ ٹوکن فکسڈ)
        let list_endpoint = format!("{}/files?project_id={}&user_id={}&base_dir={}&port=0&path=", worker_url, p_id, u_id, base_dir);
        let mut files_csv = String::new();
        
        if let Ok(res) = client.get(&list_endpoint)
            .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE) // 👈 انٹرنل کلسٹر ہینڈ شیک ٹوکن
            .send().await 
        {
            if let Ok(files_json) = res.json::<Vec<serde_json::Value>>().await {
                let names: Vec<String> = files_json.iter()
                    .filter_map(|f| f.get("name"))
                    .filter_map(|n| n.as_str())
                    .map(|s| s.to_string())
                    .collect();
                files_csv = names.join(",");
            }
        }

        // ب: اب ان فائلوں کی زپ اسٹریم ورکر مائیکروسروس سے کھینچ کر فرنٹ اینڈ کو پاس کرنا
        let download_endpoint = format!("{}/files/download?project_id={}&user_id={}&base_dir={}&port=0&files={}", worker_url, p_id, u_id, base_dir, files_csv);
        if let Ok(res) = client.get(&download_endpoint)
            .header(INTERNAL_CLUSTER_SECRET_HEADER, INTERNAL_CLUSTER_SECRET_VALUE) // 👈 انٹرنل کلسٹر ہینڈ شیک ٹوکن
            .send().await 
        {
            if let Ok(bytes) = res.bytes().await {
                return axum::response::Response::builder()
                    .status(StatusCode::OK)
                    .header("Content-Type", "application/zip")
                    .header("Content-Disposition", format!("attachment; filename=\"project_{}.zip\"", p_id))
                    .body(axum::body::Body::from(bytes))
                    .unwrap();
            }
        }
        return axum::response::Response::builder().status(StatusCode::INTERNAL_SERVER_ERROR).body(axum::body::Body::from("Failed to compress remote cluster assets")).unwrap();
    }

    // لوکل پروجیکٹس رن ٹائم مینی فیسٹ (Rust, PHP, Static HTML)
    let zip_path = format!("/tmp/admin_dl_proj_{}.zip", p_id);

    let _ = tokio::process::Command::new("zip")
        .arg("-r")
        .arg(&zip_path)
        .arg(".")
        .arg("-x") 
        .arg("node_modules/*")     
        .arg("venv/*")             
        .arg(".venv/*")            
        .arg("__pycache__/*")      
        .arg("*.pyc")              
        .arg(".git/*")             
        .arg(".next/*")            
        .arg(".nuxt/*")            
        .arg("target/*")           
        .arg("app.log")            
        .arg("run.pid")            
        .current_dir(&base_dir)
        .status()
        .await;

    let bytes = tokio::fs::read(&zip_path).await.unwrap_or_default();
    let _ = tokio::fs::remove_file(&zip_path).await;

    axum::response::Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/zip")
        .header("Content-Disposition", format!("attachment; filename=\"project_{}.zip\"", p_id))
        .body(axum::body::Body::from(bytes))
        .unwrap()
}

fn extract_tid(msg: &str) -> String {
    if let Some(idx) = msg.find("TID:") {
        let start = idx + 4;
        let rest = &msg[start..].trim_start();

        rest.chars().take_while(|c| c.is_ascii_digit()).collect::<String>()
    } else {
        "".to_string()
    }
}

fn extract_amount(msg: &str) -> i32 {
    let lower = msg.to_lowercase();
    if let Some(idx) = lower.find("rs") {

        let after_rs = &lower[idx + 2..];

        let clean: String = after_rs.chars()
            .filter(|c| c.is_ascii_digit() || *c == '.' || *c == ',')
            .collect();

        let integer_part = clean.split('.').next().unwrap_or("0").replace(",", "");
        return integer_part.parse::<i32>().unwrap_or(0);
    }
    0
}

async fn submit_billing(State(pool): State<sqlx::PgPool>, headers: HeaderMap, mut multipart: Multipart) -> (StatusCode, Json<ApiResponse>) {
    let username = match get_username_from_cookie(&headers) { 
        Some(u) => u, 
        None => return (StatusCode::UNAUTHORIZED, Json(ApiResponse { status: "error".to_string(), message: "Unauthorized".to_string(), role: None })) 
    };

    let user_row = sqlx::query("SELECT id FROM users WHERE username = $1").bind(&username).fetch_one(&pool).await.unwrap();
    let user_id: i32 = user_row.get("id");

    let (mut plan, mut trx_id) = (String::new(), String::new());
    let mut screenshot_url = String::new(); 

    while let Some(field) = multipart.next_field().await.unwrap_or(None) {
        let name = field.name().unwrap_or("").to_lowercase();
        if name == "plan" { plan = field.text().await.unwrap_or_default().trim().to_string(); }
        else if name == "trxid" || name == "trx_id" { trx_id = field.text().await.unwrap_or_default().trim().to_string(); }
        else if name == "screenshot" || name == "file" || name == "image" { 
            if let Ok(data) = field.bytes().await {
                if !data.is_empty() {
                    let _ = tokio::fs::create_dir_all("/app/data/uploads").await;
                    let filename = format!("trx_{}_{}.png", user_id, &uuid::Uuid::new_v4().to_string()[..6]);
                    let _ = tokio::fs::write(format!("/app/data/uploads/{}", filename), &data).await;
                    screenshot_url = format!("/uploads/{}", filename);
                }
            }
        }
    }

    if screenshot_url.is_empty() { screenshot_url = "No Screenshot Provided".to_string(); }

    let _ = sqlx::query("DELETE FROM billing_requests WHERE trx_id = $1").bind(&trx_id).execute(&pool).await;

    let req_res = sqlx::query("INSERT INTO billing_requests (user_id, plan_requested, trx_id, screenshot_url) VALUES ($1, $2, $3, $4) RETURNING id")
        .bind(user_id).bind(&plan).bind(&trx_id).bind(&screenshot_url)
        .fetch_one(&pool).await;

    let req_id: i32 = match req_res {
        Ok(row) => row.get("id"),
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { status: "error".to_string(), message: "Database Error".to_string(), role: None }))
    };

    let _ = sqlx::query("UPDATE users SET pending_plan = $1 WHERE id = $2").bind(&plan).bind(user_id).execute(&pool).await;

    let sms_match = sqlx::query("SELECT amount FROM sms_transactions WHERE trx_id = $1 AND is_processed = FALSE")
        .bind(&trx_id).fetch_optional(&pool).await.unwrap_or(None);

    if let Some(sms) = sms_match {
        let paid_amt: i32 = sms.get("amount");

        process_payment_match(&pool, req_id, user_id, plan.clone(), paid_amt, &trx_id).await;

        let plan_norm = plan.to_lowercase();
        let required_amt = if plan_norm == "pro" { 1000 } else { 500 };

        if paid_amt == required_amt {
            return (StatusCode::OK, Json(ApiResponse { status: "success".to_string(), message: "Payment verified automatically! Plan activated.".to_string(), role: None }));
        } else {

            let reason = format!("Payment mismatch: Requested {} (Rs. {}) but sent Rs. {}.", plan.to_uppercase(), required_amt, paid_amt);
            return (StatusCode::OK, Json(ApiResponse { status: "success".to_string(), message: reason, role: None }));
        }
    }

    (StatusCode::OK, Json(ApiResponse { status: "success".to_string(), message: "Proof submitted! Verifying automatically...".to_string(), role: None }))
}

async fn process_payment_match(pool: &Pool<Postgres>, req_id: i32, user_id: i32, plan_req: String, paid_amt: i32, tid: &str) {
    let plan_norm = plan_req.to_lowercase();
    let required_amount = if plan_norm == "pro" { 1000 } else { 500 };

    let _ = sqlx::query("DELETE FROM billing_requests WHERE id = $1").bind(req_id).execute(pool).await;

    let _ = sqlx::query("UPDATE sms_transactions SET is_processed = TRUE WHERE trx_id = $1").bind(tid).execute(pool).await;

    if paid_amt == required_amount {

        let plan_name = if plan_norm == "pro" { "Pro Plan" } else { "Basic Plan" };
        let expiry = Utc::now() + Duration::days(30);

        let _ = sqlx::query("UPDATE users SET plan = $1, plan_type = $2, pending_plan = NULL, declined_plan = NULL, decline_reason = NULL, plan_expiry = $3 WHERE id = $4")
            .bind(plan_name).bind(&plan_norm).bind(expiry).bind(user_id).execute(pool).await;

    } else {

        let reason = format!(
            "Payment mismatch: You requested {} (Rs. {}) but sent only Rs. {}.", 
            plan_norm.to_uppercase(), required_amount, paid_amt
        );

        let _ = sqlx::query("UPDATE users SET pending_plan = NULL, declined_plan = $1, decline_reason = $2 WHERE id = $3")
            .bind(&plan_norm) 
            .bind(&reason)    
            .bind(user_id)
            .execute(pool)
            .await;

    }
}

async fn admin_get_billing_requests(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    if !is_admin(&headers, &pool).await { 

        return Err(StatusCode::FORBIDDEN); 
    }

    let _ = sqlx::query("CREATE TABLE IF NOT EXISTS billing_requests (id SERIAL PRIMARY KEY, user_id INT, plan_requested TEXT, trx_id TEXT, screenshot_url TEXT, date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP);").execute(&pool).await;

    let rows = sqlx::query("SELECT b.id, b.plan_requested, b.trx_id, b.screenshot_url, b.date, u.username, u.email FROM billing_requests b JOIN users u ON b.user_id = u.id ORDER BY b.id ASC")
        .fetch_all(&pool)
        .await
        .unwrap();

    let mut reqs = Vec::new();
    for r in rows {

        let date: chrono::DateTime<chrono::Utc> = r.try_get("date").unwrap_or_else(|_| chrono::Utc::now());
        let raw_screenshot: String = r.try_get("screenshot_url").unwrap_or_else(|_| "No Screenshot Provided".to_string());

        reqs.push(serde_json::json!({ 
            "id": r.get::<i32, _>("id").to_string(), 
            "username": r.get::<String, _>("username"), 
            "email": r.get::<String, _>("email"), 
            "plan_requested": r.get::<String, _>("plan_requested"), 
            "trx_id": r.get::<String, _>("trx_id"), 
            "screenshot_url": raw_screenshot.clone(), 
            "screenshot": raw_screenshot, 
            "date": date.format("%Y-%m-%d %H:%M").to_string() 
        }));
    }

    Ok(Json(reqs))
}

async fn admin_approve_billing(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<ApproveReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let r_id: i32 = payload.request_id.parse().unwrap();

    let req_row = sqlx::query("SELECT user_id, plan_requested FROM billing_requests WHERE id = $1").bind(r_id).fetch_optional(&pool).await.unwrap();
    if let Some(row) = req_row {
        let u_id: i32 = row.get("user_id");
        let plan_id: String = row.get("plan_requested");
        let plan_name = if plan_id == "pro" { "Pro Plan" } else { "Basic Plan" };
        let expiry = Utc::now() + Duration::days(30); 
        let _ = sqlx::query("UPDATE users SET plan = $1, plan_type = $2, pending_plan = NULL, plan_expiry = $3 WHERE id = $4").bind(plan_name).bind(&plan_id).bind(expiry).bind(u_id).execute(&pool).await;
        let _ = sqlx::query("DELETE FROM billing_requests WHERE id = $1").bind(r_id).execute(&pool).await;
        return Ok(Json(ApiResponse { status: "success".to_string(), message: "Billing Approved!".to_string(), role: None }));
    }
    Err(StatusCode::NOT_FOUND)
}

async fn admin_decline_billing(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<DeclineReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let r_id: i32 = payload.request_id.parse().unwrap();
    let req_row = sqlx::query("SELECT user_id, plan_requested FROM billing_requests WHERE id = $1").bind(r_id).fetch_optional(&pool).await.unwrap();
    if let Some(row) = req_row {
        let u_id: i32 = row.get("user_id");
        let _ = sqlx::query("UPDATE users SET declined_plan = pending_plan, pending_plan = NULL, decline_reason = $1 WHERE id = $2").bind(payload.reason).bind(u_id).execute(&pool).await;
        let _ = sqlx::query("DELETE FROM billing_requests WHERE id = $1").bind(r_id).execute(&pool).await;
        return Ok(Json(ApiResponse { status: "success".to_string(), message: "Billing Declined!".to_string(), role: None }));
    }
    Err(StatusCode::NOT_FOUND)
}

async fn admin_get_keys(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let rows = sqlx::query("SELECT id, key_code, plan_type, status, duration_days, max_uses, used_count, valid_until FROM access_keys ORDER BY id DESC").fetch_all(&pool).await.unwrap();
    let mut keys = Vec::new();
    for r in rows {
        let valid: Option<chrono::DateTime<Utc>> = r.try_get("valid_until").ok();
        keys.push(serde_json::json!({ "id": r.get::<i32, _>("id").to_string(), "key_code": r.get::<String, _>("key_code"), "plan_type": r.get::<String, _>("plan_type"), "status": r.get::<String, _>("status"), "duration_days": r.get::<i32, _>("duration_days"), "max_uses": r.get::<i32, _>("max_uses"), "used_count": r.get::<i32, _>("used_count"), "valid_until": valid.map(|d| d.format("%Y-%m-%d").to_string()) }));
    }
    Ok(Json(keys))
}

async fn admin_generate_key(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<GenerateKeyReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let key_code = format!("SILENT-{}-{}", payload.plan_type.to_uppercase(), uuid::Uuid::new_v4().to_string()[..8].to_uppercase());

    let safe_validity = if payload.redeem_validity_days > 36500 { 36500 } else { payload.redeem_validity_days as i64 };
    let valid_until = Utc::now() + Duration::days(safe_validity);

    let _ = sqlx::query("INSERT INTO access_keys (key_code, plan_type, duration_days, max_uses, valid_until) VALUES ($1, $2, $3, $4, $5)")
        .bind(&key_code).bind(&payload.plan_type).bind(payload.duration_days).bind(payload.max_uses).bind(valid_until).execute(&pool).await;

    Ok(Json(ApiResponse { status: "success".to_string(), message: "Key Generated!".to_string(), role: None }))
}

async fn admin_key_action(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Path(key_id): Path<String>, Json(payload): Json<ActionReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let k_id: i32 = key_id.parse().unwrap();
    if payload.action == "toggle_status" { let _ = sqlx::query("UPDATE access_keys SET status = $1 WHERE id = $2").bind(payload.status.unwrap()).bind(k_id).execute(&pool).await; } 
    else if payload.action == "delete" { let _ = sqlx::query("DELETE FROM access_keys WHERE id = $1").bind(k_id).execute(&pool).await; }
    Ok(Json(ApiResponse { status: "success".to_string(), message: "Action done".to_string(), role: None }))
}

async fn admin_get_settings(State(pool): State<sqlx::PgPool>, headers: HeaderMap) -> Result<Json<serde_json::Value>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let maint = sqlx::query_scalar::<_, String>("SELECT key_value FROM global_settings WHERE key_name = 'maintenance_mode'").fetch_one(&pool).await.unwrap_or("false".into()) == "true";
    let msg = sqlx::query_scalar::<_, String>("SELECT key_value FROM global_settings WHERE key_name = 'announcement_msg'").fetch_one(&pool).await.unwrap_or("".into());
    let exp = sqlx::query_scalar::<_, String>("SELECT key_value FROM global_settings WHERE key_name = 'announcement_expiry'").fetch_one(&pool).await.unwrap_or("".into());
    Ok(Json(serde_json::json!({ "maintenance_mode": maint, "announcement_msg": msg, "announcement_expiry": if exp.is_empty() { None } else { Some(exp) }, "username": "aflovevip" })))
}

async fn admin_toggle_maintenance(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<ToggleMaintReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { 

        return Err(StatusCode::FORBIDDEN); 
    }

    if let Err(e) = sqlx::query(
        "CREATE TABLE IF NOT EXISTS global_settings (key_name TEXT PRIMARY KEY, key_value TEXT);"
    ).execute(&pool).await {

        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    let val = if payload.enabled { "true" } else { "false" };

    let upsert_query = "
        INSERT INTO global_settings (key_name, key_value) 
        VALUES ('maintenance_mode', $1) 
        ON CONFLICT (key_name) 
        DO UPDATE SET key_value = EXCLUDED.key_value;
    ";

    match sqlx::query(upsert_query).bind(val).execute(&pool).await {
        Ok(_) => {

            Ok(Json(ApiResponse { status: "success".to_string(), message: "Maintenance Mode Updated Successfully".to_string(), role: None }))
        },
        Err(err) => {

            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn admin_set_announcement(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<BroadcastReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { 

        return Err(StatusCode::FORBIDDEN); 
    }

    if let Err(e) = sqlx::query(
        "CREATE TABLE IF NOT EXISTS global_settings (key_name TEXT PRIMARY KEY, key_value TEXT);"
    ).execute(&pool).await {

        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    let upsert_query = "
        INSERT INTO global_settings (key_name, key_value) 
        VALUES ($1, $2) 
        ON CONFLICT (key_name) 
        DO UPDATE SET key_value = EXCLUDED.key_value;
    ";

    if let Err(err) = sqlx::query(upsert_query).bind("announcement_msg").bind(&payload.message).execute(&pool).await {

        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    let expiry = payload.expiry_date.unwrap_or_else(|| "".to_string());
    if let Err(err) = sqlx::query(upsert_query).bind("announcement_expiry").bind(&expiry).execute(&pool).await {

        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    Ok(Json(ApiResponse { status: "success".to_string(), message: "Announcement Broadcast Updated Successfully".to_string(), role: None }))
}

async fn admin_update_creds(State(pool): State<sqlx::PgPool>, headers: HeaderMap, Json(payload): Json<CredsReq>) -> Result<Json<ApiResponse>, StatusCode> {
    if !is_admin(&headers, &pool).await { return Err(StatusCode::FORBIDDEN); }
    let username = get_username_from_cookie(&headers).unwrap();
    let row = sqlx::query("SELECT password_hash FROM users WHERE username = $1").bind(&username).fetch_one(&pool).await.unwrap();
    if let Some(new_pass) = payload.new_password {
        if !new_pass.is_empty() {
            let old = payload.old_password.unwrap_or_default();
            if verify(&old, row.get::<&str, _>("password_hash")).unwrap_or(false) {
                let hashed = hash(new_pass, DEFAULT_COST).unwrap();
                let _ = sqlx::query("UPDATE users SET password_hash = $1 WHERE username = $2").bind(hashed).bind(&username).execute(&pool).await;
            } else { return Err(StatusCode::BAD_REQUEST); }
        }
    }
    let _ = sqlx::query("UPDATE users SET username = $1 WHERE username = $2").bind(&payload.new_username).bind(&username).execute(&pool).await;
    Ok(Json(ApiResponse { status: "success".to_string(), message: "Credentials updated!".to_string(), role: None }))
}