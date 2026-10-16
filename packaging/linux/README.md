# F1R3Node Linux packages

The package installs `/usr/bin/f1r3node` and a systemd service. Installation does not enable or start the service.

The service stores persistent data in `/var/lib/f1r3node`. It binds the HTTP administrative API to `127.0.0.1`.

## Configure the service

Create `rnode.conf` before you start the service. An empty bootstrap setting with `standalone = false` makes a fresh node exit.

For an isolated local node, use this configuration:

```bash
sudo install -d -m 0700 /var/lib/f1r3node
printf 'standalone = true\n' | sudo tee /var/lib/f1r3node/rnode.conf >/dev/null
sudo systemctl enable --now f1r3node.service
curl --fail http://127.0.0.1:40403/status
```

For an existing network, set `protocol-client.bootstrap` to a valid `rnode://` peer. Use the network operator's configuration values.

Stop the service with `sudo systemctl stop f1r3node.service`. Disable it with `sudo systemctl disable f1r3node.service`.

Package removal preserves the data directory. The administrator controls data removal.

## Build packages locally

Build the release binary with `cargo build --release --locked -p node --bin node`. Compute its SHA-256 digest with `sha256sum`.

Run `packaging/linux/build.sh --help` for the DEB, Arch, RPM, and tar command options.

The package script checks the binary version, architecture, hash, and runtime libraries. GitHub CI installs and tests each package.
