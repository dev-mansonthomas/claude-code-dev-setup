# Security hardening — roadmap & decisions (parked)

Notes on hardening the VM dev environment. Nothing here is implemented yet unless marked ✅.

## The two-layer model (the core idea)

- **Firewall → prevents the *leak*** (of the token **and** of your data).
- **apiKeyHelper / decoy → prevents the *easy capture*** (of the token).

They are complementary. Capture-resistance keeps the token/secrets hard to grab **inside** the
VM; egress control keeps anything that *is* grabbed from **leaving**. For the dominant threat
(automated mass scraper), the **firewall is the higher-leverage control** — a captured token is
worthless if it can't be exfiltrated — while apiKeyHelper/decoy raises the bar on capture.

## Threat being addressed

Automated supply-chain malware (a typosquatted npm/pip dependency, or a prompt-injection)
running inside the VM **as the same user as `claude`**. It tries to (a) read credentials from
the environment / files, and (b) POST them + your source off-box. It targets thousands of
machines, so a captured value that *doesn't work* is a non-event for the attacker — which is
exactly why a decoy / no-usable-token-in-env approach is worthwhile.

## Backlog

### 1. Network egress firewall — prevents leak — NOT IMPLEMENTED
Default-deny nftables in the VM **+** a forced name-allowlisting proxy **+** DNS control **+**
logging. See README → *Network firewall (planned)*. Highest leverage for this threat.

### 2. Token capture-resistance — prevents easy capture — NOT IMPLEMENTED / TO VALIDATE
Today `ccvm` injects `CLAUDE_CODE_OAUTH_TOKEN` into the VM session. A child process that `claude`
spawns may inherit it (undocumented → **assume yes**). Options, best first:

- **`apiKeyHelper`** — Claude fetches the token on demand from a script; **no standard token env
  var** is left for a child to scrape. ⚠️ *Unconfirmed* that `apiKeyHelper` accepts an OAuth
  (setup-token) value vs. API keys only — **validate before adopting**. Precedence:
  `apiKeyHelper` > `CLAUDE_CODE_OAUTH_TOKEN`.
- **Honeytoken / decoy** — put a fake, well-formed `CLAUDE_CODE_OAUTH_TOKEN` in the VM env and
  supply the *real* token via `apiKeyHelper` (higher precedence). A mass scraper grabs the decoy.
- **Immediate, no-risk** — stop passing the token on the `colima ssh` **command line** (argv is
  visible in `ps` / `/proc/<pid>/cmdline` on host **and** VM). Pass it through the environment only.

A stolen OAuth token grants only **Claude quota use** (revocable at the Console) — not host secrets.

## Facts verified (Claude Code v2.x docs)

- `CLAUDE_CODE_OAUTH_TOKEN` via env is **not** written to disk (ephemeral). `setup-token` only prints.
- Linux on-disk creds (interactive `/login`): `~/.claude/.credentials.json`, mode `0600`.
- Auth precedence: Bedrock/Vertex > `ANTHROPIC_AUTH_TOKEN` > `ANTHROPIC_API_KEY` > `apiKeyHelper`
  > `CLAUDE_CODE_OAUTH_TOKEN` > interactive `/login`.
- Subprocess credential scrubbing: **undocumented** → assume the token is inheritable by children.

Sources: code.claude.com/docs → *authentication*, *headless*, *security*.
