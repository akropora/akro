# Upgrading to Akro V2.1

Akro's persistent data lives in `~/.akro`, outside the repository. Replacing the repository does not remove projects, chats, Brain notes, or indexed knowledge.

The one local repository file you should preserve is `.env`.

## Safe upgrade

From your home directory, assuming the downloaded folder is `~/Downloads/akro-v2.1` and the current repo is `~/akro`:

```bash
cp ~/akro/.env ~/akro.env.backup 2>/dev/null || true
mv ~/akro ~/akro-old
mv ~/Downloads/akro-v2.1 ~/akro
cp ~/akro.env.backup ~/akro/.env 2>/dev/null || true
cd ~/akro
chmod +x chat.sh install.sh lib/remember-worker.sh skills/*/run.sh tests/*.sh
./tests/smoke.sh
```

After Akro starts correctly, reconnect or preserve the Git repository as appropriate before pushing. Do not delete `~/akro-old` until you have verified V2.1.

## Remove the old local model-picker workaround

V2.1 officially supports `AKRO_VISIBLE_MODELS`, so `lib/commands.sh` no longer needs a local-only patch.

If the old repository used `skip-worktree`, clear it before comparing or migrating Git state:

```bash
git update-index --no-skip-worktree lib/commands.sh 2>/dev/null || true
```

Put your allowlist in `.env`:

```bash
AKRO_VISIBLE_MODELS="coral1.6:latest,coral1.6-worker:latest,coral1.6-coder:latest"
```

Leave it empty or unset to show all installed Ollama models.

## Build Coral 1.6 Prompt

```bash
cd ~/akro
ollama create coral1.6-prompt -f models/Modelfile.coral1.6-prompt
```

Test it:

```bash
ollama run coral1.6-prompt
```

Then `/promptup` can use it automatically.
