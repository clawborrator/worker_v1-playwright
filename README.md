# worker_v1-playwright

Extension of [`ladder99/clawborrator-worker`](https://hub.docker.com/r/ladder99/clawborrator-worker)
with Playwright + Chromium pre-installed. Use this image when an
agent needs to drive a real browser — scraping behind-login
surfaces, automating sites without an API, or end-to-end testing
of web UIs.

## Image

Published to Docker Hub as:

```
ladder99/clawborrator-worker-playwright:latest
```

## Build + push

```bash
docker build -t ladder99/clawborrator-worker-playwright:latest .
docker push  ladder99/clawborrator-worker-playwright:latest
```

The build adds ~500MB over the base (Chromium + system deps).

## What's added vs. the base

- `playwright` npm package, globally installed (`require('playwright')`
  works from any cwd)
- Chromium browser binary at `/usr/local/share/playwright/`
- All system libs Chromium-headless needs (libnss3, libxkbcommon0,
  fonts-liberation, etc. — installed via `playwright install
  --with-deps chromium`)
- `PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright` baked in

## Typical mount points

When using this image, you'll usually want:

- `/var/run/docker.sock` — only if the agent will spawn sibling
  workers (same as base image)
- `/secrets/<site>.cookies.json` — read-only host mount, so the
  Playwright scripts can skip the login flow each run via
  `await context.addCookies(cookies)`

## Cookie format

Use the JSON shape Playwright's `addCookies()` accepts. The
easiest way to capture one is to log in via your real browser,
open DevTools → Application → Cookies, and export. Several
browser extensions (e.g. "Cookie-Editor", "EditThisCookie") let
you copy as Playwright-formatted JSON in one click.

Example:

```json
[
  {
    "name": "reddit_session",
    "value": "abc123…",
    "domain": ".reddit.com",
    "path": "/",
    "httpOnly": true,
    "secure": true,
    "expires": 1799999999
  },
  …
]
```

## Concrete consumer

See `../worker_v1-example-reddit-engager-{worker,repo}/` for a
complete end-to-end deployment that uses this image to drive
autonomous Reddit engagement.

## Caveats

- **Chromium has a fingerprint.** Headless mode + Playwright leaves
  detectable traces (CDP artifacts, navigator properties,
  viewport patterns). Sites with active anti-bot stacks WILL
  flag automated sessions over time. For sticky sessions look at
  `playwright-extra` + `puppeteer-extra-plugin-stealth`, but it's
  cat-and-mouse — design for cookie expiration as a routine event,
  not an exceptional one.
- **One Chromium per container.** Each spawned container launches
  its own browser. Don't try to multiplex many tasks through one
  Playwright instance unless the tasks are read-only and you've
  reasoned through the contention.
- **`--shm-size`** Chromium uses /dev/shm aggressively; if you see
  tab crashes ("Page crashed!" or "Out of memory") add
  `shm_size: 2gb` to the service in docker-compose. The base
  image's compose example for the engager already does this.
