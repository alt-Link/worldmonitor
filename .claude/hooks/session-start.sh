#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Installs the dependencies a remote session needs so that typecheck, lint, and
# the unit/sidecar/convex test suites are runnable immediately. Mirrors the
# `npm ci` step shared by .github/workflows/{typecheck,lint-code,test}.yml.
#
# Not run locally: local checkouts manage their own node_modules (see
# `npm run worktree:bootstrap`).
set -euo pipefail

# Remote-only. CLAUDE_CODE_REMOTE is the documented signal; the environment-type
# variable is a fallback so a rename can't silently turn this into a no-op.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] &&
  [ -z "${CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE:-}" ]; then
  exit 0
fi

repo_root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo_root"

# Idempotency stamp. The container is snapshotted after this hook completes, so
# resume/clear/compact firings find node_modules already warm and skip the
# install. Keying on the lockfile hash means a branch that changes dependencies
# still reinstalls. `npm ci` (not `npm install`) so the hook can never mutate
# package-lock.json out from under a commit — audit-lockfile gates every PR.
stamp_file="node_modules/.session-start-stamp"
lock_hash="$(sha256sum package-lock.json | cut -d' ' -f1)"

if [ -f "$stamp_file" ] && [ "$(cat "$stamp_file")" = "$lock_hash" ]; then
  echo "session-start: dependencies already current for package-lock.json ($lock_hash)"
  exit 0
fi

# Root install. The root `postinstall` runs `npm ci --prefer-offline` in
# blog-site/, so the blog workspace is covered here too.
#
# Deliberately not installed: pro-test/ and consumer-prices-core/ own their
# lockfiles and are only needed by `npm run build:pro` / the consumer-prices
# suite, which run their own `npm ci`. Playwright browsers are not fetched
# either — the remote image ships Chromium at $PLAYWRIGHT_BROWSERS_PATH.
echo "session-start: installing dependencies (npm ci)"
npm ci --no-audit --no-fund

printf '%s' "$lock_hash" >"$stamp_file"
echo "session-start: dependencies ready"
