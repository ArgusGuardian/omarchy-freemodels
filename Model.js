// Pure helpers for the Free AI Models plugin. No state, no imports.

function formatContext(tokens) {
  var n = Number(tokens)
  if (!isFinite(n) || n <= 0) return "\u2014"
  if (n >= 1048576) {
    var m = n / 1048576
    return (m % 1 === 0 ? m : m.toFixed(1)) + "M"
  }
  if (n >= 1024) return Math.round(n / 1024) + "K"
  return String(n)
}

// Nerd Font glyph helpers (JetBrainsMono NF ships these; verified against the
// installed font's cmap). Monochrome so they follow the active theme colors,
// unlike emoji which always render multicolor.
var GLYPH = {
  robot: "\uEE0D",        // fa-robot
  refresh: "\uF021",      // fa-refresh
  externalLink: "\uF08E", // fa-external_link
  copy: "\uF24D",         // fa-clone
  history: "\uF1DA",      // fa-history
  memory: "\uEFC5",       // fa-memory
  gauge: "\uED2F",        // fa-gauge_high
  provider: "\uF02B"      // fa-tag
}

var MODALITY_GLYPHS = {
  text: "\uF031",         // fa-font
  image: "\uF00F",        // fa-images
  vision: "\uF00F",       // fa-images
  audio: "\uF025",        // fa-headphones
  video: "\uF008",        // fa-film
  files: "\uF016"         // fa-file_o
}

// Normalize a raw tracker entry into the shape the UI reads.
// Returns null for entries missing an id or name.
function normalize(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = typeof raw.id === "string" ? raw.id : ""
  var name = typeof raw.name === "string" ? raw.name : ""
  if (id === "" && name === "") return null
  var modalities = Array.isArray(raw.modalities) ? raw.modalities : []
  var glyphs = []
  for (var i = 0; i < modalities.length; i++) {
    var g = MODALITY_GLYPHS[String(modalities[i]).toLowerCase()]
    if (g && glyphs.indexOf(g) === -1) glyphs.push(g)
  }
  var url = typeof raw.source === "string" && raw.source !== ""
    ? raw.source
    : (id.indexOf("/") !== -1 ? "https://openrouter.ai/" + id : "")
  return {
    id: id,
    name: name,
    provider: typeof raw.provider === "string" ? raw.provider : "",
    context: formatContext(raw.context_window),
    maxOutput: formatContext(raw.max_output),
    rateLimit: typeof raw.rate_limit === "string" ? raw.rate_limit : "",
    glyphs: glyphs.join(" "),
    url: url
  }
}

// Parse a tracker payload; returns {ok, models, total, updatedAt} .
function parsePayload(text) {
  var obj = JSON.parse(text)
  var list = Array.isArray(obj.models) ? obj.models : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var m = normalize(list[i])
    if (m) out.push(m)
  }
  if (out.length === 0) throw new Error("no models in payload")
  return {
    ok: true,
    models: out,
    total: Number(obj.total_free_models) > 0 ? Number(obj.total_free_models) : out.length,
    updatedAt: typeof obj.updated_at === "string" ? obj.updated_at : ""
  }
}

// "12m ago" style string from a fetched-at epoch ms.
function timeAgo(fetchedAtMs, nowMs) {
  if (!(fetchedAtMs > 0)) return "never"
  var s = Math.max(0, Math.round((nowMs - fetchedAtMs) / 1000))
  if (s < 90) return "just now"
  var m = Math.round(s / 60)
  if (m < 90) return m + "m ago"
  var h = Math.round(m / 60)
  if (h < 36) return h + "h ago"
  return Math.round(h / 24) + "d ago"
}

// "04:41 UTC" from an ISO timestamp, or "" if unparseable.
function snapshotClock(iso) {
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var h = String(d.getUTCHours()).padStart(2, "0")
  var m = String(d.getUTCMinutes()).padStart(2, "0")
  return h + ":" + m + " UTC"
}

// Case-insensitive substring match across name/provider/id.
function matches(entry, query) {
  if (query === "") return true
  var q = query.toLowerCase()
  return entry.name.toLowerCase().indexOf(q) !== -1
    || entry.provider.toLowerCase().indexOf(q) !== -1
    || entry.id.toLowerCase().indexOf(q) !== -1
}
