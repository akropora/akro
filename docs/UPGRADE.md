# Upgrade to Akro v4

Akro state under `~/.akro/` is outside the repository and is not replaced by this upgrade.

Recommended migration:

```bash
cd ~
cp -a akro akro-before-v4
cp ~/akro/.env ~/.akro-env-backup 2>/dev/null || true
```

Copy the v4 release over the existing checkout while preserving `.git` and `.env`, restore `.env`, then run:

```bash
cd ~/akro
chmod +x chat.sh install.sh lib/remember-worker.sh skills/*/run.sh tests/*.sh
./tests/smoke.sh
./install.sh
```

Recommended `.env` settings:

```bash
AGENT_MODEL="coral1.6-agent:latest"
AGENT_MAX_STEPS=12
AGENT_NUM_CTX=4096
AGENT_NUM_PREDICT=300
AGENT_CONTROLLER_NUM_CTX=8192
AGENT_CONTROLLER_NUM_PREDICT=900
```
