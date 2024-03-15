use tera::Tera;
use tokio::sync::RwLock;

use rust_embed::RustEmbed;

/// Static files and templates are embedded into the binary (in release mode) or hot-reloaded
/// from the `frontend/static` directory (in debug mode).
#[derive(RustEmbed)]
#[folder = "frontend/static/"]
#[include = "*.js"]
#[include = "*.br"]
#[include = "*.css"]
#[include = "*.svg"]
#[include = "*.png"]
struct StaticAssets;

/// Frontend source files compiled by `npm`.
#[derive(RustEmbed)]
#[folder = "frontend/dist"]
#[include = "*.js"]
#[include = "*.br"]
#[include = "*.css"]
struct StaticCompiledAssets;

/// HTML template files that will be rendered by `tera`.
#[derive(RustEmbed)]
#[folder = "frontend/templates/"]
#[include = "*.html"]
struct TemplateAssets;

pub struct ResourceResolver {
    tera: RwLock<Tera>,
}

impl ResourceResolver {
    pub fn new() -> anyhow::Result<Self> {
        let tera = load_templates()?;

        Ok(Self {
            tera: RwLock::new(tera),
        })
    }

    pub fn get_static_asset(&self, path: &str, allow_compression: bool) -> (Option<Vec<u8>>, bool) {
        if allow_compression {
            let compressed_path = path.to_owned() + ".br";
            let data = StaticCompiledAssets::get(compressed_path.as_str())
                .or_else(|| StaticAssets::get(compressed_path.as_str()))
                .map(|file| file.data.to_vec());
            if data.is_some() {
                return (data, true);
            }
        }

        (
            StaticCompiledAssets::get(path)
                .or_else(|| StaticAssets::get(path))
                .map(|file| file.data.to_vec()),
            false,
        )
    }

    pub async fn get_template(&self, path: &str) -> anyhow::Result<Vec<u8>> {
        // Live-reload the template if we're in debug mode
        #[cfg(debug_assertions)]
        {
            *self.tera.write().await = load_templates()?;
        }

        let context = tera::Context::new();
        let rendered = self.tera.read().await.render(path, &context)?;
        Ok(rendered.into_bytes())
    }
}

fn load_templates() -> anyhow::Result<Tera> {
    let templates = TemplateAssets::iter().map(|path| {
        (
            path.to_string(),
            String::from_utf8(TemplateAssets::get(&path).unwrap().data.to_vec()).unwrap(),
        )
    });
    let mut tera = Tera::default();
    tera.add_raw_templates(templates)?;
    Ok(tera)
}
