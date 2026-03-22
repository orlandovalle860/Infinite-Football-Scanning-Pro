# Build configuration (relay)

- **`RelayDebug.xcconfig`** — sets build setting `RELAY_HTTP_BASE_URL` for **Debug** (e.g. LAN `http://192.168.x.x:3000`).
- **`RelayRelease.xcconfig`** — sets `RELAY_HTTP_BASE_URL` for **Release** (e.g. `https://relay.yourdomain.com`).

The app target’s **base configuration** is **`App-Debug.xcconfig`** (Debug) or **`App-Release.xcconfig`** (Release). Those files `#include?` optional `../Secrets.xcconfig`, then include the matching **`Relay*.xcconfig`**.

**Info.plist** contains `<string>$(RELAY_HTTP_BASE_URL)</string>` for key `RELAY_HTTP_BASE_URL`. Xcode substitutes the value at build time from the xcconfig chain (no hardcoded URL in Swift).

**xcconfig note:** a literal `http://` on one line is parsed as `http:` plus a `//` comment. Relay configs use `SLASH = /` and `http:$(SLASH)$(SLASH)host…` to build `//` safely.

To change the relay URL **without editing Swift**: edit **`RelayDebug.xcconfig`** and/or **`RelayRelease.xcconfig`**.

### App Transport Security (ATS) and relay

iOS **blocks plain HTTP** (and **non-TLS WebSocket**) by default. If `RELAY_HTTP_BASE_URL` is `http://…` (e.g. a VPS IP), API calls fail with **NSURLErrorDomain -1022** unless ATS allows it.

**Info.plist** includes **`NSAllowsArbitraryLoads`** so development relay URLs over **http://** / **ws://** work. For **App Store** builds, prefer **`https://`** and **`wss://`**, then consider tightening or removing this exception per review guidelines.
