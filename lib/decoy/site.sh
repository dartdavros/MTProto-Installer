# shellcheck shell=bash

write_decoy_site_content() {
  cat > "${DECOY_WWW_DIR}/index.html" <<EOF_DECOY_HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${DECOY_DOMAIN}</title>
  <style>
    :root { color-scheme: light dark; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f7f9fc; color: #1f2937; }
    main { max-width: 720px; margin: 12vh auto; padding: 0 24px; }
    h1 { font-size: 32px; margin: 0 0 12px; }
    p { line-height: 1.6; color: #4b5563; }
    .card { background: #fff; border-radius: 18px; padding: 28px 32px; box-shadow: 0 18px 48px rgba(15, 23, 42, 0.08); }
  </style>
</head>
<body>
  <main>
    <section class="card">
      <h1>Welcome to ${DECOY_DOMAIN}</h1>
      <p>This service is online.</p>
      <p>Please contact the site owner if you expected a different destination.</p>
    </section>
  </main>
</body>
</html>
EOF_DECOY_HTML
}
