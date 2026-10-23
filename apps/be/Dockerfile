FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY server.js index.js migrate.js errors.js .env.example ./
COPY features ./features
# Migrations ship in the image, so the deploy can run `node migrate.js` from the image it deploys.
COPY migrations ./migrations
# The commit is baked in, so the image always knows what code it holds. The version is set by the
# deploy, since one image serves an rc and its prod release.
# SSM_PATH names the Parameter Store path the server reads its settings from at boot.
ARG GIT_SHA=unknown
ARG BUILT_AT=unknown
ENV GIT_SHA=$GIT_SHA BUILT_AT=$BUILT_AT
LABEL org.opencontainers.image.revision=$GIT_SHA org.opencontainers.image.created=$BUILT_AT
ENV PORT=3000
EXPOSE 3000
CMD ["node", "index.js"]
