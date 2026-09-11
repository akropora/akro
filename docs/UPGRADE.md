# Upgrade to Akro V2.2

Persistent Akro data lives in `~/.akro`, so replacing repo code does not remove saved chats, projects, Brain notes, or indexed knowledge.

Before upgrading, back up your local `.env` and repo:

```bash
cd ~
cp -a akro akro-before-v2.2
cp ~/akro/.env ~/.akro-env-backup 2>/dev/null || true
```

Copy the V2.2 files into the existing checkout while preserving `.git` and `.env`:

```bash
rsync -av --delete \
  --exclude='.git/' \
  --exclude='.env' \
  ~/Downloads/akro-v2.2/ \
  ~/akro/
```

Restore `.env` if necessary:

```bash
cp ~/.akro-env-backup ~/akro/.env 2>/dev/null || true
```

Then:

```bash
cd ~/akro
chmod +x chat.sh install.sh lib/remember-worker.sh skills/*/run.sh tests/*.sh
./tests/smoke.sh
```

Add the agent model to `.env`:

```bash
AGENT_MODEL="coral1.6-agent:latest"
```

If you use `AKRO_VISIBLE_MODELS`, you do not need to include the agent model unless you also want it visible as a normal chat model.
