# Launch Dev Server

Start the development server in a separate terminal window and open the browser.

## Steps

1. Read `package.json` to detect the dev command and port:
   - Look for `scripts.dev` to determine the command
   - Check for port hints in the dev script (default to `3000`)
   - If no `package.json` exists, ask the user for the command and port

2. Launch the dev server in a new terminal window:
   - **Windows (PowerShell)**:
     ```
     Start-Process powershell -ArgumentList '-NoExit', '-Command', 'cd \"PROJECT_PATH\"; npm run dev'
     ```
   - **macOS/Linux**:
     Open a new terminal tab/window with the dev command.

   This opens a separate terminal that stays open independently.

3. Wait 3 seconds for the server to start, then open the browser:
   - **Windows**: `Start-Process "http://localhost:PORT"`
   - **macOS**: `open http://localhost:PORT`
   - **Linux**: `xdg-open http://localhost:PORT`

4. Confirm to the user: "Dev server running in a new terminal. Browser opened to http://localhost:PORT. This chat session remains available."

Keep the chat unblocked. Never run the dev server in the foreground of this session.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*