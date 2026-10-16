# F1R3Node macOS package

The component package installs the F1R3Node command line program. It does not install F1R3Gaze or Embers.

The package supports arm64 and x86_64. The node binary contains both architectures.

## Build

Build the node on one macOS arm64 host and one macOS x86_64 host. Use the Rust toolchain in `rust-toolchain.toml`.

1. Install `protobuf`, `pkg-config`, and `lmdb` with Homebrew on each host.
2. Run `cargo build --release --locked -p node --bin node` on each host.
3. Copy both `target/release/node` files to one macOS host.
4. Compute each file's SHA-256 digest with `shasum -a 256`.
5. Run `packaging/macos/build.sh` with the version, both files, and both digests.

The build command accepts `--version`, `--arm64`, `--arm64-sha256`, `--x86_64`, `--x86_64-sha256`, and `--out`.

The script checks each binary's version, architecture, hash, and dynamic libraries. It creates a `.pkg`, a `.tar.gz`, and a SHA-256 manifest.

GitHub CI builds both binaries and uploads their SHA-256 digests. It installs the universal package on both architectures.

The installation checks an upgrade, service startup and restart, and preservation of user data after service removal.

## Install and operate

1. Open the component `.pkg` to install the node command.
2. Run `f1r3node --version` to check the installation.
3. Create `~/Library/Application Support/F1R3Node/rnode.conf` with a standalone or bootstrap configuration.
4. Run `f1r3node-service install` to enable and start the per-user service.
5. Run `f1r3node-service status` to inspect the service.
6. Run `f1r3node-service stop` to stop the service for the current login session.
7. Run `f1r3node-service start` to start the service again.
8. Run `f1r3node-service uninstall` to remove the per-user service.

For an isolated local node, set `standalone = true` in `rnode.conf`.

For an existing network, set `protocol-client.bootstrap` to a valid `rnode://` peer. Use the network operator's configuration values.

The service stores data in `~/Library/Application Support/F1R3Node`. It binds the API to `127.0.0.1`.

The component package does not enable the service. Service removal preserves the data directory.

The current CI artifacts have no Apple signature or notarization. Public distribution needs the required Apple identities and notarization credentials.
