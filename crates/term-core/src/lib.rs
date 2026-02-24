use std::ffi::{c_char, CStr, CString};
use std::path::{Path, PathBuf};

use anyhow::Context;
use chrono::Utc;
use dirs::data_dir;
use fuzzy_matcher::skim::SkimMatcherV2;
use fuzzy_matcher::FuzzyMatcher;
use ignore::WalkBuilder;
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

static STORE: Lazy<Store> = Lazy::new(|| Store::initialize().unwrap_or_default());

#[derive(Debug, Serialize, Deserialize)]
struct PersistedState {
    #[serde(default)]
    favorites: Vec<String>,
    #[serde(default)]
    recents: Vec<RecentEntry>,
    #[serde(default)]
    tags: Vec<TaggedPath>,
    #[serde(default)]
    profiles: Vec<LaunchProfile>,
}

impl Default for PersistedState {
    fn default() -> Self {
        Self {
            favorites: Vec::new(),
            recents: Vec::new(),
            tags: Vec::new(),
            profiles: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentEntry {
    pub path: String,
    pub last_opened_utc: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaggedPath {
    pub path: String,
    pub tag: String,
    pub color: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LaunchProfile {
    pub id: Uuid,
    pub name: String,
    pub command: Option<String>,
    pub working_dir: Option<String>,
    pub terminal: Option<String>,
    pub windows: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub path: String,
    pub name: String,
    pub score: i64,
}

impl Default for RecentEntry {
    fn default() -> Self {
        Self {
            path: String::new(),
            last_opened_utc: Utc::now().timestamp(),
        }
    }
}

impl Default for LaunchProfile {
    fn default() -> Self {
        Self {
            id: Uuid::new_v4(),
            name: String::from("Quick Launch"),
            command: None,
            working_dir: None,
            terminal: None,
            windows: 1,
        }
    }
}

struct Store {
    path: PathBuf,
    inner: Mutex<PersistedState>,
}

impl Default for Store {
    fn default() -> Self {
        let path = Store::default_store_path();
        Self {
            path,
            inner: Mutex::new(PersistedState::default()),
        }
    }
}

impl Store {
    fn initialize() -> anyhow::Result<Self> {
        let path = Store::default_store_path();
        if path.is_file() {
            let contents = std::fs::read_to_string(&path)
                .with_context(|| format!("failed to read state file at {}", path.display()))?;
            let state: PersistedState = serde_json::from_str(&contents)
                .with_context(|| format!("failed to parse state file at {}", path.display()))?;
            Ok(Self {
                path,
                inner: Mutex::new(state),
            })
        } else {
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            Ok(Self {
                path,
                inner: Mutex::new(PersistedState::default()),
            })
        }
    }

    fn default_store_path() -> PathBuf {
        let mut dir = data_dir().unwrap_or_else(|| PathBuf::from("."));
        dir.push("Terminaut");
        dir.push("state.json");
        dir
    }

    fn persist(&self) -> anyhow::Result<()> {
        let inner = self.inner.lock();
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(&*inner)?;
        std::fs::write(&self.path, json)?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectoryEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    /// Modification time as Unix timestamp (seconds since epoch), if available.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mod_date: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectRoot {
    pub path: String,
    pub marker: String,
}

fn normalize_path(input: &str) -> anyhow::Result<PathBuf> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        anyhow::bail!("empty path");
    }
    let expanded = if trimmed.starts_with('~') {
        if let Some(home) = dirs::home_dir() {
            home.join(trimmed.trim_start_matches('~'))
        } else {
            PathBuf::from(trimmed)
        }
    } else {
        PathBuf::from(trimmed)
    };

    let canonical = std::fs::canonicalize(&expanded).unwrap_or(expanded);
    Ok(canonical)
}

fn list_directory(path: &Path) -> anyhow::Result<Vec<DirectoryEntry>> {
    use std::time::UNIX_EPOCH;
    let mut entries: Vec<_> = std::fs::read_dir(path)?
        .filter_map(|res| res.ok())
        .filter_map(|entry| {
            let file_type = entry.file_type().ok()?;
            let name = entry.file_name().to_string_lossy().to_string();
            let mod_date = entry
                .metadata()
                .ok()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_secs() as i64);
            Some(DirectoryEntry {
                name,
                path: entry.path().display().to_string(),
                is_dir: file_type.is_dir(),
                mod_date,
            })
        })
        .collect();
    entries.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    Ok(entries)
}

fn detect_projects(path: &Path) -> Vec<ProjectRoot> {
    const MARKERS: [&str; 5] = [
        ".git",
        "package.json",
        "Cargo.toml",
        "go.mod",
        "bunfig.toml",
    ];
    let mut results = Vec::new();
    for ancestor in path.ancestors() {
        for marker in &MARKERS {
            if ancestor.join(marker).exists() {
                results.push(ProjectRoot {
                    path: ancestor.display().to_string(),
                    marker: marker.to_string(),
                });
                break;
            }
        }
    }
    results
}

fn list_recent_directories() -> Vec<RecentEntry> {
    let mut state = STORE.inner.lock().recents.clone();
    state.sort_by(|a, b| b.last_opened_utc.cmp(&a.last_opened_utc));
    state
}

fn list_favorites() -> Vec<String> {
    let mut favs = STORE.inner.lock().favorites.clone();
    favs.sort();
    favs
}

fn add_favorite(path: &str) -> anyhow::Result<()> {
    let normalized = normalize_path(path)?;
    let mut store = STORE.inner.lock();
    if !store
        .favorites
        .iter()
        .any(|p| p == normalized.to_string_lossy().as_ref())
    {
        store.favorites.push(normalized.display().to_string());
        STORE.persist().ok();
    }
    Ok(())
}

fn remove_favorite(path: &str) -> anyhow::Result<()> {
    let normalized = normalize_path(path)?;
    let normalized = normalized.display().to_string();
    let mut store = STORE.inner.lock();
    store.favorites.retain(|p| p != &normalized);
    STORE.persist().ok();
    Ok(())
}

fn touch_recent(path: &str) -> anyhow::Result<()> {
    let normalized = normalize_path(path)?;
    let normalized = normalized.display().to_string();
    let mut store = STORE.inner.lock();
    store.recents.retain(|entry| entry.path != normalized);
    store.recents.push(RecentEntry {
        path: normalized,
        last_opened_utc: Utc::now().timestamp(),
    });
    if store.recents.len() > 100 {
        store
            .recents
            .sort_by(|a, b| b.last_opened_utc.cmp(&a.last_opened_utc));
        store.recents.truncate(100);
    }
    STORE.persist().ok();
    Ok(())
}

fn list_tags() -> Vec<TaggedPath> {
    STORE.inner.lock().tags.clone()
}

fn set_tag(path: &str, tag: &str, color: Option<&str>) -> anyhow::Result<()> {
    let normalized = normalize_path(path)?;
    let normalized = normalized.display().to_string();
    let mut store = STORE.inner.lock();
    let color = color.unwrap_or("#0a84ff").to_string();
    if let Some(existing) = store
        .tags
        .iter_mut()
        .find(|entry| entry.path == normalized && entry.tag.eq_ignore_ascii_case(tag))
    {
        existing.color = color;
    } else {
        store.tags.push(TaggedPath {
            path: normalized,
            tag: tag.to_string(),
            color,
        });
    }
    STORE.persist().ok();
    Ok(())
}

fn remove_tag(path: &str, tag: &str) -> anyhow::Result<()> {
    let normalized = normalize_path(path)?;
    let normalized = normalized.display().to_string();
    let mut store = STORE.inner.lock();
    store
        .tags
        .retain(|entry| !(entry.path == normalized && entry.tag.eq_ignore_ascii_case(tag)));
    STORE.persist().ok();
    Ok(())
}

fn tags_for_path(path: &str) -> anyhow::Result<Vec<TaggedPath>> {
    let normalized = normalize_path(path)?;
    let normalized = normalized.display().to_string();
    Ok(STORE
        .inner
        .lock()
        .tags
        .iter()
        .filter(|entry| entry.path == normalized)
        .cloned()
        .collect())
}

fn list_profiles() -> Vec<LaunchProfile> {
    let mut profiles = STORE.inner.lock().profiles.clone();
    profiles.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    profiles
}

fn save_profile(
    id: Option<Uuid>,
    name: &str,
    command: Option<String>,
    working_dir: Option<String>,
    terminal: Option<String>,
    windows: Option<u8>,
) -> anyhow::Result<LaunchProfile> {
    if name.trim().is_empty() {
        anyhow::bail!("profile name required");
    }
    let mut store = STORE.inner.lock();
    let profile_id = id.unwrap_or_else(Uuid::new_v4);
    let profile = LaunchProfile {
        id: profile_id,
        name: name.trim().to_string(),
        command,
        working_dir,
        terminal,
        windows: windows.unwrap_or(1).clamp(1, 10),
    };

    if let Some(existing) = store.profiles.iter_mut().find(|p| p.id == profile_id) {
        *existing = profile.clone();
    } else {
        store.profiles.push(profile.clone());
    }
    STORE.persist().ok();
    Ok(profile)
}

fn delete_profile(id: Uuid) -> anyhow::Result<()> {
    let mut store = STORE.inner.lock();
    let before = store.profiles.len();
    store.profiles.retain(|profile| profile.id != id);
    if before == store.profiles.len() {
        anyhow::bail!("profile not found");
    }
    STORE.persist().ok();
    Ok(())
}

fn search_directories(path: &str, query: &str, limit: usize) -> anyhow::Result<Vec<SearchResult>> {
    if query.trim().is_empty() {
        anyhow::bail!("query required");
    }
    let normalized = normalize_path(path)?;
    let matcher = SkimMatcherV2::default();
    let walker = WalkBuilder::new(&normalized)
        .max_depth(Some(5))
        .standard_filters(true)
        .build();

    let mut results = Vec::new();
    for entry in walker.flatten() {
        if results.len() >= limit.saturating_mul(2) {
            break;
        }
        let md = match entry.metadata() {
            Ok(md) => md,
            Err(_) => continue,
        };
        if !md.is_dir() {
            continue;
        }
        let name = match entry.file_name().to_str() {
            Some(name) => name,
            None => continue,
        };
        if let Some(score) = matcher.fuzzy_match(name, query) {
            results.push(SearchResult {
                path: entry.path().display().to_string(),
                name: name.to_string(),
                score,
            });
        }
    }

    results.sort_by(|a, b| b.score.cmp(&a.score).then(a.name.cmp(&b.name)));
    results.truncate(limit.max(1));
    Ok(results)
}

pub mod api {
    use super::*;

    pub fn normalize_path(path: &str) -> anyhow::Result<String> {
        let normalized = super::normalize_path(path)?;
        Ok(normalized.display().to_string())
    }

    pub fn list_directory(path: &str) -> anyhow::Result<Vec<DirectoryEntry>> {
        let normalized = super::normalize_path(path)?;
        super::list_directory(&normalized)
    }

    pub fn list_favorites() -> Vec<String> {
        super::list_favorites()
    }

    pub fn add_favorite(path: &str) -> anyhow::Result<()> {
        super::add_favorite(path)
    }

    pub fn remove_favorite(path: &str) -> anyhow::Result<()> {
        super::remove_favorite(path)
    }

    pub fn list_recents() -> Vec<RecentEntry> {
        super::list_recent_directories()
    }

    pub fn touch_recent(path: &str) -> anyhow::Result<()> {
        super::touch_recent(path)
    }

    pub fn detect_projects(path: &str) -> anyhow::Result<Vec<ProjectRoot>> {
        let normalized = super::normalize_path(path)?;
        Ok(super::detect_projects(&normalized))
    }

    pub fn list_tags() -> Vec<TaggedPath> {
        super::list_tags()
    }

    pub fn set_tag(path: &str, tag: &str, color: Option<&str>) -> anyhow::Result<()> {
        super::set_tag(path, tag, color)
    }

    pub fn remove_tag(path: &str, tag: &str) -> anyhow::Result<()> {
        super::remove_tag(path, tag)
    }

    pub fn tags_for(path: &str) -> anyhow::Result<Vec<TaggedPath>> {
        super::tags_for_path(path)
    }

    pub fn list_profiles() -> Vec<LaunchProfile> {
        super::list_profiles()
    }

    pub fn save_profile(
        id: Option<Uuid>,
        name: &str,
        command: Option<String>,
        working_dir: Option<String>,
        terminal: Option<String>,
        windows: Option<u8>,
    ) -> anyhow::Result<LaunchProfile> {
        super::save_profile(id, name, command, working_dir, terminal, windows)
    }

    pub fn delete_profile(id: Uuid) -> anyhow::Result<()> {
        super::delete_profile(id)
    }

    pub fn search(path: &str, query: &str, limit: usize) -> anyhow::Result<Vec<SearchResult>> {
        super::search_directories(path, query, limit)
    }
}

fn c_string_or_null(result: anyhow::Result<String>) -> *mut c_char {
    match result {
        Ok(value) => CString::new(value)
            .map(|s| s.into_raw())
            .unwrap_or(std::ptr::null_mut()),
        Err(err) => {
            eprintln!("term-core error: {err:#}");
            std::ptr::null_mut()
        }
    }
}

fn c_string_from_json<T: Serialize>(value: &T) -> *mut c_char {
    match serde_json::to_string(value) {
        Ok(json) => CString::new(json)
            .map(|s| s.into_raw())
            .unwrap_or(std::ptr::null_mut()),
        Err(err) => {
            eprintln!("term-core json error: {err:#}");
            std::ptr::null_mut()
        }
    }
}

fn c_str_to_string(input: *const c_char) -> anyhow::Result<String> {
    if input.is_null() {
        anyhow::bail!("null pointer");
    }
    let c_str = unsafe { CStr::from_ptr(input) };
    Ok(c_str.to_string_lossy().to_string())
}

#[no_mangle]
pub extern "C" fn term_core_version() -> *mut c_char {
    CString::new(env!("CARGO_PKG_VERSION")).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn term_core_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

#[no_mangle]
pub extern "C" fn term_core_normalize_path(path: *const c_char) -> *mut c_char {
    c_string_or_null(c_str_to_string(path).and_then(|p| {
        let normalized = normalize_path(&p)?;
        Ok(normalized.display().to_string())
    }))
}

#[no_mangle]
pub extern "C" fn term_core_list_directory(path: *const c_char) -> *mut c_char {
    c_string_or_null(c_str_to_string(path).and_then(|p| {
        let normalized = normalize_path(&p)?;
        let entries = list_directory(&normalized)?;
        serde_json::to_string(&entries).context("serialize directory entries")
    }))
}

#[no_mangle]
pub extern "C" fn term_core_list_favorites() -> *mut c_char {
    c_string_from_json(&list_favorites())
}

#[no_mangle]
pub extern "C" fn term_core_add_favorite(path: *const c_char) -> u8 {
    c_str_to_string(path)
        .and_then(|p| add_favorite(&p))
        .map(|_| 1u8)
        .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn term_core_remove_favorite(path: *const c_char) -> u8 {
    c_str_to_string(path)
        .and_then(|p| remove_favorite(&p))
        .map(|_| 1u8)
        .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn term_core_list_recents() -> *mut c_char {
    c_string_from_json(&list_recent_directories())
}

#[no_mangle]
pub extern "C" fn term_core_touch_recent(path: *const c_char) -> u8 {
    c_str_to_string(path)
        .and_then(|p| touch_recent(&p))
        .map(|_| 1u8)
        .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn term_core_detect_projects(path: *const c_char) -> *mut c_char {
    c_string_or_null(c_str_to_string(path).and_then(|p| {
        let normalized = normalize_path(&p)?;
        let projects = detect_projects(&normalized);
        serde_json::to_string(&projects).context("serialize project roots")
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recent_entries_sort() {
        let mut entries = vec![
            RecentEntry {
                path: "b".into(),
                last_opened_utc: 1,
            },
            RecentEntry {
                path: "a".into(),
                last_opened_utc: 5,
            },
        ];
        entries.sort_by(|a, b| b.last_opened_utc.cmp(&a.last_opened_utc));
        assert_eq!(entries[0].path, "a");
    }
}
