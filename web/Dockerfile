# Web image: builds the React app and serves it with Caddy, which also terminates HTTPS
# (automatic Let's Encrypt certificates) and forwards /api to the API container.

FROM node:22-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# Same origin as the site: the browser calls https://<your-domain>/api/v1, so no CORS is needed.
ARG VITE_API_URL=/api/v1
ENV VITE_API_URL=${VITE_API_URL}
RUN npm run build

FROM caddy:2-alpine
COPY --from=build /src/dist /srv
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 80 443
