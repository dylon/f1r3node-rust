Name: f1r3node
Version: %{node_version}
Release: 1%{?dist}
Summary: F1R3Node blockchain service and command-line client
License: Apache-2.0
URL: https://github.com/F1R3FLY-io/f1r3node-rust
Source0: f1r3node
Source1: f1r3node.service
Source2: LICENSE.TXT
Requires: systemd

%description
F1R3Node is a blockchain service and command-line client.
The package does not enable or start the service automatically.

%prep

%build

%install
install -Dm755 %{SOURCE0} %{buildroot}/usr/bin/f1r3node
install -Dm644 %{SOURCE1} %{buildroot}/usr/lib/systemd/system/f1r3node.service
install -Dm644 %{SOURCE2} %{buildroot}/usr/share/licenses/f1r3node/LICENSE.TXT

%post
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || :
fi

%preun
if [ "$1" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now f1r3node.service || :
fi

%postun
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || :
fi

%files
/usr/bin/f1r3node
/usr/lib/systemd/system/f1r3node.service
%license /usr/share/licenses/f1r3node/LICENSE.TXT
