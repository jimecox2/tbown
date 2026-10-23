
# git add commit push
acp "message"

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