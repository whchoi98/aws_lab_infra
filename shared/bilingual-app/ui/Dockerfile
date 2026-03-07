FROM node:20-alpine AS builder
WORKDIR /app
COPY src/package*.json ./
RUN npm install --production

FROM node:20-alpine
RUN apk add --no-cache tini
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY src/ .
USER node
EXPOSE 8080
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
