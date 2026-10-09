# Using your own DNS, reverse proxy and certificates (instead of Cloudflare Tunnel)

Most organisations already run DNS and a reverse proxy with their own TLS certificates.
**DNS, certificates and the proxy are your responsibility.** This folder shows where they fit.

The containers listen on this server only:

| Service | Local address | Your public name (example) |
|---|---|---|
| App (Agilebars / Timebars / Costbars) | `http://127.0.0.1:8687` | `agile.example.com`, `pmrm.example.com`, `ppm.example.com` |
| Strapi backend | `http://127.0.0.1:1337` | `be2.example.com` |
| Website / dashboards | `http://127.0.0.1:3001` | `www.example.com` |

Requirements:
- **HTTPS is required** for the app's offline mode (browsers only run service workers over HTTPS).
- Your browsers must trust the certificate's issuer (public CA, or your internal CA).
- Add every public app name to `../tbrun/runtime-config.json`, and every public origin to
  `CORS_ORIGINS` in `../tbbe/.env.local`.
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
server {                                                    # redirect plain HTTP
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}
```
Open ports 80 and 443 in the host firewall (`sudo ufw allow 80,443/tcp`) only when you use this.
