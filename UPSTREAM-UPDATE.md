# Upstream and container update plan

This installation carries local security changes on top of
`torikushiii/hoyolab-auto`. Keep those changes on a dedicated branch and never
commit `config.json5`, `data/`, or `logs/`.

## 1. Prepare and back up

1. Stop the running container so two instances cannot check in at once.
2. Back up `config.json5` and `data/` outside the Git working tree while
   preserving their permissions.
3. Record the currently deployed image tag or digest for rollback.
4. Confirm the working tree contains only understood local changes.

## 2. Review upstream before merging

```sh
git fetch origin --prune --tags
git log --oneline --decorate HEAD..origin/main
git diff --stat HEAD..origin/main
git diff HEAD..origin/main -- package.json Dockerfile docker-compose.yml
```

Read release notes and inspect changes that touch authentication, cookies,
outbound URLs, lifecycle scripts, Docker configuration, or dependencies. Do
not merge an upstream update directly into a running deployment.

Merge the reviewed upstream commit into the local container-hardening branch.
If upstream changed its Dockerfile, preserve the new upstream version in
`Dockerfile.upstream`, then reapply the intentional hardening in `Dockerfile`.

## 3. Reconcile and verify dependencies

First try the existing reviewed lockfile:

```sh
npm ci --omit=dev --ignore-scripts
npm audit signatures
npm audit --omit=dev --audit-level=high
```

If upstream changed `package.json` and `npm ci` reports that the lockfile is no
longer compatible, generate a candidate lockfile without running lifecycle
scripts:

```sh
npm install --package-lock-only --ignore-scripts
git diff -- package.json package-lock.json
npm ci --omit=dev --ignore-scripts
npm audit signatures
npm audit --omit=dev --audit-level=high
```

Review every direct dependency change and unexpected transitive addition. Do
not use `npm audit fix --force` as a substitute for review.

## 4. Refresh the Node base deliberately

Use a supported Node LTS patch release and an explicit Alpine release. Resolve
the official multi-platform digest with:

```sh
docker buildx imagetools inspect node:<node-version>-alpine<alpine-version>
```

Update both the readable tag and `sha256:` digest in the Dockerfile. A digest
change is expected only when intentionally refreshing the base image.

## 5. Build and validate

The Portainer Compose service has `build.context` pointing at this repository.
Build without reusing dependency or base-image layers:

```sh
docker compose -f docker-compose.portainer.yml build --pull --no-cache instance
```

Before deployment, verify that credentials were excluded and that the image
runs as the unprivileged Node user:

```sh
docker run --rm --entrypoint sh hoyolab-auto:local -c \
  'test ! -e /app/config.json5 && test "$(id -u)" = 1000'
```

Review the resolved stack definition without printing or embedding secrets:

```sh
docker compose -f docker-compose.portainer.yml config
```

## 6. Deploy and observe

1. Tag the image with the reviewed upstream commit or release, not only
   `latest`.
2. Deploy that immutable tag or digest through Portainer.
3. Mount `config.json5` read-only and mount only `data/` and `logs/` writable.
4. Confirm the container timezone is `Europe/London`, the expected cron count
   is logged, and only one application instance is running.
5. Observe the first check-in and code-redemption cycles before removing the
   previous image.

## 7. Roll back

If startup, authentication, or scheduled work regresses, stop the new
container and redeploy the previously recorded image tag or digest. Restore the
configuration/data backup only if the new version changed their format.
