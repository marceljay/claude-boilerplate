# Launch Dev Server

Start the development server in a separate terminal window and open the browser.

## Steps

1. Detect the dev command and port from the project's stack:
   - **Node** (`package.json`): use `scripts.dev` (or `start`); read port hints,
     default `3000`
   - **Python**: `Makefile` `dev`/`run` target, `manage.py runserver` (Django,
     port `8000`), or `uvicorn`/`flask run` (`8000`/`5000`)
   - **Rust** (`Cargo.toml`): `cargo run`
   - **Go** (`go.mod`): `go run .`
   - **Any** (`Makefile`): prefer a `dev`/`run`/`serve` target
   - If you can't determine the command or port, ask the user.

2. Launch the dev server in a new terminal window so it stays up independently:
   - **Windows (PowerShell)**:
     ```
     Start-Process powershell -ArgumentList '-NoExit', '-Command', 'cd \"PROJECT_PATH\"; DEV_COMMAND'
     ```
   - **macOS/Linux**: open a new terminal tab/window running `DEV_COMMAND`.

3. Wait 3 seconds for the server to start, then open the browser:
   - **Windows**: `Start-Process "http://localhost:PORT"`
   - **macOS**: `open http://localhost:PORT`
   - **Linux**: `xdg-open http://localhost:PORT`

4. Confirm to the user: "Dev server running in a new terminal. Browser opened to http://localhost:PORT. This chat session remains available."

Keep the chat unblocked. Never run the dev server in the foreground of this session.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*