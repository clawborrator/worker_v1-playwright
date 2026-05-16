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

# Install playwright globally so `node` invocations from any
# working directory can `require('playwright')` without a per-
# repo npm install. Pinned to a known-good major; bump explicitly.
ARG PLAYWRIGHT_VERSION=1.49.0
RUN npm install -g playwright@${PLAYWRIGHT_VERSION}

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
