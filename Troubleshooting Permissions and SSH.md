# Two SSH "Permission denied" puzzles from a container deployment rehearsal, and what fixed them

While rehearsing a new deployment of the Timebars suite (Docker containers, one environment per server, packages generated on a dev box), I hit two SSH problems back to back. Neither was a bug in the servers. Both came from how SSH decides who you are. Here is what happened and how each was fixed.

## The setup

The dev box (`lser`) holds the `tbown` repo in VS Code. Running `apply` there turns one settings file, `tbapps.conf`, into one package per environment (`envs/DEV`, `envs/PROD` ...). A script, `00-push-to-server.sh`, copies a package to its server over SSH and rsync. On the server, numbered scripts start the containers.

The plan said every environment gets its own server. In practice I wanted DEV on the dev box itself, the box with tbown repo installed.

## Problem 1: pushing to my own machine asked for a password

I ran the push with the dev box as the target:

```bash
bash envs/DEV/00-push-to-server.sh lser /docker/compose
```

and SSH asked for a password.

**Why:** the script reaches the target over SSH, even when the target is the machine you are sitting at. `ssh lser` from lser is a normal SSH login to yourself, and it only works with a key if your own public key is in your own `~/.ssh/authorized_keys`. Mine wasn't, so SSH fell back to asking for a password.

**The fix:** SSH isn't needed to copy files onto the same machine. The push script got a `local` mode that copies directly, with no SSH at all. From /tbown repo in vscode terminal:

```bash
bash envs/DEV/00-push-to-server.sh local /docker/compose
source ~/.bashrc          # picks up $TB, which the script sets
echo $TB                  # must print out the full path to the repo: e.g. ~/Sites/tbown  
```

From there, the normal server steps run on the dev box (`sudo bash $TB/scripts/01-install-docker.sh` and so on, or `cd $TB && ./deploy-all.sh` after `docker login`).


## Problem 2: a freshly prepped box refused my key

Scenario: brand new box, prepared with our `00-prep-new-server.sh`:

```text
jcox@lser:~$ ssh tbdovm2
jcox@137.184.174.240: Permission denied (publickey).
```

**Why:** the prep script does what it promises. It creates the admin user `jcox` and then turns password logins off. The box had been created with a key from a different machine, not lser's `~/.ssh/id_ed25519`. So lser's key was never on the server, and with passwords off, SSH had nothing else to try.

**How to confirm it:** compare lser's public key with the one on the target box.
```bash
# on lser get the public key
cat ~/.ssh/id_ed25519.pub
# lser public key line: ssh-xxx xyxyxyxyxyxyyxyxyxyxyxyxyxyyx jcox@lser
```

**The fix:** add lser's public key to the admin user's `authorized_keys`. From the machine that can still log in. If cloud VM, use the web console:

```bash
# from web console or console on the physical server
ssh jcox@<server IP> 'echo "<lser public key line>" >> ~/.ssh/authorized_keys'
```

Note that `ssh-copy-id` no longer helps at this point: it needs a password login to install the key, and the prep script turned password logins off.

**For the next server:** give it the right key from the start. Add the dev box's key to DigitalOcean when you create the droplet, or hand it to the prep script:

```bash
ssh -t root@<server IP> bash 00-prep-new-server.sh jcox --web --key "$(cat ~/.ssh/id_ed25519.pub)"
```

## The lesson

Both errors had the same root: SSH with keys only works when the *right* public key is on the *receiving* side, and that includes the case where the receiving side is your own machine. When you see `Permission denied (publickey)` or an unexpected password prompt, ask two questions first:

1. Which machine am I connecting **from**, and what is its public key (`cat ~/.ssh/id_ed25519.pub`)?
2. Is that exact key in `~/.ssh/authorized_keys` of the user I'm logging in **as**, on the machine I'm connecting **to**?

And when you don't need SSH at all, as with a deployment to the same box, skip it.

# Additional Assistance for Rookies

## Send Your dev box key, before anything is locked

Every server must hold the public key of the dev box you push from, and it must get there **before** password logins are turned off, because after that `ssh-copy-id` no longer works and the server answers `Permission denied (publickey)`. Make sure the dev box has a key, then use the way that fits the server. Give each server an SSH shortcut on the dev box, so `ssh <server>` and the push script use the right user and key.

```bash
# on the dev box: make a key if there is none, and show it
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "$USER@$(hostname)"
cat ~/.ssh/id_ed25519.pub
```

**A new cloud server (you run the prep script):** hand the key to the prep script with `--key`; it installs it for the admin user before it turns passwords off. This works even when the droplet was created with a key from another machine.

```bash
scp scripts/00-prep-new-server.sh root@<server IP>:
ssh -t root@<server IP> bash 00-prep-new-server.sh <admin user> --web --key "$(cat ~/.ssh/id_ed25519.pub)"
```

**A server from your admin (password login still on):** copy the key once; it asks the admin user's password one last time.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub <admin user>@<server IP>
```

**The SSH shortcut** (once per server, on the dev box):

```bash
cat >> ~/.ssh/config <<'CFG'

Host prod1
    HostName <server IP>
    User <admin user>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
CFG
chmod 600 ~/.ssh/config
ssh prod1 'hostname; sudo -v && echo sudo ok'     # no password for SSH; sudo asks the admin password
```

Every entry needs its own `Host` line. `IdentitiesOnly yes` matters: without it SSH offers every key you have, and the server may block your address after several failed tries (*Connection reset by peer*). If `ssh prod1` still says `Permission denied (publickey)`, the dev box key is not on the server: add it from the DigitalOcean web console as root with `echo "<the cat ~/.ssh/id_ed25519.pub line>" >> /home/<admin user>/.ssh/authorized_keys`.