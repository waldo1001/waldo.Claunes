# Phase 0 spike: how to run several Claude Desktop profiles side by side

Date: 2026-10-10. Machine: macOS 26.6.2 (25G83), Apple Silicon.
Claude Desktop 2.31226.1 in `/Applications/Claude.app` (Electron 44.4.3 / Chrome 152),
signed `Developer ID Application: Anthropic PBC (Q6L2SF6YDW)`, notarized, hardened runtime,
`codesign --verify --deep --strict` and `spctl -a` both pass. No library-validation exemption.
Electron fuse `ElectronAsarIntegrity` is on (hash of `Resources/app.asar` in Info.plist).

Everything below was observed on this Mac with throwaway `Test-*` instances. The real
`/Applications/Claude.app` and `~/Library/Application Support/Claude` were only read.
All throwaway bundles, data dirs and per-bundle caches were removed afterwards; the
`claude://` default handler was restored to `com.anthropic.claudefordesktop`.

## TL;DR

**Recommended: the "nested pristine clone" wrapper.** Each Claune is
`~/Applications/Claunes/<Name>.app`, a bundle we own (own Info.plist, bundle id, icon, a
tiny launcher binary) that contains an *unmodified* APFS clone of Claude.app at
`Contents/Claude.app`. The launcher execs the real Electron binary **through a symlink inside
our bundle** with `--user-data-dir=<Claune data dir>`.

Result (all verified, see experiments G below):

- Dock / Cmd-Tab / LaunchServices show the Claune's own name, bundle id and generated icon.
- The running process still validates as Anthropic's code
  (`codesign --verify <pid>`: valid, satisfies Designated Requirement, Team Q6L2SF6YDW).
- Chromium's renderer/GPU/network sandbox stays on; all 7 helper processes run.
- Data (login, history, `claude_desktop_config.json`) lands in the Claune's own folder.
- Nothing in `/Applications/Claude.app` is touched; no re-signing; no quarantine/Gatekeeper
  issues because our outer bundle is a locally created, unsigned wrapper and the inner bundle
  is byte-identical to the notarized original.
- An APFS clone of the 648 MB bundle takes 0.6 s and ~0 extra disk (`df` did not move after
  six clones).

Known weaknesses, detailed at the end: the Claune's own auto-updater must be blocked (it
would replace our wrapper), version drift needs a re-clone ("Resync"), the `claude://`
sign-in callback goes to whichever Claude instance registered last, `~/.claude` and the
shared log folder are not isolated, and macOS permission prompts (TCC) repeat per Claune.

## Questions and answers

### Does Claude Desktop honor `--user-data-dir`?

Yes. Launched next to the running original:

```
/Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=$PWD/spike/data/Test-A
```

Observed: a second `Claude` process (pid 76263) ran beside the real one (pid 65089);
`spike/data/Test-A` was created and filled (`Cookies`, `Local Storage`, `IndexedDB`,
`config.json`, `claude_desktop_config.json`, `ant-did`, ...). The helper processes carry
`--user-data-dir=<same path>`. The original's folder was untouched.

From the bundled main-process JS (read, not modified):

- Claude refuses to start if any of these switches is present:
  `remote-debugging-port`, `remote-debugging-pipe`, `ignore-certificate-errors`,
  `host-resolver-rules`, `host-rules`, `disable-web-security`, `log-net-log`,
  `net-log-capture-mode`, `ssl-key-log-file`, `renderer-cmd-prefix`, `utility-cmd-prefix`,
  `gpu-launcher`, `zygote-cmd-prefix`, `ppapi-plugin-launcher`, `nacl-loader-cmd-prefix`,
  `browser-subprocess-path`. `user-data-dir` is **not** on the list; it is handled by
  Chromium before any app code runs.
- The env var `CLAUDE_USER_DATA_DIR` exists but is deleted at startup in packaged builds
  ("signed builds ignore it") unless an Anthropic-signed `CLAUDE_CDP_AUTH` token is present.
  Not usable.
- A relocated data dir sets `localPairingDisabledReason = "userData relocated"`: the
  "Claude in Chrome" local pairing feature is disabled in Claunes. Everything else works.
- No `requestSingleInstanceLock` call: instances with different data dirs coexist. (Two
  instances on the *same* data dir would not be prevented either; our app must never do that.)
- `app.getPath("logs")` is not moved: all instances append to `~/Library/Logs/Claude/main.log`.

### How do we get a per-Claune Dock/Cmd-Tab identity? What breaks the signature?

Identity in the Dock, Cmd-Tab and `lsappinfo` is derived from the **path the executable was
exec'd through** (`_NSGetExecutablePath`, not realpath). Code-signing validation at exec time
is done on the **real file** and its enclosing bundle. Chromium derives helper and resource
paths from the **realpath** of the executable. Those three facts drive every result below.

| # | Layout | Launches? | Dock identity | Helpers (sandbox) | `codesign -v <pid>` |
|---|--------|-----------|---------------|-------------------|---------------------|
| a | `cp -c` clone of Claude.app, Info.plist edited (name/id) | **No: SIGKILL (exit 137)** | - | - | static: "invalid Info.plist" |
| a2 | pristine clone, only resources changed (InfoPlist.strings, icon, Assets.car removed) | **No: exit 137** | - | - | "file modified / file missing" |
| a3 | pristine clone, our shim as `Contents/MacOS/Claude`, real binary renamed | **No: exit 137** (shim itself killed) | - | - | - |
| a4 | pristine clone, untouched, binary run with `--user-data-dir` | Yes | "Claude", Claude icon | OK | valid |
| b | launcher app, execs `/Applications/Claude.app/.../Claude` directly | Yes | "Claude" at /Applications (identity lost) | OK | valid |
| c | wrapper: own plist + shim, `MacOS/Claude` symlink to real binary, Frameworks/Resources symlinked | Browser runs, then dies | own name/icon/id | **all helpers FATAL "Unable to find helper app"** | valid, DR satisfied |
| c' | same as c with `--no-sandbox` | Yes | own name/icon/id | OK (but unsandboxed) | valid, DR satisfied |
| c2 | wrapper with own plist, real binary and Frameworks **copied** (`cp -c`) into wrapper | **No: exit 137** | - | - | - |
| c3 | same with a hard link to the real binary | `ln: Operation not permitted` | - | - | - |
| **G** | **wrapper: own plist + shim, symlink to a pristine nested clone `Contents/Claude.app`** | **Yes** | **own name/icon/id** | **OK, sandboxed** | **valid, DR satisfied** |

Details:

- **(a) Modified clones are killed at exec.** Since macOS Ventura, Gatekeeper re-checks
  notarized apps on every launch even without quarantine. Any change (Info.plist, a
  resource, the main executable) kills the launch with SIGKILL. `cp` also attaches
  `com.apple.provenance`. So "copy Claude.app and rename it" is dead unless we re-sign.
- **(b) exec'ing the real path** works but LaunchServices reports
  `LSBundlePath=/Applications/Claude.app`, `LSDisplayName=Claude`. Dock shows Claude.
- **(c) symlink wrapper.** The browser process runs with our identity and validates as
  Anthropic's code, because the exec'd file is the real one. But Chromium builds the helper
  sandbox policy with `bundle-path = canonical(NSBundle.mainBundle)` = our wrapper, while the
  helpers were launched from the realpath'd location `/Applications/Claude.app/...`.
  Inside the sandbox a helper calls Electron's `OverrideChildProcessPath`, which reads
  `CFBundleName` from `/Applications/Claude.app/Contents/Info.plist`; the read is denied
  (only `(allow file-read* (subpath (param bundle-path)))` and the browser executable
  itself are allowed, see `sandbox/policy/mac/common.sb`), the name resolves to "", the
  helper path does not exist, `LOG(FATAL) "Unable to find helper app"`. Confirmed by
  `--no-sandbox` making the exact same bundle work.
- **(G) nested pristine clone** resolves the conflict: the symlink target
  `Contents/Claude.app/Contents/MacOS/Claude` is a real, unmodified, notarized bundle (exec
  validation passes), its realpath is *inside* our wrapper (so helpers are launched from
  `<Name>.app/Contents/Claude.app/Contents/Frameworks/...` and the sandbox bundle-path
  covers them), and the exec path is our bundle (so the identity is ours). One extra: Electron
  looks the asar hash up by the asar path relative to our `Contents`, so our Info.plist needs
  the `ElectronAsarIntegrity` entry duplicated under the key
  `Claude.app/Contents/Resources/app.asar` (without it: FATAL "Failed to get integrity for
  validatable asar archive"). Our Resources folder holds our icon plus a symlink per entry of
  the nested Resources (AppKit loads `MainMenu` and localizations from `NSBundle.mainBundle`).

Observed for G (pid 85443):

```
"LSDisplayName"="Test-G"  "LSBundlePath"=".../Test-G.app"  "CFBundleIdentifier"="be.waldo.claunes.test-g"
NSRunningApplication.icon center pixel #348A3E  (our green tile; Claude's icon samples #FFFEFF / #EE835D)
codesign --verify --verbose=2 85443: valid on disk, satisfies its Designated Requirement
codesign -dv 85443: Executable=.../Test-G.app/Contents/Claude.app/Contents/MacOS/Claude
                    Identifier=com.anthropic.claudefordesktop TeamIdentifier=Q6L2SF6YDW
7 helper processes, launched from .../Test-G.app/Contents/Claude.app/Contents/Frameworks/
no sandbox denials in the unified log; data dir populated (27 entries)
```

Spotlight indexes the wrapper (`mdfind -name Test-G`) and does **not** index the nested
`Claude.app` (packages are opaque), so no duplicate "Claude" entries appear.

How arguments get passed from Dock/Spotlight/Launchpad: LaunchServices starts
`CFBundleExecutable`, which is our launcher (`Contents/MacOS/<Name>`). The launcher reads the
data dir from the wrapper's Info.plist and `execv`s `Contents/MacOS/Claude` (the symlink) with
`--user-data-dir=...`, forwarding any LS arguments. `execv` keeps the pid, so the Dock tile
stays the same.

### Code signing summary

- Anthropic's signature stays valid on everything that is theirs: the nested clone is
  byte-identical (`codesign --verify --deep --strict Contents/Claude.app` passes), and the
  running Electron process validates dynamically as Anthropic's code.
- Our wrapper bundle as a whole is *not* signed (its main executable is our ad-hoc Swift
  launcher, its Info.plist is ours). `codesign --verify <Name>.app` fails, `spctl` rejects
  it. This does not matter for launching: it is created locally (no quarantine) and the
  executable that matters is validated on its real path. It would matter if someone zipped
  and shared a Claune bundle; that is not a use case (the app regenerates them).
- No approach that modifies the Claude bundle or re-signs is needed. Nothing to decide here.

### Auto-updater behaviour

Facts:

- Claude uses Squirrel.Mac (`Contents/Frameworks/Squirrel.framework/Resources/ShipIt`).
  ShipIt state is stored in `~/Library/Caches/<bundle id>.ShipIt/` (so per Claune) and its
  `targetBundleURL` is the running app's `NSBundle.mainBundle` (Electron's
  `auto_updater_mac.mm` + Squirrel strings `targetBundleURL`, `mainBundle`). The real app's
  last update log shows `targetBundleURL=file:///Applications/Claude.app/` and "Moving bundles
  directly" (it renames the old bundle away and the new one into place).
- The Claune instances **do** run the updater: `~/Library/Caches/be.waldo.claunes.test-g.ShipIt`
  appeared and `config.json` got `updaterRunningInstance`/`updaterLastSeenVersion`. During
  the spike no update was available ("The running client is already the latest version").
- `disableAutoUpdates` exists only as a managed setting (MDM profile or
  `/etc/claude-desktop/managed-settings.json`), i.e. system wide. Not usable per Claune.

Consequences and plan:

- A Claune never goes "stale and broken" when Anthropic updates `/Applications/Claude.app`:
  it has its own full clone and keeps running the old version. Drift is detected by comparing
  `CFBundleShortVersionString` of the nested clone with the real app; repair = delete the
  nested clone, re-clone, rewrite Info.plist (`ElectronAsarIntegrity`, version). The launcher
  does this automatically at launch when the Claune is not running; the main window exposes
  "Resync" as the manual fallback.
- The dangerous case is the Claune's own updater succeeding: ShipIt would replace
  `<Name>.app` with a pristine `Claude.app`, deleting our launcher, so the next Dock click
  would start Claude with the **default** data dir (account mix-up). Mitigation chosen:
  `~/Applications/Claunes` is kept read-only (`chmod 555`); ShipIt's rename then fails and
  Claude only logs a failed install. Our app temporarily makes the folder writable while it
  creates, updates or trashes Claunes. **Untested** (no update was available during the
  spike); Phase 6 verifies it by simulating ShipIt's rename against a 555 directory and keeps
  a second guard: the launcher refuses to exec if `Contents/Claude.app` is missing or the
  wrapper's Info.plist is not ours, and re-generates the Claune instead.

### `claude://` sign-in callback routing

- Sign-in opens the browser; the callback is a `claude://` URL handled by LaunchServices.
- Claude calls `app.setAsDefaultProtocolClient("claude")` at every launch with
  `keepExistingDefault: false`. Observed: after launching Test-G,
  `LSCopyDefaultHandlerForURLScheme("claude")` returned `be.waldo.claunes.test-g`; before, it
  was `com.anthropic.claudefordesktop`. So **the most recently launched Claude instance (or
  the real app) receives all sign-in callbacks**, regardless of which window started the login.
- Plan (Phase 4/7): the menu bar app observes app activation; whenever a Claune (or the real
  Claude) becomes frontmost it re-asserts that bundle id as the `claude` handler
  (`LSSetDefaultHandlerForURLScheme`, returned 0 without any prompt in the spike). The
  sign-in therefore lands in the Claune the user was looking at when clicking "Sign in".
  First-launch hint for a new Claune: sign out of claude.ai in the browser or use a private
  window, because the browser session, not Claude, decides *which account* signs in.

### Anything shared between instances outside the data dir?

| Item | Shared? | Notes |
|------|---------|-------|
| `~/Library/Application Support/Claude` | no | only the original uses it; Claunes use `.../waldo.Claunes/<id>/data` |
| Keychain "Claude Safe Storage" (Electron safeStorage key) | yes, by design | service name comes from the app name "Claude"; one key encrypts every instance's tokens. Harmless. ACL is satisfied because the process validates as Anthropic's code (verified dynamically; a real sign-in to confirm persistence is a hand check). |
| Keychain "Claude Code-credentials", `~/.claude` | yes | Claude Code CLI state, keyed by `$HOME`. The desktop honors `CLAUDE_CONFIG_DIR`; isolating it per Claune is possible later but would also split it from the terminal CLI. Left shared. |
| `~/Library/Logs/Claude/*.log` | yes | instances interleave in one `main.log`. Cosmetic. |
| `~/Library/Caches/<bundle id>`, `~/Library/Preferences/<bundle id>.plist`, Saved Application State, `~/Library/HTTPStorages/<bundle id>` | no | keyed by our per-Claune bundle id |
| TCC permissions (Accessibility, Screen Recording, Automation, folders) | no | keyed by bundle id: every Claune asks again. Expected cost of a distinct identity. |
| `claude://` default handler | one global | see above |
| Login item "Start Claude at login" (inside Claude) | per bundle | Electron registers the app bundle via SMAppService; launching the bundle goes through our launcher. To verify by hand. |
| `~/Library/Application Support/Claude-3p` | no | the "custom 3p" config dir is derived as `<userData>-3p`, so per Claune |

## Recommendation

Build on layout G. Per Claune:

```
~/Applications/Claunes/Work.app/
  Contents/Info.plist          ours: CFBundleIdentifier be.waldo.claunes.<uuid>, name, icon,
                               ElectronAsarIntegrity (both keys), ClauneID
  Contents/MacOS/Work          our launcher (Swift, ad-hoc signed), reads profiles.json
  Contents/MacOS/Claude  ->    ../Claude.app/Contents/MacOS/Claude
  Contents/Frameworks    ->    ../Claude.app/Contents/Frameworks
  Contents/Resources/          Claune.icns + one symlink per entry of ../Claude.app/Contents/Resources/<x>
  Contents/Claude.app/         pristine APFS clone of /Applications/Claude.app (never modified)
```

Data: `~/Library/Application Support/waldo.Claunes/profiles.json` and
`~/Library/Application Support/waldo.Claunes/<uuid>/data` as `--user-data-dir`.

Weaknesses, honestly: the updater block is a mitigation, not a cure; an Anthropic change to
Electron's helper-path logic or to macOS's bundle-identity rules could break the wrapper
(the shape is: "drift detection + Resync" handles version drift, not mechanism drift);
sign-in routing depends on re-asserting the URL handler; permission prompts repeat per
Claune; local Chrome pairing is off in Claunes.

## Spike artefacts kept in `spike/`

- `make-nested.sh`: builds a layout-G wrapper (the recommended one).
- `make-wrapper.sh`, `make-hl.sh`: the failed symlink-only and copied-binary variants.
- `shim/shim.swift`: the launcher used in all experiments.
- `shim/makeicon.swift`: generates the rounded-tile icon as `.icns` via `iconutil`.
- `shim/probe.swift`, `iconprobe.swift`, `handlerprobe.swift`, `sethandler.swift`: the probes
  used for `_NSGetExecutablePath`/`Bundle.main`, running-app icon sampling, and the
  `claude://` handler.
