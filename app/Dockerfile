# Builds the feasy web app into a small Node image that serves it on port 3000
FROM node:22-slim AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
# Mezo testnet unless the build is given mainnet
ARG NEXT_PUBLIC_MEZO_NETWORK=testnet
ENV NEXT_PUBLIC_MEZO_NETWORK=$NEXT_PUBLIC_MEZO_NETWORK
COPY package.json package-lock.json .npmrc ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
COPY --from=build --chown=node:node /app/.next/standalone ./
COPY --from=build --chown=node:node /app/.next/static ./.next/static
COPY --from=build --chown=node:node /app/public ./public
USER node
EXPOSE 3000
CMD ["node", "server.js"]
