# {{PROJECT_NAME}}

> One-line description of what this project does.

This README assumes **no prior knowledge** of the project. Follow it top to
bottom and you'll have it running.

## What you need first (prerequisites)

| Tool | Why | Check |
|------|-----|-------|
| Git | get the code | `git --version` |
| Node.js (LTS) | run the app | `node --version` |
| Docker (optional) | local Redis/services | `docker --version` |

> Don't have these? See the team's "Mac OS Setup" guide, or install Node via
> `nvm install --lts`.

## 1. Get the code
```bash
git clone <REPO_URL>
cd {{PROJECT_NAME}}
```

> **Enable the secret-scan hook** (one-time, after cloning):
> ```bash
> git config core.hooksPath .githooks
> ```
> A local pre-commit hook (gitleaks) then blocks any commit that contains a secret.
> Needs gitleaks (`brew install gitleaks`); CI re-checks on push regardless.

## 2. Configure
```bash
cp .env.example .env   # then open .env and fill in the values (see comments inside)
```
Never commit `.env` — it's already in `.gitignore`.

## 3. Install dependencies
```bash
npm install            # or: pnpm install
```

## 4. Run it
```bash
npm run dev            # starts the app; open the URL it prints
```
**Success looks like:** TODO (e.g., "the page loads at http://localhost:3000").

## 5. Run the tests
```bash
npm test
```
All tests should pass (green).

## Troubleshooting
- **`command not found: node`** → install Node (`nvm install --lts`) and open a
  new terminal.
- **Port already in use** → stop the other process or set `PORT=...` in `.env`.
- **Redis connection refused** → start it: `docker run -d -p 6379:6379 redis:latest`.

## Project docs
- Humans: this README.
- Agents/contributors: [`docs/`](docs/) — product brief, feature specs,
  architecture, and decision records.

## License
TODO
