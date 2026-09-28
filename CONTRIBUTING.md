# Contributing to Snapper

Thanks for helping out. This guide covers setup, the build workflow (including
one macOS permission gotcha that will bite you), and how to get changes merged.

## Setup

```sh
git clone https://github.com/Marvelxy/snapper.git
cd snapper
make app   # builds ./build/Snapper.app (universal arm64 + x86_64)
```

Requirements: macOS 14+, Swift 6 toolchain.

## Build targets

| Command | What it does |
|---|---|
| `make app` | Build the universal bundle into `./build` |
| `make run` | **Build** and launch the bundle |
| `make open` | Launch the already-built bundle **without rebuilding** |
| `make install` | Build and copy to `/Applications/Snapper.app` |
| `make run-raw` | Run the raw executable (capture won't work reliably — see below) |
| `Snapper --diagnose` | Headless capture self-check for the exact binary |

## ⚠️ Read this: rebuilding revokes Screen Recording permission

macOS ties the Screen Recording grant to the binary's code signature hash, and
local builds are ad-hoc signed — so **every rebuild invalidates your grant**
and the app will prompt for permission again.

Workflow:

1. `make app` (build once)
2. Launch, grant Screen Recording when prompted
3. Fully quit (`pkill Snapper`)
4. From then on use `make open` — never `make run` — unless the code changed
5. After a code change: rebuild, delete the stale Snapper entry in
   System Settings → Privacy & Security → Screen & System Audio Recording,
   grant again, relaunch

Always test capture against the `.app` bundle, never `make run-raw`: the raw
executable has a different identity and your grant won't apply to it.

## Making changes

- Create a feature branch from `main` (`git checkout -b feature/my-change`)
- Keep changes focused; one concern per pull request
- Verify with `swift build -c release` at minimum, plus `make app` if you
  touched packaging; exercise the editor manually (`Take Screenshot` → select →
  annotate → copy/save)
- Code style: match the surrounding code — concise `//` comments, `MARK:`
  sections, SwiftUI state lives in the session object (`UI/SnapperSession.swift`),
  coordinates are top-left-origin points mapped to pixels by `pixelScale`
- Open a PR against `main` with a short description and how you tested

## Reporting issues

Include: macOS version, how you launched the app (bundle path), the output of
`Snapper --diagnose` for that exact binary, and what you expected vs. what happened.

## License

By contributing you agree your changes are released under the project's
[GPL-3.0](LICENSE) license.
