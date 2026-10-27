
##### Next time you deploy a new blog tag:

On lser: bash scripts/apply.sh, then bash envs/PROD/00-push-to-server.sh gmk1 ~/docker. You only need these if you changed tbapps.conf or pulled tbown.
On gmk1: cd ~/docker/tbApps && ./deploy-all.sh, then type the new tag at tbblog and press Enter for the others. Or just cd ~/docker/tbApps/tbblog && ./deploy.sh.


# NEW Redeploy STAGING and PROD with the blog (deploy-all shortcut)

You're deploying over existing installs, and the blog already runs by hand on both servers. Nothing gets lost:
the push never overwrites the server's `secrets.env`, `.env` tags or `tbblog/uploads`, and the first
`deploy-all.sh` copies the blog's secrets from `tbblog/strapi.env.local` and `web.env.local` into `secrets.env`.
The proxy and cloudflared are not touched; `deploy-all.sh` no longer starts the proxy.

## 1. STAGING on lser (tbown repo and package on the same box, no ssh)

In the tbown repo on lser:

```bash
git checkout main && git pull origin main                 # after you merge PR #11
nano tbapps.conf
#   [STAGING] add:  BLOG_HOST=blogs.agile-pm-rm-ppm.com
#                   BLOG_ADMIN_HOST=strapis.agile-pm-rm-ppm.com
#   [PROD]    add:  BLOG_HOST=blog.agile-pm-rm-ppm.com
#                   BLOG_ADMIN_HOST=strapi.agile-pm-rm-ppm.com
mkdir -p archives && mv envs archives/envs-2026-10-26     # archives/ is git-ignored
bash scripts/apply.sh --check                             # no FIX lines
bash scripts/apply.sh                                     # new envs/STAGING, envs/PROD ...
```

Safety copy of the blog first (the old backup script doesn't include it):

```bash
bash $TB/scripts/05-backup.sh
docker exec tbpgdb pg_dump -U tbblog -d tbblog -Fc > ~/tbblog-before.dump
cp $TB/tbblog/strapi.env.local $TB/tbblog/web.env.local ~/ && chmod 600 ~/*.env.local
```

Push and deploy:

```bash
bash envs/STAGING/00-push-to-server.sh local /docker/compose
source ~/.bashrc
cd $TB && ./deploy-all.sh
```

In the output, check for the line *"Taken back into secrets.env ... (or a blog installed by hand): TBBLOG_..."*
and *"Database tbblog on tbpgdb accepts tbblog."* Then run `bash $TB/scripts/07-check-urls.sh`.

## 2. PROD on gmk1, over ssh

First, on gmk1, check that `echo $TB` prints the folder that holds the blog (`~/docker/tbApps`, so the blog is `$TB/tbblog`).
If the blog is somewhere else, tell me before you push.

In the tbown repo on lser:

```bash
bash envs/PROD/00-push-to-server.sh gmk1 ~/docker
```

In a gmk1 terminal (`ssh gmk1`):

```bash
bash $TB/scripts/05-backup.sh
docker exec tbpgdb pg_dump -U tbblog -d tbblog -Fc > ~/tbblog-before.dump
cd $TB && ./deploy-all.sh
bash $TB/scripts/07-check-urls.sh
```

Note: the blog's "Visit Timebars Ltd." link now goes to that environment's website (staging: wwws.timebars.com).



// end 

# git add commit push
acp "miscl"

This repo is for easing the docker container deployment and variables and secrets.
Remember there are two ways to make changes and push them out.
1. Inside the repo make changes, update envs folders and push to server, run commands again from server.
2. Instead go to the server package you deployed and change the secrets.env file and redeploy.

# Easy way to deploy new strapi token - this is no 2 above.

You only change one file: the `STRAPI_ADMIN_TOKEN=` line in `$TB/secrets.env`. Do this on prod:

**1. Put the token in:**
```
nano $TB/secrets.env
```
Make the line read `STRAPI_ADMIN_TOKEN=<new token>`, all on one line, with no spaces or quotes.

**2. Check the token with Strapi** (`200` means good, `401` means the token itself is wrong):
```
T=$(grep '^STRAPI_ADMIN_TOKEN=' $TB/secrets.env | cut -d= -f2-); curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" 'https://be2.timebars.com/api/help-articles?pagination[pageSize]=1'
```

**3. Copy it to the apps and restart them.** This keeps the tags you just set: `up -d` reads each folder's `.env`, and it doesn't pull.
```
bash $TB/scripts/03-make-passwords.sh
cd $TB/tbhelp && docker compose up -d --force-recreate
cd $TB/tbwww && docker compose up -d --force-recreate
```

**4. Confirm Cloud has it.** This should print `set`:
```
docker exec tbhelpapp sh -c 'test -n "$STRAPI_ADMIN_TOKEN" && echo set || echo empty'
```

If step 2 gives `401`, make the token in prod Strapi (`be2.timebars.com/admin`), not staging, as Full access. If step 4 says `empty`, send me the output of `grep -c '^STRAPI_ADMIN_TOKEN=.' $TB/tbhelp/.secrets.env`.


# Merge multi brancjes repos into main
B=claude/project-thread-5l1i26; for r in helpappGitHub tbwwwGithubApr20 tbrunpGitHubMar27 tbown; do echo "== $r"; (cd "$r" && git checkout main && git pull origin main && git fetch origin "$B" && git merge --no-edit "origin/$B" && git push origin main && git push origin --delete "$B" && { git branch -D "$B" 2>/dev/null; true; }) || { echo "Stopped at $r"; break; }; done