# Installation

Agent Monitor runs on macOS 27 and has been tested on Apple Silicon. Install a release download or build from source, then run `agent-monitor` from any directory.

## Install the release

Download `agent-monitor-0.1.0-macos-arm64.tar.gz` and its `.sha256` file from [release v0.1.0](https://github.com/mbackschat/agent-monitor/releases/tag/v0.1.0). In the download directory:

```sh
shasum -a 256 -c agent-monitor-0.1.0-macos-arm64.tar.gz.sha256
tar -xzf agent-monitor-0.1.0-macos-arm64.tar.gz
cd agent-monitor-0.1.0-macos-arm64
mkdir -p "$HOME/.local/bin"
install -m 755 agent-monitor "$HOME/.local/bin/agent-monitor"
cp -R AgentMonitor_AgentMonitorPresentation.bundle "$HOME/.local/bin/"
```

The v0.1.0 binary is ad-hoc signed, not Developer ID signed or notarized. macOS may block a downloaded copy; building locally from source is an alternative. Intel Macs and older macOS versions are not covered by this release.

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

## Set up your PATH

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
