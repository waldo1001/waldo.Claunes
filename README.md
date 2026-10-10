# waldo.Claunes

Run several Claude Desktop accounts side by side on one Mac. Each profile is a
**Claune** (Claude + clone): its own login, chat history, settings and MCP servers, its
own app in `~/Applications/Claunes/` with its own name and colored icon in Spotlight,
Launchpad, the Dock and Cmd-Tab.

> waldo.Claunes is an independent open-source utility. It is not affiliated with,
> endorsed by, or produced by Anthropic. Claude is a trademark of Anthropic PBC. It is
> meant for people with multiple legitimate accounts (for example work and personal),
> not for getting around usage limits.

Free, MIT licensed, local only: no account, no telemetry, no network calls of its own.
Inspired by the functionality of [Multi-Claude](https://multiclaude.app).

## Requirements

- macOS 13 or later, Apple Silicon or Intel (developed on macOS 26).
- Claude Desktop installed in `/Applications/Claude.app`. waldo.Claunes runs Anthropic's
  app; it does not bundle, re-host or modify it. If it is missing, the app says so and
  links to the download page.
- Xcode command line tools (Swift 5.9+) to build from source.

## Install / build

```sh
git clone https://github.com/waldo1001/waldo.Claunes.git
cd waldo.Claunes
scripts/install.sh            # builds release and copies build/waldo.Claunes.app to /Applications
```

Or build only: `scripts/build-app.sh release` produces `build/waldo.Claunes.app`.
Tests: `swift test`. Command line interface (same core, handy for scripting):
`build/waldo.Claunes.app/Contents/MacOS/claunes list|create|launch|resync|rename|delete|migrate|doctor`.

A local build is ad-hoc signed; macOS may ask you to confirm opening it. Release builds
are signed with a Developer ID and notarized:

```sh
xcrun notarytool store-credentials claunes --apple-id you@example.com --team-id TEAMID --password app-specific-password   # once
scripts/release.sh "Developer ID Application: Name (TEAMID)" claunes   # -> build/waldo.Claunes-<version>.zip
```

## Use

1. Open waldo.Claunes. On first run it detects your existing Claude Desktop data in
   `~/Library/Application Support/Claude` and offers to import it into a named Claune.
   The import is a copy (an APFS clone: instant, no extra disk). The original stays as
   backup and keeps working with the normal Claude app.
2. **New Claune**: name, color, letter/emoji badge. An app appears in
   `~/Applications/Claunes/<Name>.app` and in Spotlight.
3. Launch it from Spotlight, the Dock, the menu bar item or the main window. Several
   Claunes run at the same time; switching never logs anything out.
4. Signing in happens in your browser. If the browser is already logged in to another
   Claude account, that account lands in the Claune. Sign out of claude.ai first or use
   a private window; the Claune shows this hint on its first launch. Keep the Claune in
   front when you click Sign in: waldo.Claunes routes the sign-in callback to the
   frontmost Claude instance.
5. **Edit MCP config** opens the Claune's own `claude_desktop_config.json`.
6. When Anthropic updates Claude Desktop, Claunes keep working. Each Claune is rebuilt
   from the new version automatically on its next launch; **Resync** in the main window
   does the same by hand.
7. **Delete** asks for confirmation and moves the app and the data folder to the Trash.

## How it works

Full research notes with the experiments that led here: [SPIKE.md](SPIKE.md).

- `~/Applications/Claunes/<Name>.app` is a small wrapper bundle we own (its own bundle id,
  name and generated icon). Inside it, `Contents/Claude.app` is an unmodified APFS clone
  of `/Applications/Claude.app`.
- The wrapper's executable is a tiny launcher. It execs the real Electron binary
  *through a symlink inside the wrapper* with `--user-data-dir=<Claune data dir>`.
  macOS derives the Dock identity from that exec path (ours), validates the code
  signature on the real file (Anthropic's, untouched), and Chromium finds its helpers
  and sandbox paths inside our bundle. So the Dock shows the Claune, the process still
  validates as Anthropic's signed app (Keychain access keeps working), and the renderer
  sandbox stays on.
- Data: `~/Library/Application Support/waldo.Claunes/profiles.json` plus one folder per
  Claune (`<uuid>/`), which is the Claune's `--user-data-dir`.
- Icons are generated at runtime (rounded tile in the profile color with the badge).
  No Anthropic artwork is shipped.
- The launcher checks at every start whether the embedded clone matches the installed
  Claude version and re-clones when it does not (well under a second).

## Known limitations

- **Claude's own auto-updater inside a Claune cannot install.** It would replace the
  wrapper with a plain Claude.app. `~/Applications/Claunes` is therefore kept read-only;
  the updater's install fails harmlessly and the Claune picks up the new version from
  `/Applications/Claude.app` on its next launch (after the normal Claude app updated).
  You may see Claude's "update failed / restart to update" banner inside a Claune.
- **Sign-in callback routing** depends on which Claude instance is frontmost when you
  click Sign in (the app re-asserts the `claude://` handler on activation).
- **macOS permission prompts repeat per Claune** (Accessibility, Screen Recording,
  folders...): each Claune is its own app to macOS.
- "Claude in Chrome" local pairing is disabled by Claude when the data dir is relocated.
- `~/.claude` (Claude Code CLI state) and `~/Library/Logs/Claude` are shared by all
  instances. Claude Code credentials in the Keychain are shared too.
- Mac only. Not sandboxed, not for the Mac App Store, not notarized.
