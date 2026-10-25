# Third-party notices

This application bundles and launches the following third-party components:

## cloudflared

- Project: Cloudflare Tunnel client (`cloudflared`)
- Copyright: Cloudflare, Inc.
- License: Apache License 2.0
- Source: https://github.com/cloudflare/cloudflared
- Bundled binary: `data/flutter_assets/assets/bin/cloudflared.exe`
  (extracted at first launch to `%APPDATA%\com.qodertunnel\cf_tunnel_manager\bin\cloudflared.exe`)

The official cloudflared binary redistributed here is unmodified.

## cloudflared (Android build)

- The Android APK ships a locally built `libcloudflared.so` compiled from the
  same upstream source (Apache License 2.0) with:
  - `GOOS=android GOARCH=arm64 CGO_ENABLED=1` so DNS goes through Android's
    resolver (a static Linux build cannot read `/etc/resolv.conf`, which Android
    does not provide);
  - a small patch in `cmd/cloudflared/main.go` (`useEnvDNSServer`) that lets the
    caller pass the system resolver via the `CF_DNS_SERVER` environment variable,
    because bionic cannot answer the SRV queries used for edge discovery.
- Build command:
  `GOOS=android GOARCH=arm64 CGO_ENABLED=1 CC=<ndk>/aarch64-linux-android21-clang go build -o libcloudflared.so ./cmd/cloudflared`

## Flutter

- Copyright: Google LLC
- License: BSD 3-Clause
- Source: https://github.com/flutter/flutter

Flutter license notices for the engine and packaged dependencies are also
embedded by the Flutter tool in the application's asset bundle.

## Dart packages

`provider`, `path_provider`, `http`, `url_launcher`, `flutter_localizations`,
and their transitive dependencies are distributed under their respective
open-source licenses (Apache-2.0, BSD-3-Clause, MIT). Full texts are available
from https://pub.dev and in each package's repository.

## Windows SDK / MSVC runtime

Redistributed runtime components are covered by Microsoft's Visual Studio
license terms.
