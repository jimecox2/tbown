#!/usr/bin/env python3
"""make-secrets.py — keys and passwords of this environment, made where it runs.

Reads ../secrets.env (this environment folder), makes every EMPTY password with a strong random value
(the first time only - a value once made is never changed), saves it back, and writes each stack's
.secrets.env (chmod 600) from it. Run it through 03-make-passwords.sh (deploy-all.sh does), and again after you paste a key:

    bash $TB/scripts/03-make-passwords.sh

Passwords are made on the machine that runs this, so with the recommended hand-over they never leave
the server. Never change a database password here after the first deploy: the database keeps the old one.
"""
import os
import re
import secrets
import string
import sys

ENV_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECRETS = os.path.join(ENV_DIR, "secrets.env")

KEYS = [  # pasted by you; empty = that feature is off
    ("GEMINI_API_KEY", "Google Gemini key, starts with AIza - Ask AI, AI Create, help assistant"),
    ("SENDGRID_API_KEY", "SendGrid key, starts with SG. - registration and password emails"),
    ("STRAPI_ADMIN_TOKEN", "Strapi API token, Full access - made AFTER Strapi is up (guide: Strapi API token)"),
    ("STRIPE_SECRET_KEY", "only if you sell licences: sk_test_... (not PROD) or sk_live_... (PROD)"),
    ("STRIPE_PUBLISHABLE_KEY", "with the one above: pk_test_... or pk_live_..."),
]
PASSWORDS = ["POSTGRES_PASSWORD", "STRAPI_DB_PASSWORD", "PGADMIN_DEFAULT_PASSWORD", "APP_KEYS", "API_TOKEN_SALT",
             "ADMIN_JWT_SECRET", "TRANSFER_TOKEN_SALT", "JWT_SECRET", "WWW_NEXTAUTH_SECRET", "CLOUD_NEXTAUTH_SECRET"]
# What each stack reads: (name in the container, name in secrets.env)
STACKS = {
    "postgres": [("POSTGRES_PASSWORD", "POSTGRES_PASSWORD"), ("STRAPI_DB_PASSWORD", "STRAPI_DB_PASSWORD"),
                 ("PGADMIN_DEFAULT_PASSWORD", "PGADMIN_DEFAULT_PASSWORD")],
    "tbbe": [("DATABASE_PASSWORD", "STRAPI_DB_PASSWORD"), ("APP_KEYS", "APP_KEYS"), ("API_TOKEN_SALT", "API_TOKEN_SALT"),
             ("ADMIN_JWT_SECRET", "ADMIN_JWT_SECRET"), ("TRANSFER_TOKEN_SALT", "TRANSFER_TOKEN_SALT"),
             ("JWT_SECRET", "JWT_SECRET"), ("SENDGRID_API_KEY", "SENDGRID_API_KEY")],
    "tbwww": [("NEXTAUTH_SECRET", "WWW_NEXTAUTH_SECRET"), ("STRAPI_ADMIN_TOKEN", "STRAPI_ADMIN_TOKEN"),
              ("STRIPE_SECRET_KEY", "STRIPE_SECRET_KEY"), ("STRIPE_PUBLISHABLE_KEY", "STRIPE_PUBLISHABLE_KEY")],
    "tbhelp": [("GEMINI_API_KEY", "GEMINI_API_KEY"), ("NEXTAUTH_SECRET", "CLOUD_NEXTAUTH_SECRET"),
               ("STRAPI_ADMIN_TOKEN", "STRAPI_ADMIN_TOKEN")],
}


def rnd(n=40):
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(n))


def read_kv(path):
    vals = {}
    if os.path.isfile(path):
        for line in open(path):
            m = re.match(r"^\s*([A-Z_][A-Z0-9_]*)\s*=(.*)$", line.rstrip("\n"))
            if m:
                vals[m.group(1)] = m.group(2).strip()
    return vals


def write_private(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.chmod(path, 0o600)


def template(env, vals):
    """The secrets.env layout; scripts/apply.sh on the dev box writes it the same way (empty passwords)."""
    out = [f"# secrets.env - keys and passwords of the {env} environment. chmod 600.",
           "# Never in git, never in email. Keep a copy in your password vault.",
           "# After a change: bash scripts/03-make-passwords.sh && ./deploy-all.sh",
           "", "# === Keys you paste (empty = that feature is off) ==="]
    for k, c in KEYS:
        out += [f"# {c}", f"{k}={vals.get(k, '')}"]
    out += ["", "# === Passwords: made by scripts/03-make-passwords.sh where this environment runs, the first time ===",
            "# Leave them empty here. Never change one after the first deploy."]
    out += [f"{k}={vals.get(k, '')}" for k in PASSWORDS]
    return "\n".join(out) + "\n"


def main():
    if not os.path.isfile(SECRETS):
        print(f"No {SECRETS} - this environment folder is incomplete (scripts/apply.sh on the dev box makes it).")
        return 1
    env = read_kv(os.path.join(ENV_DIR, "environment.env")).get("ENVIRONMENT", "?")
    vals = read_kv(SECRETS)
    # A database container already on this server means its volume has passwords from an earlier secrets.env
    # (deploy-all.sh makes the empty volume first, so the volume alone says nothing)
    if not vals.get("STRAPI_DB_PASSWORD") and os.system("docker inspect tbpgdb >/dev/null 2>&1") == 0:
        print("STOP: this secrets.env has no database passwords, but a Timebars database (tbpgdb) already runs on this")
        print("server. New passwords would not match that database. Copy the secrets.env of the folder that made it")
        print("(or your vault copy) here. Only if that data is not needed: the Important note before guide step 7.3.")
        return 1
    made = []
    for k in PASSWORDS:
        if not vals.get(k):
            vals[k] = ",".join(rnd(32) for _ in range(4)) if k == "APP_KEYS" else rnd()
            made.append(k)
    if made:
        # keep the user's layout: rewrite the known lines in place, append any that are missing
        lines = open(SECRETS).read().splitlines()
        done = set()
        for i, line in enumerate(lines):
            m = re.match(r"^\s*([A-Z_][A-Z0-9_]*)\s*=", line)
            if m and m.group(1) in made:
                lines[i] = f"{m.group(1)}={vals[m.group(1)]}"
                done.add(m.group(1))
        lines += [f"{k}={vals[k]}" for k in made if k not in done]
        write_private(SECRETS, "\n".join(lines) + "\n")
        print(f"Made on this machine for {env}: {', '.join(made)}")
    else:
        os.chmod(SECRETS, 0o600)
    for stack, pairs in STACKS.items():
        d = os.path.join(ENV_DIR, stack)
        if os.path.isdir(d):
            text = [f"# {stack}/.secrets.env - written by scripts/make-secrets.py from ../secrets.env. Edit secrets.env, not this."]
            text += [f"{name}={vals.get(src, '')}" for name, src in pairs]
            write_private(os.path.join(d, ".secrets.env"), "\n".join(text) + "\n")
    missing = [k for k, _ in KEYS if not vals.get(k)]
    if missing:
        print(f"Empty keys in secrets.env (those features stay off): {', '.join(missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
