use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use term_core::api;
use uuid::Uuid;

#[derive(Parser)]
#[command(
    name = "term-core-cli",
    author,
    version,
    about = "JSON surface for Terminaut core"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Normalize {
        path: String,
    },
    List {
        path: String,
    },
    Favorites {
        #[command(subcommand)]
        action: FavoritesCommand,
    },
    Recents {
        #[command(subcommand)]
        action: RecentsCommand,
    },
    Projects {
        path: String,
    },
    Tags {
        #[command(subcommand)]
        action: TagCommand,
    },
    Profiles {
        #[command(subcommand)]
        action: ProfileCommand,
    },
    Search {
        query: String,
        #[arg(long, default_value = "~")]
        start: String,
        #[arg(short, long, default_value_t = 20)]
        limit: usize,
    },
    Version,
}

#[derive(Subcommand)]
enum FavoritesCommand {
    List,
    Add { path: String },
    Remove { path: String },
}

#[derive(Subcommand)]
enum RecentsCommand {
    List,
    Touch { path: String },
}

#[derive(Subcommand)]
enum TagCommand {
    List,
    For {
        path: String,
    },
    Add {
        path: String,
        tag: String,
        #[arg(long, default_value = "#0a84ff")]
        color: String,
    },
    Remove {
        path: String,
        tag: String,
    },
}

#[derive(Subcommand)]
enum ProfileCommand {
    List,
    Save {
        #[arg(long)]
        id: Option<String>,
        name: String,
        #[arg(long)]
        command: Option<String>,
        #[arg(long)]
        working_dir: Option<String>,
        #[arg(long)]
        terminal: Option<String>,
        #[arg(short, long)]
        windows: Option<u8>,
    },
    Delete {
        id: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Normalize { path } => emit_string(api::normalize_path(&path)?),
        Commands::List { path } => emit_json(&api::list_directory(&path)?),
        Commands::Favorites { action } => handle_favorites(action),
        Commands::Recents { action } => handle_recents(action),
        Commands::Projects { path } => emit_json(&api::detect_projects(&path)?),
        Commands::Tags { action } => handle_tags(action),
        Commands::Profiles { action } => handle_profiles(action),
        Commands::Search {
            query,
            start,
            limit,
        } => emit_json(&api::search(&start, &query, limit)?),
        Commands::Version => emit_string(env!("CARGO_PKG_VERSION")),
    }
}

fn handle_favorites(cmd: FavoritesCommand) -> Result<()> {
    match cmd {
        FavoritesCommand::List => emit_json(&api::list_favorites()),
        FavoritesCommand::Add { path } => {
            api::add_favorite(&path)?;
            emit_ok()
        }
        FavoritesCommand::Remove { path } => {
            api::remove_favorite(&path)?;
            emit_ok()
        }
    }
}

fn handle_recents(cmd: RecentsCommand) -> Result<()> {
    match cmd {
        RecentsCommand::List => emit_json(&api::list_recents()),
        RecentsCommand::Touch { path } => {
            api::touch_recent(&path)?;
            emit_ok()
        }
    }
}

fn handle_tags(cmd: TagCommand) -> Result<()> {
    match cmd {
        TagCommand::List => emit_json(&api::list_tags()),
        TagCommand::For { path } => emit_json(&api::tags_for(&path)?),
        TagCommand::Add { path, tag, color } => {
            api::set_tag(&path, &tag, Some(&color))?;
            emit_ok()
        }
        TagCommand::Remove { path, tag } => {
            api::remove_tag(&path, &tag)?;
            emit_ok()
        }
    }
}

fn handle_profiles(cmd: ProfileCommand) -> Result<()> {
    match cmd {
        ProfileCommand::List => emit_json(&api::list_profiles()),
        ProfileCommand::Save {
            id,
            name,
            command,
            working_dir,
            terminal,
            windows,
        } => {
            let parsed_id = id.as_deref().map(Uuid::parse_str).transpose()?;
            let profile =
                api::save_profile(parsed_id, &name, command, working_dir, terminal, windows)?;
            emit_json(&profile)
        }
        ProfileCommand::Delete { id } => {
            let uuid = Uuid::parse_str(&id).context("invalid uuid")?;
            api::delete_profile(uuid)?;
            emit_ok()
        }
    }
}

fn emit_ok() -> Result<()> {
    emit_json(&serde_json::json!({"status": "ok"}))
}

fn emit_string(value: impl AsRef<str>) -> Result<()> {
    println!("{}", value.as_ref());
    Ok(())
}

fn emit_json<T: serde::Serialize>(value: &T) -> Result<()> {
    let json = serde_json::to_string(value).context("serialize json output")?;
    println!("{}", json);
    Ok(())
}
