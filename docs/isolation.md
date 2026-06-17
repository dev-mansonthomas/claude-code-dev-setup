# Isolated by default — the Colima VM

Everything runs inside an **always-on Colima Linux VM**: Claude Code, your tools, Docker
(testcontainers), and the Grafana monitoring stack. You **edit on the host** (VS Code,
Finder) — `~/Projects` is mounted into the VM — and **Claude + builds + tests run in the
VM**. The VM is the security boundary: a compromised dependency or agent action is confined
to the VM (it can touch the mounted `~/Projects`, but **not** `~/.ssh`, your keychain, or the
rest of macOS).

## One-time setup
```bash
./03-vm-up.sh            # or: make vm-up
```
It (idempotently):
- installs `colima` + `docker` (Homebrew) if missing;
- starts Colima with **`vz` + `virtiofs`**, **`~/Projects` mounted writable**, Docker on;
- sizes the VM by host RAM: **8 GB** (≤24 GB Mac) or **12 GB** (more) — `--cpu 4/6 --disk 60`;
- **provisions the VM** (`scripts/vm-provision.sh`): Claude Code, git/jq/gitleaks/uv, the
  kit's skills + global config (reused from the mounted kit), `claude-monitor`, and clones
  `claude-code-otel`;
- links **`ccvm`** onto your PATH and installs a **LaunchAgent** so the VM **auto-starts at login**.

First time only, **authenticate the VM** — Claude in the VM has no browser, so use a long-lived
token generated on the host (needs a Claude Pro/Max/Team/Enterprise subscription):
```bash
./04-vm-auth.sh    # runs `claude setup-token`, then stores the token host-side (chmod 600)
```
`ccvm` injects it into every VM session — the token never lands in the VM image or under `~/Projects`,
so it can't be committed. Rotate by re-running `claude setup-token`; revoke at the Claude Console.
(Simpler, less safe: `export CLAUDE_CODE_OAUTH_TOKEN=…` in the VM's `~/.profile`, or just run
`claude` once inside the VM and finish the interactive login.)

## Daily workflow
```bash
ccvm <project>     # opens VS Code on the host + a Claude session INSIDE the VM
ccvm               # just shell into the VM (at ~/Projects)
```
`05-new-project.sh <name>` scaffolds under `~/Projects` then **auto-launches `ccvm`** (VS Code +
Claude in the VM). Edit in VS Code on your Mac; the VM sees the changes instantly.

## Host vs VM settings — opposite postures by design
The host and the VM **must not share** one `settings.json` — they want opposite security postures:

| | Sandbox | Permissions | Why |
|---|---|---|---|
| **Host** (symlinked `settings.json`) | **on** (Seatbelt) | `acceptEdits` + allow-list | the host is the sensitive environment — lock it down |
| **VM** (`settings.json` real file) | **off** | `bypassPermissions` (max autonomy) | the VM **is** the boundary — let Claude run unattended |

The VM posture lives in [`claude-config/settings.vm.json`](../claude-config/settings.vm.json) (just the
deltas: `sandbox.enabled=false`, `permissions.defaultMode=bypassPermissions`). `03-vm-up.sh` merges it
over the base and writes a **real** `~/.claude/settings.json` in the VM, **regenerated every run** so it
stays in sync with the kit; the host keeps the symlinked, sandboxed profile. So Claude runs unattended in
the VM without per-command prompts — far lower risk than doing that on the host.

> The VM provisions `bubblewrap` + `socat` so Claude's sandbox *capability* check passes (clean `/doctor`),
> while `sandbox.enabled=false` keeps the sandbox itself **unused** — so zero friction and no nag.

## Monitoring (Grafana) lives in the VM
No second VM — the OTEL/Grafana stack runs in the same Colima VM:
```bash
ccvm                                   # into the VM
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
  the VM and rely on host separation for everything else.
- **Outbound network is currently unrestricted** — the VM can reach the whole internet, so a
  compromised dep could exfiltrate what it reads. An egress allowlist is planned; see the
  README's *Network firewall* section. Until then, treat VM egress as open.
- **Resources:** the VM holds 8–12 GB while running. Stop it with `colima stop` if needed.
- **Two environments:** the VM has its own `~/.claude`. The kit's config is symlinked from the
  **mounted** repo, so editing the kit on the host updates the VM too; re-run
  `bash <kit>/scripts/20-skills.sh` in the VM to refresh skills.

## Trim the host to VM-only (optional)
Once everything runs in the VM, the **host** copies of the monitoring stack are redundant — and
because the `docker` CLI now talks to the Colima daemon, starting them from the host competes with
the VM's stack for ports 3000/4317. **Keep `claude` on the host** (you need it for `claude
setup-token`); drop the rest:
```bash
./grafana-down.sh 2>/dev/null || true     # stop any host-launched dashboards
rm -rf ~/Tools/claude-code-otel           # host OTEL clone — the VM has its own at ~/claude-code-otel
uv tool uninstall claude-monitor 2>/dev/null || true   # optional — monitoring lives in the VM now
brew uninstall claude-squad 2>/dev/null || true        # optional — removes the 'cs' alias too
```
A later `./01-setup.sh` re-run would reinstall these; pass `--no-extras` to keep the host lean. The
host's `~/.claude` config (skills, MCP, settings) is harmless to keep — it's just unused while you
work in the VM.

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
