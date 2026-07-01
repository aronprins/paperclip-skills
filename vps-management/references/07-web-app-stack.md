# 07 — Web Server & Application Stack

Serving applications securely: Nginx/Apache, TLS via Let's Encrypt with Mozilla-grade config,
PHP-FPM/Node process isolation, container basics, and database secure defaults. The recurring theme
is **run every service as an unprivileged, dedicated user, expose only what's needed, and encrypt in
transit.**

## Why

Mozilla's Server-Side TLS guidelines are the canonical config source, with three profiles:
**Modern** (TLS 1.3 only), **Intermediate** (TLS 1.2 + 1.3 — the general-purpose default), and
**Old** (legacy clients only). Application isolation (per-app system users, per-pool PHP-FPM,
non-root containers) contains the blast radius of any single app compromise. Databases bound to
localhost with strong auth remove a huge class of remote attacks.

## How

### 1. Nginx (or Apache) baseline
Install, enable, and confirm the firewall already allows 80/443 (`03`).
```bash
apt -y install nginx        # or: apt -y install apache2
systemctl enable --now nginx
```
Reduce information leakage and add security headers in `/etc/nginx/conf.d/hardening.conf`:
```nginx
server_tokens off;                                  # hide version
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
# Add a Content-Security-Policy tuned to the app.
```
Validate every change with `nginx -t` before `systemctl reload nginx` (Apache: `apachectl
configtest`).

### 2. TLS with Let's Encrypt
```bash
apt -y install certbot python3-certbot-nginx        # or -apache
certbot --nginx -d example.com -d www.example.com --redirect --agree-tos -m admin@example.com
certbot renew --dry-run                              # prove auto-renewal works
```
`acme.sh` is a lightweight alternative (pure shell, supports DNS-01 for wildcards). Certbot installs a
renewal timer automatically; the dry-run is your proof it will renew unattended.

### 3. Strong TLS config (Mozilla Intermediate — the default recommendation)
Generate current config from the Mozilla SSL Configuration Generator (now maintained at the TLSRef
Configurator community project after moving off ssl-config.mozilla.org) for your exact server +
version, then apply. The essentials:
```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;                       # off for intermediate/modern
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_stapling on;                                     # OCSP stapling
ssl_stapling_verify on;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```
Treat the cipher string as *current-at-time-of-writing* and regenerate from the Mozilla generator
periodically — TLS recommendations evolve.

### 4. PHP-FPM: per-app pool, unprivileged user
Run each site's PHP under its own system user and pool so one site can't read another's files or
sessions.
```bash
adduser --system --group --no-create-home site1
cp /etc/php/8.3/fpm/pool.d/www.conf /etc/php/8.3/fpm/pool.d/site1.conf
# In site1.conf: [site1]; user=site1; group=site1; listen=/run/php/site1.sock; chown/chmod the socket
# php.ini hardening: expose_php=Off; disable_functions=exec,passthru,shell_exec,system,proc_open,popen;
#                    open_basedir per site; upload_max_filesize sane; allow_url_fopen=Off if unused
systemctl reload php8.3-fpm
```
Block PHP execution in upload/writable directories at the Nginx level (`location ~* /uploads/.*\.php$
{ deny all; }`).

### 5. Node.js under a process manager
Never run Node as root or bare in a shell. Use a systemd unit (preferred for servers) or PM2.
```ini
# /etc/systemd/system/app.service
[Service]
User=appuser
WorkingDirectory=/srv/app
ExecStart=/usr/bin/node server.js
Restart=on-failure
Environment=NODE_ENV=production
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
```
Put Nginx in front as a TLS-terminating reverse proxy; bind Node to `127.0.0.1:3000`.

### 6. Docker / containers
- Never `--privileged`; drop capabilities (`--cap-drop=ALL --cap-add=<only needed>`).
- Run as non-root inside the container (`USER app` in the Dockerfile); consider read-only rootfs
  (`--read-only` + tmpfs for writable paths).
- **Docker bypasses ufw**: by default it manipulates iptables and can expose published ports past the
  host firewall. Bind published ports to localhost (`-p 127.0.0.1:3000:3000`) when only the reverse
  proxy needs them, or use `ufw-docker`/explicit rules. See `03`.
- Keep base images minimal and patched; scan images (Trivy/Grype) in CI.

### 7. Databases — secure defaults
Bind to localhost, set strong auth, remove the insecure install defaults.
```bash
# MySQL / MariaDB:
mysql_secure_installation        # MariaDB: mariadb-secure-installation
#   -> sets root password, removes anonymous users, disallows remote root, drops the test DB
# Ensure localhost-only in the server config (my.cnf / 50-server.cnf):
#   bind-address = 127.0.0.1
# MySQL 8: enable validate_password component; create least-privilege per-app users, never use root.

# PostgreSQL:
#   listen_addresses = 'localhost'    (postgresql.conf)
#   in pg_hba.conf prefer scram-sha-256 over md5/trust; one role per app with only needed grants
```
Run the DB as its packaged unprivileged user (mysql/postgres), never root. If an app truly needs
remote DB access, restrict it by firewall to specific source IPs and require TLS — but co-locating or
using a private network is safer.

## RHEL family differences
- Apache package is `httpd` (not `apache2`); config under `/etc/httpd/`. Nginx via EPEL or nginx repo.
- SELinux governs what web servers can read/connect to: use `setsebool -P httpd_can_network_connect
  on` for reverse proxies, and `chcon`/`semanage fcontext` for non-standard docroots — don't disable
  SELinux to "fix" a 403.
- `certbot` via EPEL or `dnf install certbot python3-certbot-nginx`.

## Pitfalls
- **Reloading Nginx/Apache without `-t`/`configtest`** — a syntax error takes the site down on reload.
- **Wildcard/legacy TLS** (`ssl_prefer_server_ciphers on` with an old cipher list) — regenerate from
  Mozilla instead.
- **PHP running as one shared user across all sites** — one compromised site reads all others.
- **DB left bound to `0.0.0.0`** with default/weak root — the classic internet-exposed-database breach.
- **Docker port published past the firewall** without realizing ufw didn't block it.
- **Forgetting the renewal dry-run** — certs silently expire 90 days later.

## Verify
```bash
nginx -t && systemctl reload nginx
curl -sI https://example.com | grep -i strict-transport-security     # HSTS present
# External TLS grade:
testssl.sh https://example.com        # or the SSL Labs site; aim for A/A+, no TLS 1.0/1.1, no weak ciphers
ss -tlnp | grep -E '3306|5432'        # DBs listening on 127.0.0.1 only, not 0.0.0.0
certbot renew --dry-run
```

## How managed services handle it
This is the panels' core competency and the strongest corroboration of the standard. Forge, Ploi,
RunCloud, SpinupWP, and ServerPilot all: isolate each site under its **own system user with its own
PHP-FPM pool**; provision **Let's Encrypt** certificates with automatic renewal; put **Nginx**
(sometimes with an Apache backend) in front with sane security headers; and install databases bound
to localhost with generated strong credentials rather than the insecure defaults. RunCloud and
GridPane add per-site isolation and web-application firewall options. The per-app-user + per-pool
pattern in steps 4–5 is copied directly from how these services keep tenants apart.
