# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Web UI for [mediaMTX](https://mediamtx.org/) — a dependency-free media streaming server. The UI runs in Docker as a separate container alongside mediaMTX and allows runtime configuration of all server properties, paths (streams), and users without restarting mediaMTX.

Target mediaMTX version: **1.16.0**

## Development Commands

All development happens inside the Docker container:

```bash
# Start the stack (mediamtx server + UI)
docker compose -f docker-compose-mediamtx.yml up -d  # mediamtx server
docker compose up -d                                  # UI server

# Enter the container for development
docker exec -it mediamtxui sh

# Inside the container:
node index.js              # run the server directly
node build_frontend.js     # bundle frontend JS + CSS to server/build/
node build_server.js       # bundle server to server/build/server.js
node watch_css.js          # watch CSS with hot reloading (injects into running app)
node generate_auth.js      # generate argon2 password hash for config/auth.json
```

The UI is accessible at `http://localhost:3000` (or configured `SERVER_PORT`).

## Architecture

### Backend (`server/`)

Node.js + Express app using ES modules (`"type": "module"`).

Entry point: `server/index.js` → `Main` class instantiates:
- `Auth` — argon2-based authentication, reads `config/auth.json`
- `MediaMTX` — wraps mediaMTX API proxy + config management
- `Server` — Express app with session + CSRF protection

**Key server classes:**
- `server/lib/Server.js` — Express setup: static files, session cookie, auth middleware, routes at `/auth`, `/mediamtx`, `/api`
- `server/lib/MediaMTX.js` — orchestrates `MediamtxConfig` (YAML read/write) + `MediamtxApiProxy` (proxies to mediaMTX HTTP API at port 9997) + `MediamtxMetricsProxy` (proxies metrics at port 9998)
- `server/lib/Routes/` — API route handlers: Config, Overview, Server, Path, Sources, Playback, Recording, Monitoring

All routes require session authentication (401 if not logged in).

### Frontend (`server/public/js/`)

Vanilla JS (no framework), bundled with esbuild. No npm install needed for runtime.

Entry point: `server/public/js/index.js` → `Page` class

**Core frontend architecture:**
- `Page` (`page.js`) — top-level orchestrator: auth check → load settings → render tab navigation → show tabs
- `Settings` (`Settings.js`) — loads all mediaMTX config sections from API, delegates to `SettingsStore` (plain data object) and section-specific classes in `Settings/`
- `DataProxy` (`data_proxy.js`) — JS Proxy wrapper that intercepts get/set/delete on settings objects, emits events and triggers parent `action()` on change. Used to propagate form changes to the API automatically.
- `FetchManager` (`fetch_manager.js`) — wraps fetch with auth redirect on 401
- `EventEmitter` (`event_emitter.js`) — custom event system used throughout

**Settings tree** (mirrors mediaMTX config sections):
`settings.tree.{general, auth, api, pprof, metrics, playback, rtsp, rtmp, hls, webrtc, srt, path, paths, users}`

**Tabs** (`Tabs/`): Overview, Streams, Sources, Server, PathDefaults, Users

**Form components** (`Components/Form/`): All extend base `Component` class. Available types: `textinput`, `numberinput`, `checkboxinput`, `radioinput`, `selectinput`, `selecttextinput`, `multitextinput`, `multicheckboxinput`, `sliderinput`, `numbersliderinput`, `durationsliderinput`, `textareainput`, `availabletracksinput`, `permissions`.

Form `Component` base class (`Components/Form/Component.js`): takes `{parent, storeKey, store, prop, inputType, values, locked}` options. Reading `this.value` reads from `store[prop]`; setting `this.value` writes to `store[prop]` with 50ms debounce.

### Configuration

- `config/mediamtx.yml` — mediaMTX runtime config (copy from `config/mediamtx.default.yml`)
- `config/auth.json` — UI login credentials (argon2 hashes, copy from `config/auth.default.json`)
- `.env` — Docker environment variables (copy from `.env.default`)

Environment variables consumed by the server:
- `MEDIAMTX_API_URL_BASE` — default: `http://mediamtx:9997/v3`
- `MEDIAMTX_METRICS_URL_BASE` — default: `http://mediamtx:9998/metrics`
- `SERVER_PORT` — default: 3000
- `SESSION_SECRET` — session cookie secret

### Data flow for settings changes

1. User edits a form input → `Component.value` setter fires (debounced)
2. Sets `store[prop]` → `DataProxy` intercepts → calls `parent.action('update', prop, value)`
3. Settings class `onUpdate()` emits domain event (e.g., `update-global`, `update-path`)
4. Tab handler catches event → calls appropriate `/api/` route → backend proxies to mediaMTX API
