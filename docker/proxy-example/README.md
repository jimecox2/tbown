# Using your own DNS, reverse proxy and certificates (instead of Cloudflare Tunnel)

Most organisations already run DNS and a reverse proxy with their own TLS certificates — and internal-only
names (`tb.company.internal`) need certificates from your own certificate authority.
**DNS, certificates and the proxy are your responsibility.** This folder shows where they fit.

Public names and no proxy of your own? The package has one built in — Caddy with free Let's Encrypt
certificates (`../proxy`, guide section 8.3) — so you do not need this page.

The containers listen on this server only:

| Service | Local address | Your public name (example) |
|---|---|---|
| App (Agilebars / Timebars / Costbars) | `http://127.0.0.1:8687` | `agile.example.com`, `pmrm.example.com`, `ppm.example.com` |
| Strapi backend | `http://127.0.0.1:1337` | `be2.example.com` |
| Website | `http://127.0.0.1:3001` | `www.example.com` |
| Timebars Cloud (dashboards, AI help) | `http://127.0.0.1:3010` | `cloud.example.com` |

Requirements:
- **HTTPS is required** for the app's offline mode (browsers only run service workers over HTTPS).
- Your browsers must trust the certificate's issuer (public CA, or your internal CA).
- Put every public name in `tbapps.conf` and run `bash $TB/scripts_v1/03-config.sh apply`: it writes the app's
  `runtime-config.json` and Strapi's allowed origins for you (guide section 7.1). Never edit those files.
- Do not cache `/index.html`, `/sw.js` or `/runtime-config.json` at the proxy.

Example (nginx on the host, certificates in `/etc/ssl/timebars/`):

```nginx
server {
    listen 443 ssl;
    server_name pmrm.example.com agile.example.com ppm.example.com;
    ssl_certificate     /etc/ssl/timebars/fullchain.pem;   # your certificate chain
    ssl_certificate_key /etc/ssl/timebars/privkey.pem;     # your private key (chmod 600)
    location / {
        proxy_pass http://127.0.0.1:8687;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
server {
    listen 443 ssl;
    server_name be2.example.com;
    ssl_certificate     /etc/ssl/timebars/fullchain.pem;
    ssl_certificate_key /etc/ssl/timebars/privkey.pem;
    client_max_body_size 30m;                               # matches Strapi's upload limit
    location / {
        proxy_pass http://127.0.0.1:1337;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
server {
    listen 443 ssl;
    server_name www.example.com;
    ssl_certificate     /etc/ssl/timebars/fullchain.pem;
    ssl_certificate_key /etc/ssl/timebars/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
server {
    listen 443 ssl;
    server_name cloud.example.com;
    ssl_certificate     /etc/ssl/timebars/fullchain.pem;
    ssl_certificate_key /etc/ssl/timebars/privkey.pem;
    client_max_body_size 10m;                               # the help assistant sends documentation with each question
    location / {
        proxy_pass http://127.0.0.1:3010;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 300s;                            # AI answers can take a while
    }
}
server {                                                    # redirect plain HTTP
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}
```
Open ports 80 and 443 in the host firewall (`sudo ufw allow 80,443/tcp`) only when you use this.
