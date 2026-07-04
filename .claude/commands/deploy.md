# Deploy to Production

Deploy the current project to production.

## Steps

1. Detect the deployment platform by checking for:
   - `vercel.json` or `.vercel/` -> Vercel (`npx vercel --prod`)
   - `netlify.toml` -> Netlify
   - `Dockerfile` -> Docker-based
   - `package.json` scripts for `deploy`
   - Fall back to asking the user

2. Pre-deploy checks:
   - Verify the build succeeds using the project's stack: `npm run build`
     (Node), `cargo build --release` (Rust), `go build ./...` (Go),
     `make build` if a Makefile defines it, or the project's documented command
   - Run the test suite if one exists
   - Check for uncommitted changes — warn if working tree is dirty
   - Show the current branch and last commit

3. Confirm with the user: "Ready to deploy [branch] to production via [platform]. Proceed?"

4. Run the deployment command.

5. If the project has a docs site (Docusaurus in `docs/`), ask if docs should be deployed too.

6. After deployment, update `_planning/STATUS.md` with the deployment timestamp.

---
