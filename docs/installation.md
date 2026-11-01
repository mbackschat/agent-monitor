# Installation

Agent Monitor requires Apple Silicon and macOS 27 or later. Install the CLI/TUI, the Mac menu bar app, or both through Homebrew or release downloads; source builds require Xcode.

## Homebrew (recommended)

With [Homebrew](https://brew.sh) installed, choose either or both packages:

| Interface | Install | Start |
| --- | --- | --- |
| CLI and terminal dashboard | `brew install mbackschat/tap/agent-monitor` | `agent-monitor --tui` |
| Mac menu bar app | `brew install --cask mbackschat/tap/agent-monitor-app` | Open **Agent Monitor** from Applications. |

For example, install and open the terminal dashboard:

```sh
brew install mbackschat/tap/agent-monitor
agent-monitor --tui --group session
```

The [tap](https://github.com/mbackschat/homebrew-tap) verifies each download's checksum. The formula installs the CLI and its schema bundle; the cask installs the signed, notarized app without adding another CLI executable. Neither package requires Xcode.

To update:

```sh
brew update
brew upgrade agent-monitor
brew upgrade --cask agent-monitor-app
```

Run the upgrade command for each installed package; quit the Mac app before upgrading it. To remove a package, use `brew uninstall agent-monitor` or `brew uninstall --cask agent-monitor-app`. If you previously installed a CLI copy manually, use `which -a agent-monitor` to check whether an older copy takes precedence on your PATH.

## Install the release

Download the `agent-monitor-<version>-macos-arm64.tar.gz` archive and its `.sha256` file from the [latest release](https://github.com/mbackschat/agent-monitor/releases/latest). In the download directory, holding only that version:

```sh
shasum -a 256 -c agent-monitor-*-macos-arm64.tar.gz.sha256
tar -xzf agent-monitor-*-macos-arm64.tar.gz
cd agent-monitor-*-macos-arm64
mkdir -p "$HOME/.local/bin"
install -m 755 agent-monitor "$HOME/.local/bin/agent-monitor"
cp -R AgentMonitor_AgentMonitorPresentation.bundle "$HOME/.local/bin/"
```

CLI release binaries are ad-hoc signed, not Developer ID signed or notarized. macOS may block a downloaded copy; building locally from source is an alternative. Intel Macs and older macOS versions are not covered by releases.

Keep the resource bundle beside the executable: it contains the schema used by `--json-schema`. The archive includes the project and dependency licenses; retain them when redistributing the package.

## Install the Mac app

Download `agent-monitor-app-<version>-macos-arm64.zip` and its `.sha256` from the [release](https://github.com/mbackschat/agent-monitor/releases/latest). Check the checksum, extract the ZIP, then drag **Agent Monitor.app** to Applications and open it. It appears in the menu bar, without a Dock icon.

```sh
shasum -a 256 -c agent-monitor-app-*-macos-arm64.zip.sha256
```

The native release app is Developer ID-signed and notarized, with the ticket attached. For a manual installation, quit and replace the app to update it, or quit and remove it to uninstall. For a Homebrew installation, use the cask commands above. There is no in-app updater or login item.

Terminal focus may ask for Automation permission when explicitly requested. Monitoring needs no launch wrapper or provider login. See [Mac controls](usage/mac.md) for inspection, sampling and actions.

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
