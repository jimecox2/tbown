#!/usr/bin/env python3
"""tbconfig.py — one settings file (tbapps.conf) for the whole Timebars install.

Run it through scripts_v1/03-config.sh:
  new     [file]   ask a few questions (domain, names) and write tbapps.conf - workstation or server
                   (the Cloudflare tunnel method, guide section 8.1)
  new-proxy [file] the same for the proxy method: Caddy on this server, Let's Encrypt certificates, one
                   environment (PROD / STAGING / DEV / TRAINING) and its own domain (guide section 8.3);
                   run it through scripts_v1/03-config-proxy.sh
  dns     [IP]     proxy method: the DNS records to make at your registrar, and whether each name already
                   points at this server (IP: the address they must point to; on DigitalOcean found itself)
  apply   [file]   on the server: check tbapps.conf, generate the passwords and keys that are made on
                   the server (first time only), write every stack's .env.local and tbrun's
                   runtime-config.json, and offer to recreate the containers whose settings changed
  import  [file]   on a server set up before tbapps.conf: write tbapps.conf from the current
                   .env.local files and runtime-config.json (keeps every secret)
  check   [file]   only check tbapps.conf and show what apply would change; writes nothing

tbapps.conf is plain KEY=VALUE text. You type each address once; every derived value (URLs,
CORS origins, the app's runtime-config.json) is worked out by apply. The .env.local files and
runtime-config.json are outputs: edit tbapps.conf, then apply.
"""
import json
import os
import re
import secrets
import string
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                       # $TB on a server, the package folder on a workstation
ON_SERVER = os.path.isfile(os.path.join(ROOT, "tbbe", "docker-compose.yml"))
DEFAULT_CONF = os.path.join(ROOT, "tbapps.conf")
PRODUCTS = ("AB", "TB", "CB")
STACKS = ("postgres", "tbbe", "tbwww", "tbhelp", "cloudflared")
CONTAINERS = {"postgres": "tbpgdb", "tbbe": "tbbe", "tbwww": "tbwwwp", "tbhelp": "tbhelpapp",
              "cloudflared": "cloudflared", "tbrun": "tbrun", "proxy": "tbproxy"}

# ---------------------------------------------------------------------------------------------------
# The file layout. Parts 1-3 are yours; part 4 is filled on the server by apply.
# ---------------------------------------------------------------------------------------------------
PART1 = [  # key, default, comment
    ("APP_AB_HOST", "agile.{d}", "Agilebars"),
    ("APP_TB_HOST", "pmrm.{d}", "Timebars"),
    ("APP_CB_HOST", "ppm.{d}", "Costbars"),
    ("APP_OFFLINE", "yes", "yes = the three app addresses above keep working offline after the first visit"),
    ("EXTRA_APP_HOSTS", "", "optional extra app addresses, no offline: host:AB host:TB host:CB (space separated)"),
    ("BACKEND_HOST", "be2.{d}", "Strapi: login, licences, publishing"),
    ("WEBSITE_HOST", "www.{d}", "website: sales, sign-up, profile, orders"),
    ("CLOUD_HOST", "cloud.{d}", "Timebars Cloud: dashboards, notifications, AI help"),
    ("EMAIL_FROM", "noreply@{d}", "sender of registration and password emails"),
    ("EMAIL_REPLY_TO", "", "replies go here (empty = EMAIL_FROM)"),
    ("EXTRA_CORS_ORIGINS", "https://checkout.stripe.com,http://localhost:*", "other browser origins Strapi accepts, besides the addresses above"),
    ("OP_URL", "", "optional: your OpenProject address, e.g. https://op.example.com"),
]
PART2 = [  # key, comment
    ("TUNNEL_TOKEN", "Cloudflare tunnel token for THIS server (guide section 2.1). Empty if you use your own proxy or an existing tunnel container."),
    ("GEMINI_API_KEY", "Google Gemini key for Ask AI and AI Create (guide section 2.1). Empty = AI features off."),
    ("SENDGRID_API_KEY", "SendGrid key, starts with SG. - registration and password emails (guide section 2.1). Empty = no email."),
    ("STRAPI_ADMIN_TOKEN", "Strapi API token, Full access - made AFTER Strapi is up (guide section 15). Empty until then."),
    ("STRIPE_SECRET_KEY", "optional, only if you sell licences on the website: Stripe secret key, sk_test_... or sk_live_..."),
    ("STRIPE_PUBLISHABLE_KEY", "optional, with the one above: Stripe publishable key, pk_test_... or pk_live_..."),
]
PART3_FIXED = [("POSTGRES_USER", "pgsuper"), ("STRAPI_DB_NAME", "strapi"), ("STRAPI_DB_USER", "strapi"),
               ("PGADMIN_DEFAULT_EMAIL", "admin@example.com")]
PART3_SECRETS = ["POSTGRES_PASSWORD", "STRAPI_DB_PASSWORD", "PGADMIN_DEFAULT_PASSWORD", "APP_KEYS",
                 "API_TOKEN_SALT", "ADMIN_JWT_SECRET", "TRANSFER_TOKEN_SALT", "JWT_SECRET",
                 "WWW_NEXTAUTH_SECRET", "CLOUD_NEXTAUTH_SECRET"]
# The proxy method only (03-config-proxy.sh): Caddy on this server answers every address. These lines are
# written to tbapps.conf only when PUBLIC_ACCESS=proxy, so a Cloudflare tunnel install's file is unchanged.
PROXY_KEYS = [
    ("PUBLIC_ACCESS", "proxy = Caddy on this server answers every address, with Let's Encrypt certificates (guide section 8.3)"),
    ("ENVIRONMENT", "PROD, STAGING, DEV or TRAINING - shown by the checks and in backup names; not PROD = search engines kept out"),
    ("ACME_EMAIL", "Let's Encrypt sends certificate notices to this address"),
    ("BARE_DOMAIN", "this name redirects to the website, e.g. example.com -> www.example.com (empty = none)"),
]
ENVIRONMENTS = ("PROD", "STAGING", "DEV", "TRAINING")
# Names Let's Encrypt cannot certify (not public DNS). Such addresses need your own proxy (guide section 8.2).
PRIVATE_SUFFIXES = (".internal", ".local", ".lan", ".localhost", ".home.arpa", ".home", ".corp", ".test",
                    ".example", ".invalid", ".intranet", ".private")
ALL_KEYS = ([k for k, *_ in PART1] + [k for k, _ in PROXY_KEYS] + [k for k, _ in PART2]
            + [k for k, _ in PART3_FIXED] + PART3_SECRETS)
# Where each part-4 value already lives on a running server (stack, name in its .env.local). apply takes
# a value missing from tbapps.conf from there before it generates a new one, so a lost or renamed
# tbapps.conf never changes the passwords of an existing install.
PART3_FROM_ENV = {
    "POSTGRES_USER": [("postgres", "POSTGRES_USER")], "STRAPI_DB_NAME": [("postgres", "STRAPI_DB_NAME"), ("tbbe", "DATABASE_NAME")],
    "STRAPI_DB_USER": [("postgres", "STRAPI_DB_USER"), ("tbbe", "DATABASE_USERNAME")],
    "PGADMIN_DEFAULT_EMAIL": [("postgres", "PGADMIN_DEFAULT_EMAIL")],
    "POSTGRES_PASSWORD": [("postgres", "POSTGRES_PASSWORD")],
    "STRAPI_DB_PASSWORD": [("postgres", "STRAPI_DB_PASSWORD"), ("tbbe", "DATABASE_PASSWORD")],
    "PGADMIN_DEFAULT_PASSWORD": [("postgres", "PGADMIN_DEFAULT_PASSWORD")],
    "APP_KEYS": [("tbbe", "APP_KEYS")], "API_TOKEN_SALT": [("tbbe", "API_TOKEN_SALT")],
    "ADMIN_JWT_SECRET": [("tbbe", "ADMIN_JWT_SECRET")], "TRANSFER_TOKEN_SALT": [("tbbe", "TRANSFER_TOKEN_SALT")],
    "JWT_SECRET": [("tbbe", "JWT_SECRET")], "WWW_NEXTAUTH_SECRET": [("tbwww", "NEXTAUTH_SECRET")],
    "CLOUD_NEXTAUTH_SECRET": [("tbhelp", "NEXTAUTH_SECRET")],
}
DB_NAMES = ("POSTGRES_USER", "STRAPI_DB_NAME", "STRAPI_DB_USER")        # never change on an existing database
DB_PASSWORDS = ("POSTGRES_PASSWORD", "STRAPI_DB_PASSWORD")             # apply sets these in the database
# Part 3 (optional): any other setting for one stack, e.g. TBHELP__AI_REQUIRE_LOGIN=false
EXTRA_RE = re.compile(r"^(POSTGRES|TBBE|TBWWW|TBHELP|CLOUDFLARED)__([A-Z][A-Z0-9_]*)$")

HOST_RE = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")


def rnd(n=40):
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(n))


def say(msg=""):
    print(msg, flush=True)


def ask(prompt, default=""):
    try:
        ans = input(f"{prompt}{f' [{default}]' if default else ''}: ").strip()
    except EOFError:
        ans = ""
    return ans or default


def yes(prompt, default=True):
    ans = ask(f"{prompt} ({'Y/n' if default else 'y/N'})").lower()
    return default if not ans else ans.startswith("y")


# ---------------------------------------------------------------------------------------------------
# Reading and writing KEY=VALUE files (never executed as shell)
# ---------------------------------------------------------------------------------------------------
def read_kv(path):
    vals = {}
    if not os.path.isfile(path):
        return vals
    with open(path) as fh:
        for line in fh:
            m = re.match(r"^\s*([A-Z_][A-Z0-9_]*)\s*=(.*)$", line.rstrip("\n"))
            if m:
                v = m.group(2).strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                    v = v[1:-1]
                vals[m.group(1)] = v
    return vals


def write_private(path, text, mode=0o600):
    # Write in place (same file), so a running container that mounts it sees the change.
    exists = os.path.exists(path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.chmod(path, mode)
    return exists


def conf_text(v, domain_note=""):
    out = ["# tbapps.conf - every setting of this Timebars install, in one file.",
           "# Plain KEY=VALUE lines; no quotes needed, no spaces around =, no comments after a value.",
           "# Apply on the server after every change:   bash $TB/scripts_v1/03-config.sh apply",
           "# Keep a copy in your password manager: it holds every password of this install.",
           "",
           "# === 1. Your addresses: hostnames only - no https://, no / at the end ===" + domain_note]
    for k, _, c in PART1:
        out.append(f"# {c}")
        out.append(f"{k}={v.get(k, '')}")
    if v.get("PUBLIC_ACCESS") == "proxy":
        out += ["", "# --- the proxy on this server (03-config-proxy.sh) ---"]
        for k, c in PROXY_KEYS:
            out.append(f"# {c}")
            out.append(f"{k}={v.get(k, '')}")
    out += ["", "# === 2. Keys you paste (leave empty what you do not use) ==="]
    for k, c in PART2:
        if c:
            out.append(f"# {c}")
        out.append(f"{k}={v.get(k, '')}")
    out += ["", "# === 3. Optional: any other setting for one stack, as STACK__NAME=value ===",
            "# e.g. TBHELP__AI_REQUIRE_LOGIN=false   (stacks: POSTGRES TBBE TBWWW TBHELP CLOUDFLARED)"]
    out += [f"{k}={val}" for k, val in sorted(v.items()) if EXTRA_RE.match(k)]
    out += ["", "# === 4. Made on the server by 03-config.sh apply - do not share ===",
            "# To change POSTGRES_PASSWORD or STRAPI_DB_PASSWORD: type the new value, apply (it sets it in the database).",
            "# Never change the names (POSTGRES_USER, STRAPI_DB_NAME, STRAPI_DB_USER) once the database exists."]
    for k, _ in PART3_FIXED:
        out.append(f"{k}={v.get(k, '')}")
    for k in PART3_SECRETS:
        out.append(f"{k}={v.get(k, '')}")
    return "\n".join(out) + "\n"


def update_conf_in_place(path, updates):
    """Set the given keys in tbapps.conf, keeping the user's layout; append keys that are missing."""
    with open(path) as fh:
        lines = fh.read().splitlines()
    done = set()
    for i, line in enumerate(lines):
        m = re.match(r"^\s*([A-Z_][A-Z0-9_]*)\s*=", line)
        if m and m.group(1) in updates:
            lines[i] = f"{m.group(1)}={updates[m.group(1)]}"
            done.add(m.group(1))
    missing = [k for k in updates if k not in done]
    if missing:
        lines.append("# added by 03-config.sh")
        lines += [f"{k}={updates[k]}" for k in missing]
    write_private(path, "\n".join(lines) + "\n")


# ---------------------------------------------------------------------------------------------------
# Checking tbapps.conf
# ---------------------------------------------------------------------------------------------------
def clean_host(raw):
    h = raw.strip().lower()
    h = re.sub(r"^https?://", "", h).rstrip("/")
    return h


def check(c):
    """Returns (errors, warnings, normalised values)."""
    errs, warns, v = [], [], {}
    for k in ALL_KEYS:
        val = c.get(k, "").strip()
        v[k] = "" if val == "CHANGE_ME" else val
    hosts = {}
    for k in ("APP_AB_HOST", "APP_TB_HOST", "APP_CB_HOST", "BACKEND_HOST", "WEBSITE_HOST", "CLOUD_HOST"):
        raw = v[k]
        h = clean_host(raw)
        if not h:
            errs.append(f"{k} is empty")
            continue
        if h != raw:
            warns.append(f"{k}: using '{h}' (written '{raw}' - hostnames only, no https:// or /)")
        if not HOST_RE.match(h):
            errs.append(f"{k}: '{raw}' is not a hostname like pmrm.example.com")
        v[k] = h
        hosts.setdefault(h, []).append(k)
    extras = []
    for item in v["EXTRA_APP_HOSTS"].replace(",", " ").split():
        if ":" not in item:
            errs.append(f"EXTRA_APP_HOSTS: '{item}' must be host:AB, host:TB or host:CB")
            continue
        h, p = item.rsplit(":", 1)
        h, p = clean_host(h), p.upper()
        if p not in PRODUCTS or not HOST_RE.match(h):
            errs.append(f"EXTRA_APP_HOSTS: '{item}' must be host:AB, host:TB or host:CB")
            continue
        extras.append((h, p))
        hosts.setdefault(h, []).append("EXTRA_APP_HOSTS")
    v["_extras"] = extras
    v["_stack_extra"] = {}
    for k, val in c.items():
        m = EXTRA_RE.match(k)
        if m:
            v["_stack_extra"].setdefault(m.group(1).lower(), []).append((m.group(2), val.strip()))
        elif k not in ALL_KEYS and val.strip():
            warns.append(f"{k} is not a known setting - ignored (for one stack write e.g. TBHELP__{k})")
    for h, keys in hosts.items():
        if len(keys) > 1:
            errs.append(f"{h} is used twice ({', '.join(keys)}) - every address needs its own name")
    off = v["APP_OFFLINE"].lower() or "yes"
    if off not in ("yes", "no"):
        errs.append("APP_OFFLINE must be yes or no")
    v["APP_OFFLINE"] = off
    for k in ("EMAIL_FROM", "EMAIL_REPLY_TO"):
        if v[k] and not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", v[k]):
            errs.append(f"{k}: '{v[k]}' is not an email address")
    if v["OP_URL"] and not v["OP_URL"].startswith("http"):
        errs.append("OP_URL must start with https://")
    for k in ALL_KEYS:
        if re.search(r"\s", v[k]) and k != "EXTRA_APP_HOSTS":
            errs.append(f"{k} contains a space - paste the value only")
    if not v["GEMINI_API_KEY"]:
        warns.append("GEMINI_API_KEY is empty: Ask AI and AI Create stay off, and tbhelp's deploy.sh asks for it")
    if not v["SENDGRID_API_KEY"]:
        warns.append("SENDGRID_API_KEY is empty: no registration or password emails")
    elif not v["SENDGRID_API_KEY"].startswith("SG."):
        warns.append("SENDGRID_API_KEY does not start with SG. - check it")
    if not v["STRAPI_ADMIN_TOKEN"]:
        warns.append("STRAPI_ADMIN_TOKEN is empty: fine until Strapi is up (guide section 15)")
    access = v["PUBLIC_ACCESS"].lower() or "tunnel"
    if access not in ("tunnel", "proxy"):
        errs.append("PUBLIC_ACCESS must be proxy, or empty for the Cloudflare tunnel")
    v["PUBLIC_ACCESS"] = access
    if access == "proxy":
        check_proxy(v, hosts, errs, warns)
    elif not v["TUNNEL_TOKEN"]:
        warns.append("TUNNEL_TOKEN is empty: fine if this server uses its own proxy or an existing tunnel container")
    return errs, warns, v


def check_proxy(v, hosts, errs, warns):
    env = v["ENVIRONMENT"].upper() or "PROD"
    if env not in ENVIRONMENTS:
        errs.append(f"ENVIRONMENT must be one of {', '.join(ENVIRONMENTS)}")
    v["ENVIRONMENT"] = env
    if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", v["ACME_EMAIL"]):
        errs.append("ACME_EMAIL: an email address is needed - Let's Encrypt sends certificate notices to it")
    bare = clean_host(v["BARE_DOMAIN"])
    if bare:
        if not HOST_RE.match(bare):
            errs.append(f"BARE_DOMAIN: '{v['BARE_DOMAIN']}' is not a domain like example.com")
        hosts.setdefault(bare, []).append("BARE_DOMAIN")
        if len(hosts[bare]) > 1:
            errs.append(f"{bare} is used twice ({', '.join(hosts[bare])}) - every address needs its own name")
    v["BARE_DOMAIN"] = bare
    for h in hosts:
        if h.endswith(PRIVATE_SUFFIXES):
            errs.append(f"{h}: Let's Encrypt only certifies public DNS names - for internal names use your own "
                        "proxy and certificates (guide section 8.2)")
    if v["TUNNEL_TOKEN"]:
        warns.append("TUNNEL_TOKEN is set but not used: this install answers through its own proxy")
    if env != "PROD":
        if v["STRIPE_SECRET_KEY"].startswith("sk_live_") or v["STRIPE_PUBLISHABLE_KEY"].startswith("pk_live_"):
            warns.append(f"{env} server with a LIVE Stripe key - real cards would be charged; use the sk_test_ / pk_test_ keys")


# ---------------------------------------------------------------------------------------------------
# What each stack gets
# ---------------------------------------------------------------------------------------------------
def render(v):
    https = lambda h: f"https://{h}"
    be, www, cloud = https(v["BACKEND_HOST"]), https(v["WEBSITE_HOST"]), https(v["CLOUD_HOST"])
    run = {"AB": https(v["APP_AB_HOST"]), "TB": https(v["APP_TB_HOST"]), "CB": https(v["APP_CB_HOST"])}
    origins = [run["AB"], run["TB"], run["CB"]] + [https(h) for h, _ in v["_extras"]] + [www, cloud, be]
    origins += [o.strip() for o in v["EXTRA_CORS_ORIGINS"].split(",") if o.strip()]
    seen, cors = set(), []
    for o in origins:
        if o not in seen:
            seen.add(o)
            cors.append(o)
    out = {
        "postgres": [("POSTGRES_USER", v["POSTGRES_USER"]), ("POSTGRES_PASSWORD", v["POSTGRES_PASSWORD"]),
                     ("POSTGRES_DB", "postgres"), ("STRAPI_DB_NAME", v["STRAPI_DB_NAME"]),
                     ("STRAPI_DB_USER", v["STRAPI_DB_USER"]), ("STRAPI_DB_PASSWORD", v["STRAPI_DB_PASSWORD"]),
                     ("PGADMIN_DEFAULT_EMAIL", v["PGADMIN_DEFAULT_EMAIL"]),
                     ("PGADMIN_DEFAULT_PASSWORD", v["PGADMIN_DEFAULT_PASSWORD"])],
        "tbbe": [("DATABASE_HOST", "tbpgdb"), ("DATABASE_PORT", "5432"), ("DATABASE_NAME", v["STRAPI_DB_NAME"]),
                 ("DATABASE_USERNAME", v["STRAPI_DB_USER"]), ("DATABASE_PASSWORD", v["STRAPI_DB_PASSWORD"]),
                 ("DATABASE_SSL", "false"), ("APP_KEYS", v["APP_KEYS"]), ("API_TOKEN_SALT", v["API_TOKEN_SALT"]),
                 ("ADMIN_JWT_SECRET", v["ADMIN_JWT_SECRET"]), ("TRANSFER_TOKEN_SALT", v["TRANSFER_TOKEN_SALT"]),
                 ("JWT_SECRET", v["JWT_SECRET"]), ("HOST", "0.0.0.0"), ("PORT", "1337"), ("PUBLIC_URL", be),
                 ("CORS_ORIGINS", ",".join(cors)), ("SENDGRID_API_KEY", v["SENDGRID_API_KEY"]),
                 ("EMAIL_FROM", v["EMAIL_FROM"]), ("EMAIL_REPLY_TO", v["EMAIL_REPLY_TO"] or v["EMAIL_FROM"])],
        "tbwww": [("NEXTAUTH_SECRET", v["WWW_NEXTAUTH_SECRET"]), ("NEXTAUTH_URL", www),
                  ("STRAPI_ADMIN_TOKEN", v["STRAPI_ADMIN_TOKEN"]), ("STRIPE_SECRET_KEY", v["STRIPE_SECRET_KEY"]),
                  ("STRIPE_PUBLISHABLE_KEY", v["STRIPE_PUBLISHABLE_KEY"]), ("CLOUD_API_URL", f"{be}/api"),
                  ("CLOUD_URL", cloud), ("RUN_URL_AB", run["AB"]), ("RUN_URL_TB", run["TB"]), ("RUN_URL_CB", run["CB"])],
        "tbhelp": [("GEMINI_API_KEY", v["GEMINI_API_KEY"]), ("STRAPI_URL", "http://tbbe:1337/api"),
                   ("NEXTAUTH_SECRET", v["CLOUD_NEXTAUTH_SECRET"]), ("NEXTAUTH_URL", cloud),
                   ("CLOUD_API_URL", f"{be}/api"), ("CLOUD_WWW_URL", www), ("RUN_URL_AB", run["AB"]),
                   ("RUN_URL_TB", run["TB"]), ("RUN_URL_CB", run["CB"]), ("STRAPI_ADMIN_TOKEN", v["STRAPI_ADMIN_TOKEN"])],
        "cloudflared": [("TUNNEL_TOKEN", v["TUNNEL_TOKEN"])],
    }
    for stack, pairs in v.get("_stack_extra", {}).items():
        known = dict(out[stack])
        known.update(pairs)
        out[stack] = list(known.items())
    offline = v["APP_OFFLINE"] == "yes"
    sites = [{"host": v[f"APP_{p}_HOST"], "product": p, "offline": offline} for p in PRODUCTS]
    sites += [{"host": h, "product": p, "offline": False} for h, p in v["_extras"]]
    runtime = {"apiUrl": f"{be}/api", "wwwUrl": www, "cloudUrl": cloud, "opUrl": v["OP_URL"], "aiBaseUrl": "/ai",
               "sites": sites, "productPublicHost": {p: v[f"APP_{p}_HOST"] for p in PRODUCTS}}
    return out, runtime


def proxy_hosts(v):
    """Every name the proxy answers: (name, what it is, container:port or redirect target)."""
    rows = [(v[f"APP_{p}_HOST"], {"AB": "Agilebars", "TB": "Timebars", "CB": "Costbars"}[p], "tbrun:80") for p in PRODUCTS]
    rows += [(h, f"extra app address ({p})", "tbrun:80") for h, p in v["_extras"]]
    rows += [(v["BACKEND_HOST"], "Strapi backend", "tbbe:1337"), (v["WEBSITE_HOST"], "Website", "tbwwwp:3001"),
             (v["CLOUD_HOST"], "Timebars Cloud", "tbhelpapp:3010")]
    if v["BARE_DOMAIN"]:
        rows.append((v["BARE_DOMAIN"], f"redirects to {v['WEBSITE_HOST']}", f"https://{v['WEBSITE_HOST']}"))
    return rows


def caddy_text(v):
    prod = v["ENVIRONMENT"] == "PROD"
    t = ["# proxy/Caddyfile - GENERATED by 03-config.sh apply from ../tbapps.conf.",
         "# Do not edit: change tbapps.conf, then run   bash $TB/scripts_v1/03-config.sh apply",
         f"# Environment: {v['ENVIRONMENT']}. Caddy gets a Let's Encrypt certificate for every name below and renews it.",
         "{", f"\temail {v['ACME_EMAIL']}", "}", "",
         "(tb_common) {", "\theader -Server"]
    if not prod:
        t.append('\theader X-Robots-Tag "noindex, nofollow"')
    t += ["}", ""]
    rows = proxy_hosts(v)
    apps = [h for h, _, target in rows if target == "tbrun:80"]
    t += ["# Agilebars, Timebars, Costbars - one app; it picks the product from the name",
          f"{', '.join(apps)} {{", "\timport tb_common", "\treverse_proxy tbrun:80", "}", ""]
    for h, what, target in rows:
        if target == "tbrun:80":
            continue
        t += [f"# {what}", f"{h} {{", "\timport tb_common"]
        if target.startswith("https://"):
            t.append(f"\tredir {target}{{uri}} permanent")
        else:
            if target.startswith("tbwwwp") and not prod:
                t += ["\trespond /robots.txt <<TXT", "\t\tUser-agent: *", "\t\tDisallow: /", "\t\tTXT 200"]
            t.append(f"\treverse_proxy {target}")
        t += ["}", ""]
    return "\n".join(t)


def env_text(stack, pairs):
    head = [f"# {stack}/.env.local - GENERATED by 03-config.sh apply from ../tbapps.conf.",
            "# Do not edit: change tbapps.conf, then run   bash $TB/scripts_v1/03-config.sh apply"]
    return "\n".join(head + [f"{k}={val}" for k, val in pairs]) + "\n"


def runtime_text(rt):
    lines = ["{"]
    lines.append(f'  "apiUrl": {json.dumps(rt["apiUrl"])},')
    lines.append(f'  "wwwUrl": {json.dumps(rt["wwwUrl"])},')
    lines.append(f'  "cloudUrl": {json.dumps(rt["cloudUrl"])},')
    lines.append(f'  "opUrl": {json.dumps(rt["opUrl"])},')
    lines.append(f'  "aiBaseUrl": {json.dumps(rt["aiBaseUrl"])},')
    lines.append('  "sites": [')
    rows = [f'    {{ "host": {json.dumps(s["host"])}, "product": "{s["product"]}", "offline": {str(s["offline"]).lower()} }}'
            for s in rt["sites"]]
    lines.append(",\n".join(rows))
    lines.append("  ],")
    lines.append(f'  "productPublicHost": {json.dumps(rt["productPublicHost"])}')
    lines.append("}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------------------------------
# Docker helpers
# ---------------------------------------------------------------------------------------------------
def container_state(name):
    try:
        r = subprocess.run(["docker", "inspect", "-f", "{{.State.Status}}", name], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""
    except FileNotFoundError:
        return ""


def postgres_initialised():
    return bool(container_state("tbpgdb"))


def sql_ident(name):
    return '"' + name.replace('"', '""') + '"'


def sql_literal(text):
    return "'" + text.replace("'", "''") + "'"


def set_db_passwords(superuser, roles):
    """ALTER ROLE ... PASSWORD inside tbpgdb. roles: [(role, new password)]. The SQL goes in on stdin,
    so the passwords never show in a process list. Local connections inside the container need no
    password (the official image's default), so this works whatever the old passwords were."""
    if container_state("tbpgdb") != "running":
        say("tbpgdb is not running - start it first (cd $TB/postgres && ./deploy.sh), then apply again.")
        return False
    sql = "".join(f"ALTER ROLE {sql_ident(r)} PASSWORD {sql_literal(pw)};\n" for r, pw in roles)
    res = subprocess.run(["docker", "exec", "-i", "tbpgdb", "psql", "-U", superuser, "-d", "postgres", "-q",
                          "-v", "ON_ERROR_STOP=1"], input=sql, text=True, capture_output=True)
    if res.returncode != 0:
        say(f"Could not set the password in the database: {res.stderr.strip()}")
        return False
    return True


# ---------------------------------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------------------------------
def start_again(path):
    """An existing tbapps.conf: keep parts 2-4, save the old file. Returns the kept values, or None to stop."""
    if not os.path.exists(path):
        return {}
    old = read_kv(path)
    keep = {k: old[k] for k in [k for k, _ in PART3_FIXED] + PART3_SECRETS if old.get(k)}
    keep.update({k: old[k] for k, _ in PART2 if old.get(k)})
    keep.update({k: val for k, val in old.items() if EXTRA_RE.match(k)})
    say(f"{path} already exists.")
    say("Starting again keeps its passwords made on the server (part 4), your pasted keys (part 2) and part 3;")
    say("you answer the address questions again. The old file is saved next to it.")
    if not yes("Start again"):
        say(f"Nothing changed. To edit it instead: nano {path}")
        return None
    import time
    bak = f"{path}.{time.strftime('%Y%m%d-%H%M%S')}"
    os.rename(path, bak)
    say(f"Saved the old file as {bak}\n")
    return keep


def cmd_new(path):
    keep = start_again(path)
    if keep is None:
        return 1
    say("New tbapps.conf: the addresses users will open. Press Enter to accept a suggestion.\n")
    domain = ask("Your domain, e.g. example.com").lower().strip().strip(".")
    domain = clean_host(domain)
    if not HOST_RE.match(domain):
        say(f"'{domain}' is not a domain like example.com")
        return 1
    suffix = ask("A letter added to every name, e.g. s for staging (agiles, be2s ...); Enter for none").strip().lower()
    names = {"APP_AB_HOST": "agile", "APP_TB_HOST": "pmrm", "APP_CB_HOST": "ppm",
             "BACKEND_HOST": "be2", "WEBSITE_HOST": "www", "CLOUD_HOST": "cloud"}
    v = {k: f"{n}{suffix}.{domain}" for k, n in names.items()}
    say("\nProposed addresses:")
    labels = {"APP_AB_HOST": "Agilebars", "APP_TB_HOST": "Timebars", "APP_CB_HOST": "Costbars",
              "BACKEND_HOST": "Strapi backend", "WEBSITE_HOST": "Website", "CLOUD_HOST": "Timebars Cloud"}
    for k in names:
        say(f"  {labels[k]:<16} {v[k]}")
    if not yes("\nUse these"):
        for k in names:
            v[k] = clean_host(ask(f"  {labels[k]}", v[k]))
    v["APP_OFFLINE"] = "yes" if yes("Let the three app addresses work offline (recommended)") else "no"
    if yes(f"Also serve the short addresses ab{suffix} / tb{suffix} / cb{suffix}.{domain} (optional extras, no offline)", False):
        v["EXTRA_APP_HOSTS"] = f"ab{suffix}.{domain}:AB tb{suffix}.{domain}:TB cb{suffix}.{domain}:CB"
    v["EMAIL_FROM"] = ask("Sender address for emails", f"noreply@{domain}")
    v["EXTRA_CORS_ORIGINS"] = "https://checkout.stripe.com,http://localhost:*"
    for k, val in PART3_FIXED:
        v[k] = val
    v.update(keep)
    write_private(path, conf_text(v))
    say(f"\nWritten: {path}")
    say("Next:")
    say("  1. Open it in any text editor and paste your keys in part 2 (Gemini, SendGrid, tunnel token ...)" + (" - kept from before." if keep else "."))
    if ON_SERVER:
        say("  2. bash $TB/scripts_v1/03-config.sh apply")
    else:
        say("  2. On the server: nano $TB/tbapps.conf, paste the whole file, save (Ctrl+O, Enter, Ctrl+X).")
        say("  3. On the server: bash $TB/scripts_v1/03-config.sh apply")
    return 0


def choose(prompt, options, default):
    while True:
        ans = ask(f"{prompt} ({' / '.join(options)})", default).upper()
        if ans in options:
            return ans
        say(f"  Type one of: {', '.join(options)}")


def cmd_new_proxy(path):
    keep = start_again(path)
    if keep is None:
        return 1
    say("New tbapps.conf for the PROXY method: Caddy on this server answers every address and gets a free")
    say("Let's Encrypt certificate for each. One server = one environment with its own domain. Every name must be")
    say("a public DNS name pointing at this server - internal-only names (tb.company.internal) need your own proxy")
    say("and certificates instead (guide section 8.2). Press Enter to accept a suggestion.\n")
    env = choose("Environment of this server", ENVIRONMENTS, "PROD")
    while True:
        domain = clean_host(ask(f"Domain for the {env} environment, e.g. example.com or {env.lower()}.example.com").strip("."))
        if not HOST_RE.match(domain):
            say(f"  '{domain}' is not a domain like example.com")
        elif domain.endswith(PRIVATE_SUFFIXES):
            say(f"  {domain} is not a public DNS name - Let's Encrypt cannot certify it (guide section 8.2)")
        else:
            break
    say("\nAddress names for the three apps:")
    say(f"  1 = process names   agile.{domain}  pmrm.{domain}  ppm.{domain}")
    say(f"  2 = initials        ab.{domain}  tb.{domain}  cb.{domain}")
    style = ""
    while style not in ("1", "2"):
        style = ask("Which", "1")
    apps = ("agile", "pmrm", "ppm") if style == "1" else ("ab", "tb", "cb")
    names = {"APP_AB_HOST": apps[0], "APP_TB_HOST": apps[1], "APP_CB_HOST": apps[2],
             "BACKEND_HOST": "be2", "WEBSITE_HOST": "www", "CLOUD_HOST": "cloud"}
    v = {k: f"{n}.{domain}" for k, n in names.items()}
    labels = {"APP_AB_HOST": "Agilebars", "APP_TB_HOST": "Timebars", "APP_CB_HOST": "Costbars",
              "BACKEND_HOST": "Strapi backend", "WEBSITE_HOST": "Website", "CLOUD_HOST": "Timebars Cloud"}
    say("\nProposed addresses:")
    for k in names:
        say(f"  {labels[k]:<16} {v[k]}")
    say(f"  {'(redirect)':<16} {domain} -> {v['WEBSITE_HOST']}")
    if not yes("\nUse these"):
        for k in names:
            v[k] = clean_host(ask(f"  {labels[k]}", v[k]))
    v["APP_OFFLINE"] = "yes" if yes("Install the service worker, so the apps keep working offline after the first visit") else "no"
    v["ACME_EMAIL"] = ask("Your email for Let's Encrypt certificate notices", f"admin@{domain}")
    v["EMAIL_FROM"] = ask("Sender address for emails", f"noreply@{domain}")
    v["EXTRA_CORS_ORIGINS"] = "https://checkout.stripe.com,http://localhost:*"
    v.update({"PUBLIC_ACCESS": "proxy", "ENVIRONMENT": env,
              "BARE_DOMAIN": "" if domain in v.values() else domain})
    for k, val in PART3_FIXED:
        v[k] = val
    v.update(keep)
    v["TUNNEL_TOKEN"] = ""            # not used by the proxy method
    write_private(path, conf_text(v))
    say(f"\nWritten: {path}")
    if env != "PROD":
        say(f"{env}: search engines are kept out of every address, and Stripe should use its test keys (sk_test_ / pk_test_).")
    say("Next:")
    say("  1. Open it in any text editor and paste your keys in part 2 (Gemini, SendGrid ...)" + (" - kept from before." if keep else "."))
    step = 2
    if not ON_SERVER:
        say("  2. On the server: nano $TB/tbapps.conf, paste the whole file, save (Ctrl+O, Enter, Ctrl+X).")
        step = 3
    say(f"  {step}. On the server: bash $TB/scripts_v1/03-config.sh apply")
    say(f"  {step + 1}. Make the DNS records it lists:  bash $TB/scripts_v1/03-config.sh dns   (guide section 8.3)")
    return 0


def public_ip():
    """This server's public IPv4 on DigitalOcean: the Reserved IP when one is assigned, else the droplet's own."""
    import urllib.request
    base = "http://169.254.169.254/metadata/v1/"
    def get(p):
        try:
            with urllib.request.urlopen(base + p, timeout=2) as r:
                return r.read().decode().strip()
        except Exception:
            return ""
    if get("reserved_ip/ipv4/active") == "true":
        return get("reserved_ip/ipv4/ip_address")
    return get("interfaces/public/0/ipv4/address")


def cmd_dns(path, ip):
    import socket
    if not os.path.isfile(path):
        say(f"No {path} - make it first: bash $TB/scripts_v1/03-config-proxy.sh")
        return 1
    errs, _, v = check(read_kv(path))
    if errs:
        say("Fix tbapps.conf first (03-config.sh check shows what).")
        return 1
    if v["PUBLIC_ACCESS"] != "proxy":
        say("This install uses the Cloudflare tunnel: Cloudflare makes each DNS record when you add the published")
        say("application (guide section 8.1). Nothing to do at a registrar.")
        return 0
    ip = ip or public_ip()
    rows = proxy_hosts(v)
    zone = v["BARE_DOMAIN"]
    say(f"DNS records for {v['ENVIRONMENT']} - make one A record per name at your registrar (Rebel.ca: Edit DNS records),")
    say(f"pointing at {ip or '<this server public IP>'}. No AAAA (IPv6) records unless this server has that IPv6 address.\n")
    say(f"  {'':3} {'Type':<5} {'Host' + (f' (in {zone})' if zone else ''):<{max(24, len(zone) + 12)}} Full name")
    bad, elsewhere = 0, set()
    for h, what, _ in rows:
        host = ("@" if h == zone else h[: -len(zone) - 1]) if zone and (h == zone or h.endswith("." + zone)) else h
        try:
            got = sorted(set(socket.gethostbyname_ex(h)[2]))
        except OSError:
            got = []
        try:
            v6 = [a for a in socket.getaddrinfo(h, 443, socket.AF_INET6) if a]
        except OSError:
            v6 = []
        if not got:
            res, mark = "missing - not in DNS yet", "[ ]"
        elif ip and got != [ip]:
            res, mark = f"points to {', '.join(got)} - change it to {ip}", "[!]"
            elsewhere.update(got)
        else:
            res, mark = f"OK {', '.join(got)}", "[x]"
        if v6:
            res += "  + an AAAA record: delete it, or make sure it is this server"
        if mark != "[x]" or v6:
            bad += 1
        say(f"  {mark} {'A':<5} {host:<{max(24, len(zone) + 12)}} {h}\n        {res}")
    say("")
    if len(elsewhere) == 1 and bad == len(rows):
        say(f"Every name points to {elsewhere.pop()}: the registrar's parking or default records (often a * wildcard")
        say("and @). Delete them, then add the A records above.")
    if not ip:
        say("Give the server's public IP to compare against:  bash $TB/scripts_v1/03-config.sh dns <IP>")
    if bad:
        say(f"{bad} name(s) still to fix. New records can take a few minutes to show; run this again.")
        return 1
    say("Every name points at this server. Next: cd $TB/proxy && ./deploy.sh   (guide section 8.3)")
    return 0


def cmd_import(path):
    if os.path.exists(path):
        say(f"{path} already exists - nothing imported.")
        return 1
    env = {s: read_kv(os.path.join(ROOT, s, ".env.local")) for s in STACKS}
    if not any(env.values()):
        say(f"No .env.local files in {ROOT} - use: 03-config.sh new")
        return 1
    try:
        rt = json.load(open(os.path.join(ROOT, "tbrun", "runtime-config.json")))
    except Exception:
        rt = {}
    host = lambda url: clean_host(url or "").split("/")[0]
    v = {}
    sites = rt.get("sites", [])
    for p in PRODUCTS:
        main = [s for s in sites if s.get("product") == p and s.get("offline")] or [s for s in sites if s.get("product") == p]
        v[f"APP_{p}_HOST"] = main[0]["host"] if main else ""
    used = {v[f"APP_{p}_HOST"] for p in PRODUCTS}
    v["APP_OFFLINE"] = "yes" if any(s.get("offline") for s in sites) else "no"
    v["EXTRA_APP_HOSTS"] = " ".join(f'{s["host"]}:{s["product"]}' for s in sites if s.get("host") not in used)
    v["BACKEND_HOST"] = host(env["tbbe"].get("PUBLIC_URL") or rt.get("apiUrl", ""))
    v["WEBSITE_HOST"] = host(env["tbwww"].get("NEXTAUTH_URL") or rt.get("wwwUrl", ""))
    v["CLOUD_HOST"] = host(env["tbhelp"].get("NEXTAUTH_URL") or rt.get("cloudUrl", ""))
    v["EMAIL_FROM"] = env["tbbe"].get("EMAIL_FROM", "")
    v["EMAIL_REPLY_TO"] = env["tbbe"].get("EMAIL_REPLY_TO", "") if env["tbbe"].get("EMAIL_REPLY_TO") != v["EMAIL_FROM"] else ""
    derived = {f"https://{v[k]}" for k in ("APP_AB_HOST", "APP_TB_HOST", "APP_CB_HOST", "WEBSITE_HOST", "CLOUD_HOST")}
    derived |= {f"https://{s['host']}" for s in sites}
    v["EXTRA_CORS_ORIGINS"] = ",".join(o for o in env["tbbe"].get("CORS_ORIGINS", "").split(",") if o and o not in derived)
    v["OP_URL"] = rt.get("opUrl", "")
    allenv = {}
    for s in ("cloudflared", "tbhelp", "tbwww", "tbbe", "postgres"):
        allenv.update({k: val for k, val in env[s].items() if val and val != "CHANGE_ME"})
    for k, _ in PART2:
        v[k] = allenv.get(k, "")
    for k, d in PART3_FIXED:
        v[k] = env["postgres"].get(k) or d
    for k in ("POSTGRES_PASSWORD", "STRAPI_DB_PASSWORD", "PGADMIN_DEFAULT_PASSWORD"):
        v[k] = env["postgres"].get(k, "")
    v["STRAPI_DB_PASSWORD"] = v["STRAPI_DB_PASSWORD"] or env["tbbe"].get("DATABASE_PASSWORD", "")
    for k in ("APP_KEYS", "API_TOKEN_SALT", "ADMIN_JWT_SECRET", "TRANSFER_TOKEN_SALT", "JWT_SECRET"):
        v[k] = env["tbbe"].get(k, "")
    v["WWW_NEXTAUTH_SECRET"] = env["tbwww"].get("NEXTAUTH_SECRET", "")
    v["CLOUD_NEXTAUTH_SECRET"] = env["tbhelp"].get("NEXTAUTH_SECRET", "")
    for k in list(v):
        if v[k] == "CHANGE_ME":
            v[k] = ""
    write_private(path, conf_text(v))
    say(f"Written: {path} (from the current .env.local files and runtime-config.json, secrets kept).")
    say("Check it, then: bash $TB/scripts_v1/03-config.sh check   (should show no changes)")
    return 0


def plan_changes(v):
    out, rt = render(v)
    changes = {}
    for stack, pairs in out.items():
        p = os.path.join(ROOT, stack, ".env.local")
        old = read_kv(p)
        new = dict(pairs)
        diff = sorted(k for k in set(old) | set(new) if old.get(k, "") != new.get(k, ""))
        if not os.path.exists(p):
            diff = ["(new file)"]
        changes[stack] = (p, env_text(stack, pairs), diff)
    p = os.path.join(ROOT, "tbrun", "runtime-config.json")
    try:
        old_rt = json.load(open(p))
    except Exception:
        old_rt = None
    diff = [] if old_rt == json.loads(runtime_text(rt)) else (["(new file)"] if old_rt is None else
           sorted(k for k in set(old_rt or {}) | set(rt) if (old_rt or {}).get(k) != json.loads(runtime_text(rt)).get(k)))
    changes["tbrun"] = (p, runtime_text(rt), diff)
    if v["PUBLIC_ACCESS"] == "proxy":
        p = os.path.join(ROOT, "proxy", "Caddyfile")
        text = caddy_text(v)
        old = open(p).read() if os.path.isfile(p) else None
        changes["proxy"] = (p, text, [] if old == text else (["(new file)"] if old is None else ["Caddyfile"]))
    return changes


def cmd_apply(path, dry=False, assume_yes=False):
    if not ON_SERVER:
        say("apply runs on the server, in $TB. On a workstation use: 03-config.sh new")
        return 1
    if not os.path.isfile(path):
        say(f"No {path}. Renamed or moved? Put it back:  ls {path}*   (the running containers are not affected)")
        say("Otherwise make one:  bash $TB/scripts_v1/03-config.sh new   (proxy method: 03-config-proxy.sh)")
        say("- apply then keeps this server's current passwords.")
        return 1
    if os.stat(path).st_mode & 0o077:
        os.chmod(path, 0o600)
        say(f"Set {path} to chmod 600 (it holds passwords).")
    errs, warns, v = check(read_kv(path))
    for w in warns:
        say(f"  note: {w}")
    if errs:
        say("\nFix these in tbapps.conf, then run it again:")
        for e in errs:
            say(f"  - {e}")
        return 1
    if v["PUBLIC_ACCESS"] == "proxy" and not os.path.isdir(os.path.join(ROOT, "proxy")):
        say(f"No {ROOT}/proxy folder: send the package again (00-push-to-server.sh), then apply.")
        return 1
    # Part 4: an empty value is taken from this server's current .env.local files, else generated.
    env = {s: read_kv(os.path.join(ROOT, s, ".env.local")) for s in STACKS}
    gen, kept = {}, {}
    for k in [k for k, _ in PART3_FIXED] + PART3_SECRETS:
        if v[k]:
            continue
        cur = next((env[s].get(n) for s, n in PART3_FROM_ENV[k] if env[s].get(n) not in (None, "", "CHANGE_ME")), "")
        if cur:
            kept[k] = cur
        else:
            gen[k] = dict(PART3_FIXED).get(k) or (",".join(rnd(32) for _ in range(4)) if k == "APP_KEYS" else rnd())
    if (gen or kept) and not dry:
        update_conf_in_place(path, {**kept, **gen})
        if kept:
            say(f"Taken from this server's current settings into tbapps.conf: {', '.join(sorted(kept))}")
        if gen:
            say(f"Generated in tbapps.conf: {', '.join(sorted(gen))}")
    v.update(kept)
    v.update(gen)
    changes = plan_changes(v)
    say("\nSettings files:")
    changed = []
    for stack, (p, text, diff) in changes.items():
        if diff:
            changed.append(stack)
            say(f"  {stack:<12} {', '.join(diff)}")
        else:
            say(f"  {stack:<12} unchanged")
    # An existing database keeps its names; a changed password is set in the database first.
    pg_diff = changes["postgres"][2] if postgres_initialised() and env["postgres"] else []
    bad = [k for k in pg_diff if k in DB_NAMES]
    pw = [k for k in pg_diff if k in DB_PASSWORDS]
    if bad:
        say(f"\nStopped: the database already exists and {', '.join(bad)} would change - Strapi would be locked out.")
        say(f"Put the value(s) in tbapps.conf part 4 back to what {ROOT}/postgres/.env.local holds, then apply again.")
        return 1
    if pw:
        say(f"\nDatabase password(s) changed in tbapps.conf: {', '.join(pw)} - apply sets them in the database"
            " and recreates tbbe, so Strapi logs in with the new one.")
    if dry:
        say("\n(check only: nothing written)")
        return 0
    if pw:
        roles = [(v["POSTGRES_USER"] if k == "POSTGRES_PASSWORD" else v["STRAPI_DB_USER"], v[k]) for k in pw]
        if not set_db_passwords(env["postgres"].get("POSTGRES_USER") or v["POSTGRES_USER"], roles):
            say("Nothing written; the database still has the old password(s).")
            return 1
        say(f"Set in the database: {', '.join(pw)}")
    for stack, (p, text, diff) in changes.items():
        if diff:
            # runtime-config.json and the Caddyfile hold no secrets and must be readable inside the containers
            write_private(p, text, 0o644 if stack in ("tbrun", "proxy") else 0o600)
    if not changed:
        say("\nNothing changed.")
        return 0
    say("\nWritten.")
    running = [s for s in changed if container_state(CONTAINERS[s])]
    if not running:
        say("No running container uses the changed settings yet - start the stacks with ./deploy.sh (guide section 9 on).")
        return 0
    say(f"Running containers with new settings: {', '.join(CONTAINERS[s] for s in running)}")
    if assume_yes or yes("Recreate them now so they use the new settings"):
        for s in ("postgres", "tbbe", "tbwww", "tbhelp", "tbrun", "cloudflared", "proxy"):
            if s not in running:
                continue
            if s == "proxy":
                # Caddy re-reads its file without dropping connections; a recreate only if that fails
                say("  proxy: caddy reload")
                if subprocess.run(["docker", "exec", "tbproxy", "caddy", "reload", "--config", "/etc/caddy/Caddyfile",
                                   "--adapter", "caddyfile"]).returncode == 0:
                    continue
            say(f"  {s}: docker compose up -d --force-recreate")
            subprocess.run(["docker", "compose", "up", "-d", "--force-recreate"], cwd=os.path.join(ROOT, s))
        say("Done. Check: bash $TB/scripts_v1/06-health-check.sh && bash $TB/scripts_v1/07-check-urls.sh")
    else:
        say("Later, in each of those folders: docker compose up -d --force-recreate")
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("new", "new-proxy", "apply", "import", "check", "dns"):
        say(__doc__)
        return 1
    args = [a for a in argv[2:] if not a.startswith("-")]
    cmd = argv[1]
    if cmd == "dns":
        ip = next((a for a in args if re.match(r"^\d{1,3}(\.\d{1,3}){3}$", a)), "")
        rest = [a for a in args if a != ip]
        return cmd_dns(os.path.abspath(rest[0]) if rest else DEFAULT_CONF, ip)
    path = os.path.abspath(args[0]) if args else DEFAULT_CONF
    if cmd == "new":
        return cmd_new(path)
    if cmd == "new-proxy":
        return cmd_new_proxy(path)
    if cmd == "import":
        if not ON_SERVER:
            say("import runs on the server, in $TB.")
            return 1
        return cmd_import(path)
    return cmd_apply(path, dry=(cmd == "check"), assume_yes=("--yes" in argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
