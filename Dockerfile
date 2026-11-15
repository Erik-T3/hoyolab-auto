FROM node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS dependencies

ENV NODE_ENV=production

WORKDIR /app

RUN chown node:node /app
USER node

# Install exactly the reviewed dependency tree. The project-level .npmrc and
# explicit flag both prevent dependency lifecycle scripts from executing.
COPY --chown=node:node package.json package-lock.json .npmrc ./
RUN npm ci --omit=dev --ignore-scripts && \
    npm audit signatures && \
    npm audit --omit=dev --audit-level=high && \
    npm cache clean --force


FROM node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS runtime

ENV NODE_ENV=production \
    TZ=Europe/London

WORKDIR /app

# Apply Alpine security updates and install named timezone data. npm and npx
# are build tools and are removed from the final runtime attack surface.
RUN apk upgrade --no-cache && \
    apk add --no-cache tzdata && \
    rm -rf /usr/local/lib/node_modules/npm \
           /usr/local/bin/npm \
           /usr/local/bin/npx

# The official Node image provides an unprivileged node user (UID/GID 1000).
RUN chown node:node /app
USER node

COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node . .

RUN mkdir -p /app/data /app/logs

CMD ["node", "index.js"]
