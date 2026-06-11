# Isolated by default — the Colima VM

Everything runs inside an **always-on Colima Linux VM**: Claude Code, your tools, Docker
(testcontainers), and the Grafana monitoring stack. You **edit on the host** (VS Code,
Finder) — `~/Projects` is mounted into the VM — and **Claude + builds + tests run in the
VM**. The VM is the security boundary: a compromised dependency or agent action is confined
to the VM (it can touch the mounted `~/Projects`, but **not** `~/.ssh`, your keychain, or the
rest of macOS).

## One-time setup
```bash
./vm-up.sh            # or: make vm-up
```
It (idempotently):
- installs `colima` + `docker` (Homebrew) if missing;
- starts Colima with **`vz` + `virtiofs`**, **`~/Projects` mounted writable**, Docker on;
- sizes the VM by host RAM: **8 GB** (≤24 GB Mac) or **12 GB** (more) — `--cpu 4/6 --disk 60`;
- **provisions the VM** (`scripts/vm-provision.sh`): Claude Code, git/jq/gitleaks/uv, the
  kit's skills + global config (reused from the mounted kit), `claude-monitor`, and clones
  `claude-code-otel`;
- links **`cc`** onto your PATH and installs a **LaunchAgent** so the VM **auto-starts at login**.

First time only, log in to Claude **inside the VM**: `cc` then run `claude` once
(or on the host `claude setup-token`, then `export CLAUDE_CODE_OAUTH_TOKEN=…` in the VM).

## Daily workflow
```bash
cc <project>     # opens VS Code on the host + a Claude session INSIDE the VM
cc               # just shell into the VM (at ~/Projects)
```
`new-project.sh <name>` scaffolds under `~/Projects` then **auto-launches `cc`** (VS Code +
Claude in the VM). Edit in VS Code on your Mac; the VM sees the changes instantly.

Because the VM is the boundary, you can run Claude with **`--dangerously-skip-permissions`**
inside it for fully unattended work, with much less risk than on the host.

## Monitoring (Grafana) lives in the VM
No second VM — the OTEL/Grafana stack runs in the same Colima VM:
```bash
cc                                   # into the VM
cd ~/claude-code-otel && make up     # start collector + Prometheus + Grafana
```
Open **http://localhost:3000** on your Mac (admin/admin) — Lima forwards the VM's local
ports to the host. Claude's telemetry (`settings.json` → `localhost:4317`) reaches the
collector in the VM automatically.

## Performance & caveats
- **Mounts are slower than native disk for many small files.** Keep caches/deps on the VM's
  native disk via the per-project `env` (`.uv-cache`, `npm_config_cache`, `GRADLE_USER_HOME`…
  — see the README recipes), not on the mounted source.
- **The writable mount is a scoped hole:** the VM can write `~/Projects`. Keep secrets out of
  the VM and rely on the firewall/host separation for everything else.
- **Resources:** the VM holds 8–12 GB while running. Stop it with `colima stop` if needed.
- **Two environments:** the VM has its own `~/.claude`. The kit's config is symlinked from the
  **mounted** repo, so editing the kit on the host updates the VM too; re-run
  `bash <kit>/scripts/20-skills.sh` in the VM to refresh skills.

## Isolation spectrum
| Level | Isolation | Notes |
|---|---|---|
| OS sandbox (Seatbelt) | per-command | lightweight; blocks net/Docker → friction for installs/integration |
| Devcontainer | namespaces + firewall | shares the host kernel; good middle ground |
| **Colima VM (this)** | **full kernel** | strongest; Docker native; always-on; the default here |

## Undo
```bash
colima stop                                   # stop the VM
launchctl unload ~/Library/LaunchAgents/com.$USER.colima.plist   # stop auto-start
rm ~/Library/LaunchAgents/com.$USER.colima.plist
colima delete                                 # remove the VM entirely
```
