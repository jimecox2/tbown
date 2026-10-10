#!/usr/bin/env python3
"""tbconfig.py — one settings file (tbapps.conf) for the whole Timebars install.

Run it through scripts/03-config.sh:
  new     [file]   ask a few questions (domain, names) and write tbapps.conf - workstation or server
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
              "cloudflared": "cloudflared", "tbrun": "tbrun"}

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
ALL_KEYS = [k for k, *_ in PART1] + [k for k, _ in PART2] + [k for k, _ in PART3_FIXED] + PART3_SECRETS
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
           "# Apply on the server after every change:   bash $TB/scripts/03-config.sh apply",
           "# Keep a copy in your password manager: it holds every password of this install.",
           "",
           "# === 1. Your addresses: hostnames only - no https://, no / at the end ===" + domain_note]
    for k, _, c in PART1:
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
    out += ["", "# === 4. Made on the server by 03-config.sh apply - do not edit, do not share ==="]
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
    if not v["TUNNEL_TOKEN"]:
        warns.append("TUNNEL_TOKEN is empty: fine if this server uses its own proxy or an existing tunnel container")
    return errs, warns, v


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


def env_text(stack, pairs):
    head = [f"# {stack}/.env.local - GENERATED by 03-config.sh apply from ../tbapps.conf.",
            "# Do not edit: change tbapps.conf, then run   bash $TB/scripts/03-config.sh apply"]
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


# ---------------------------------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------------------------------
def cmd_new(path):
    keep = {}
    if os.path.exists(path):
        old = read_kv(path)
        keep = {k: old[k] for k in [k for k, _ in PART3_FIXED] + PART3_SECRETS if old.get(k)}
        keep.update({k: old[k] for k, _ in PART2 if old.get(k)})
        keep.update({k: val for k, val in old.items() if EXTRA_RE.match(k)})
        say(f"{path} already exists.")
        say("Starting again keeps its passwords made on the server (part 4), your pasted keys (part 2) and part 3;")
        say("you answer the address questions again. The old file is saved next to it.")
        if not yes("Start again"):
            say(f"Nothing changed. To edit it instead: nano {path}")
            return 1
        import time
        bak = f"{path}.{time.strftime('%Y%m%d-%H%M%S')}"
        os.rename(path, bak)
        say(f"Saved the old file as {bak}\n")
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
        say("  2. bash $TB/scripts/03-config.sh apply")
    else:
        say("  2. On the server: nano $TB/tbapps.conf, paste the whole file, save (Ctrl+O, Enter, Ctrl+X).")
        say("  3. On the server: bash $TB/scripts/03-config.sh apply")
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
    say("Check it, then: bash $TB/scripts/03-config.sh check   (should show no changes)")
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
    return changes


def cmd_apply(path, dry=False, assume_yes=False):
    if not ON_SERVER:
        say("apply runs on the server, in $TB. On a workstation use: 03-config.sh new")
        return 1
    if not os.path.isfile(path):
        say(f"No {path} yet. Make one:  bash $TB/scripts/03-config.sh new    (or import, on a server set up before)")
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
    gen = {}
    for k, d in PART3_FIXED:
        if not v[k]:
            gen[k] = d
    for k in PART3_SECRETS:
        if not v[k]:
            gen[k] = ",".join(rnd(32) for _ in range(4)) if k == "APP_KEYS" else rnd()
    if gen and not dry:
        db_keys = {"POSTGRES_USER", "POSTGRES_PASSWORD", "STRAPI_DB_NAME", "STRAPI_DB_USER", "STRAPI_DB_PASSWORD"}
        if postgres_initialised() and db_keys & set(gen):
            say("The database already exists, but tbapps.conf has no database password yet.")
            say("New passwords would lock Strapi out. Import the current ones first:")
            say(f"  mv {path} {path}.new && bash $TB/scripts/03-config.sh import   (then copy your part 1 and 2 over)")
            return 1
        update_conf_in_place(path, gen)
        say(f"Generated in tbapps.conf: {', '.join(sorted(gen))}")
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
    if dry:
        say("\n(check only: nothing written)")
        return 0
    if postgres_initialised():
        bad = [k for k in changes["postgres"][2] if k in ("POSTGRES_USER", "POSTGRES_PASSWORD", "STRAPI_DB_NAME",
                                                          "STRAPI_DB_USER", "STRAPI_DB_PASSWORD")]
        if bad:
            say(f"\nStopped: the database already exists and {', '.join(bad)} would change - Strapi would be locked out.")
            say("Put the old values back in tbapps.conf part 4 (03-config.sh import shows them), then apply again.")
            return 1
    for stack, (p, text, diff) in changes.items():
        if diff:
            # runtime-config.json holds no secrets and must be readable by nginx inside the container
            write_private(p, text, 0o644 if stack == "tbrun" else 0o600)
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
        for s in ("postgres", "tbbe", "tbwww", "tbhelp", "tbrun", "cloudflared"):
            if s in running:
                say(f"  {s}: docker compose up -d --force-recreate")
                subprocess.run(["docker", "compose", "up", "-d", "--force-recreate"], cwd=os.path.join(ROOT, s))
        say("Done. Check: bash $TB/scripts/06-health-check.sh && bash $TB/scripts/07-check-urls.sh")
    else:
        say("Later, in each of those folders: docker compose up -d --force-recreate")
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("new", "apply", "import", "check"):
        say(__doc__)
        return 1
    args = [a for a in argv[2:] if not a.startswith("-")]
    path = os.path.abspath(args[0]) if args else DEFAULT_CONF
    cmd = argv[1]
    if cmd == "new":
        return cmd_new(path)
    if cmd == "import":
        if not ON_SERVER:
            say("import runs on the server, in $TB.")
            return 1
        return cmd_import(path)
    return cmd_apply(path, dry=(cmd == "check"), assume_yes=("--yes" in argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
