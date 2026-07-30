#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Installs the dependencies a remote session needs to run typecheck, lint, and
# the unit/sidecar/convex test suites. Mirrors the `npm ci` step shared by
# .github/workflows/{typecheck,lint-code,test}.yml.
#
# Runs async on a cold container (see below), so a fresh session is usable
# before the install finishes.
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

# Cold container: hand the session back immediately and install in the
# background. Declared here rather than at the top of the file so it only
# applies to this path — the warm path above already returns in ~10ms, where
# going async would add machinery and buy nothing.
#
# Trade-off: the session is usable before node_modules exists, so a command run
# in the first ~1-2 minutes can fail on missing deps. Re-running it once the
# install lands is the fix. The timeout is ~8x the observed cold install so a
# slow registry doesn't get killed mid-flight.
echo '{"async": true, "asyncTimeout": 600000}'

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
