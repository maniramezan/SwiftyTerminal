#!/usr/bin/env bash
set -euo pipefail
cat > "${1:?output directory}/index.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url=documentation/swiftyterminal">
    <link rel="canonical" href="documentation/swiftyterminal">
    <title>SwiftyTerminal Documentation</title>
  </head>
  <body>
    <p>Redirecting to <a href="documentation/swiftyterminal">SwiftyTerminal documentation</a>…</p>
  </body>
</html>
HTML
