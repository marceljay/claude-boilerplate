- **`/dev` no longer announces a host port it cannot know.** Inside the dev
  container the editor may forward container port 3000 to another host port,
  and nothing in the container can read which. `/dev`, CLAUDE.md, and README
  §7 now say so and hand URLs to `"$BROWSER"` (VS Code's `code --openExternal`
  helper), which resolves the forward and opens the real host URL. The status
  line suffixes the dev-server port with `(container)` there.
