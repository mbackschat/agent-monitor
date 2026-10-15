# Installation

Agent Monitor runs on macOS 27 or later and has been tested on Apple Silicon. Install with Homebrew, use a release download, or build from source, then run `agent-monitor` from any directory.

## Homebrew (recommended)

With [Homebrew](https://brew.sh) installed:

```sh
brew install mbackschat/tap/agent-monitor
agent-monitor --tui --group session
```

The [tap](https://github.com/mbackschat/homebrew-tap) installs the verified release archive and its schema resource bundle. Xcode and manual PATH changes are not required when Homebrew is already on your PATH. The formula requires Apple Silicon and macOS 27 or later.

To update:

```sh
brew update
brew upgrade agent-monitor
```

To remove it, run `brew uninstall agent-monitor`. If you previously installed a copy manually, use `which -a agent-monitor` to check whether an older copy takes precedence on your PATH.

## Install the release

Download `agent-monitor-0.2.1-macos-arm64.tar.gz` and its `.sha256` file from [release v0.2.1](https://github.com/mbackschat/agent-monitor/releases/tag/v0.2.1). In the download directory:

```sh
shasum -a 256 -c agent-monitor-0.2.1-macos-arm64.tar.gz.sha256
tar -xzf agent-monitor-0.2.1-macos-arm64.tar.gz
cd agent-monitor-0.2.1-macos-arm64
mkdir -p "$HOME/.local/bin"
install -m 755 agent-monitor "$HOME/.local/bin/agent-monitor"
cp -R AgentMonitor_AgentMonitorPresentation.bundle "$HOME/.local/bin/"
```

The v0.2.1 binary is ad-hoc signed, not Developer ID signed or notarized. macOS may block a downloaded copy; building locally from source is an alternative. Intel Macs and older macOS versions are not covered by this release.

Keep the resource bundle beside the executable: it contains the schema used by `--json-schema`. The archive includes the project and dependency licenses; retain them when redistributing the package.

## Build from source

Requires Xcode 27 with Swift 6.4. Clone this repository, then build and install:

```sh
git clone https://github.com/mbackschat/agent-monitor.git
cd agent-monitor
swift build -c release
mkdir -p "$HOME/.local/bin"
install -m 755 .build/release/agent-monitor "$HOME/.local/bin/agent-monitor"
cp -R .build/release/AgentMonitor_AgentMonitorPresentation.bundle "$HOME/.local/bin/"
```

Dependencies are fetched automatically during the build. Neither installation method requires `sudo`.

## PATH for manual installations

If `$HOME/.local/bin` is not already on your `PATH`, add this line to `~/.zshrc` (or your shell's equivalent configuration) and open a new terminal. You can also run it in the current terminal to use the command immediately:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Run

From any directory:

```sh
agent-monitor --help
agent-monitor --version
agent-monitor --tui --group session
```

The installed command runs directly; it does not invoke SwiftPM or rebuild the project. See the [usage guide](usage.md) for controls and options, or the [development guide](development.md) for source-level work.
