# syntax=docker/dockerfile:1
#
# worker_v1-playwright — clawborrator-worker + Playwright + Chromium.
#
# Extension of the base worker image with browser-automation
# capability. Used by agents that need to drive a real browser:
# scrape behind-login surfaces, automate sites that don't have
# an API, or test web UIs end-to-end. The Reddit engager
# (worker_v1-example-reddit-engager-{worker,repo}) is the
# canonical consumer.
#
# Browser binaries are installed to a system-wide location
# readable by the non-root `worker` user, so the runtime doesn't
# have to re-download Chromium on each container boot.
#
# Image size penalty over the base: ~500MB (Chromium + deps).
# Build + push:
#   docker build -t ladder99/clawborrator-worker-playwright:latest .
#   docker push ladder99/clawborrator-worker-playwright:latest

FROM ladder99/clawborrator-worker:latest

# Chromium needs a pile of system libs that aren't in the slim
# base. playwright's `--with-deps` installs them; we run as root
# during build (`USER 0` resets the worker-uid set by the base
# image's runtime) so apt-get can write to /var/lib/dpkg.
USER 0

# System-wide browser cache. Both the build-time `playwright
# install` and the runtime `require('playwright')` look at this
# env var, so setting it here makes the install land where the
# worker user can read it without per-user re-download.
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright

# CRITICAL — without this, `require('playwright')` from any
# script outside /usr/local/lib/node_modules fails with "Cannot
# find module 'playwright'". `npm install -g` puts the package
# at /usr/local/lib/node_modules but Node.js does NOT search
# global node_modules during require() resolution unless NODE_PATH
# explicitly names it. (Pre-0.1.1 of this image omitted this and
# every consumer hit the missing-module error on first run.)
ENV NODE_PATH=/usr/local/lib/node_modules

# Install playwright globally so `node` invocations from any
# working directory can `require('playwright')` without a per-
# repo npm install. Also install playwright-extra, the
# puppeteer-extra runtime that the stealth plugin uses for its
# plugin discovery (works with playwright-extra too), the
# stealth plugin itself, AND user-preferences which stealth
# loads dynamically. Stealth's plugin loader expects user-
# preferences as a SIBLING in node_modules, not nested inside
# its own folder, so we install it explicitly at the top level.
# (Pre-0.1.3 of this image omitted puppeteer-extra and user-
# preferences as siblings and the stealth import errored at
# runtime with "user-preferences could not be found".)
ARG PLAYWRIGHT_VERSION=1.49.0
RUN npm install -g \
        playwright@${PLAYWRIGHT_VERSION} \
        playwright-extra \
        puppeteer-extra \
        puppeteer-extra-plugin-stealth \
        puppeteer-extra-plugin-user-preferences

# Xvfb. Lets agents run Chromium with `headless: false` under a
# virtual display, which removes the most obvious "I'm headless"
# fingerprint signal that sites like LinkedIn check. xauth is
# required by xvfb-run (the convenience wrapper agents use as
# `xvfb-run -a node ...`); without xauth, xvfb-run errors with
# "xauth command not found". (Pre-0.1.3 of this image shipped
# xvfb without xauth and the prefix failed immediately.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        xvfb \
        xauth && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /tmp/.X11-unix && \
    chmod 1777 /tmp/.X11-unix

# Pull down Chromium + matching system deps. `--with-deps` runs
# apt-get under the hood for the missing shared libs Chromium
# headless needs (libnss3, libxkbcommon0, libatk-bridge2.0-0,
# fonts-liberation, etc.). Chromium-only — Firefox and WebKit are
# ~300MB extra and we don't need them for the engager use case.
RUN npx --yes playwright install --with-deps chromium && \
    chmod -R a+rX ${PLAYWRIGHT_BROWSERS_PATH}

# Hand control back to the base image's worker uid (set in
# worker_v1/Dockerfile via the runtime entrypoint, not via
# Dockerfile USER directive — the entrypoint starts as root,
# chowns /workspace, then drops to `worker` via gosu). No USER
# directive here would also work, but being explicit avoids
# surprises if the base ever changes.
USER 0

# Document the additional env contract this image adds on top
# of the base worker_v1 contract (see worker_v1/README.md for
# the full list of envs the base honors):
#
#   PLAYWRIGHT_BROWSERS_PATH  pre-set to /usr/local/share/playwright;
#                             don't override unless you know what you're doing
#
# Mount points typical for this image:
#
#   /secrets/<site>.cookies.json  read-only, mounted from host;
#                                 the scripts that drive Playwright
#                                 load these via context.addCookies()
#                                 to skip the login flow on every run.
#
# Entry / runtime is inherited from the base — no override needed.
