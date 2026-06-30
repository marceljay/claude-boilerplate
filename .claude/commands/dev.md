# Launch Dev Server

Start the development server without blocking this chat, and surface its URL.

## Steps

0. **Detect the environment first.** If `/.dockerenv` exists or
   `$REMOTE_CONTAINERS`/`$DEVCONTAINER` is set, you're in the dev container —
   follow the container path in steps 2–3 (this is the usual case). Otherwise
   use the host path.

1. Detect the dev command and port from the project's stack:
   - **Node** (`package.json`): use `scripts.dev` (or `start`); read port hints,
     default `3000`
   - **Python**: `Makefile` `dev`/`run` target, `manage.py runserver` (Django,
     port `8000`), or `uvicorn`/`flask run` (`8000`/`5000`)
   - **Rust** (`Cargo.toml`): `cargo run`
   - **Go** (`go.mod`): `go run .`
   - **Any** (`Makefile`): prefer a `dev`/`run`/`serve` target
   - If you can't determine the command or port, ask the user.

2. **Launch it without blocking this chat.**
   - **In the container:** run the server as a background task (e.g. the Bash
     tool's `run_in_background`), and make it **bind `0.0.0.0`, not
     `127.0.0.1`** — a server bound to localhost inside the container isn't
     reachable from the host and the editor can't forward it. Most frameworks
     take a host flag: `next dev -H 0.0.0.0`, `vite --host`,
     `uvicorn --host 0.0.0.0`, `manage.py runserver 0.0.0.0:8000`,
     `flask run --host 0.0.0.0`. Don't pin a host port or assume one is free —
     the editor auto-forwards the container port to whatever host port is open
     (which may differ), so parallel containers don't collide.
   - **On the host:** open a new terminal window/tab running the dev command so
     it stays up independently (PowerShell: `Start-Process powershell
-ArgumentList '-NoExit','-Command','cd \"PROJECT_PATH\"; DEV_COMMAND'`).

3. Wait ~3 seconds, then surface the URL — **do not open a browser yourself**:
   - **In the container:** there is no host browser, and the host port may not
     match the container port. Tell the user the container port (e.g. `3000`)
     and that the editor auto-forwards it — they open it from VS Code's **Ports**
     panel (or the toast). Don't run `open`/`xdg-open`.
   - **On the host:** you may open it — `open` (macOS) / `xdg-open` (Linux) /
     `Start-Process` (Windows) on `http://localhost:PORT`.

4. Confirm to the user: server is running in the background / a new terminal,
   how to reach it (forwarded port or `http://localhost:PORT`), and that this
   chat stays available.

Keep the chat unblocked. Never run the dev server in the foreground of this session.

---
