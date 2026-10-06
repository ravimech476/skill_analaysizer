# API image: a static Go binary on a minimal base, running as a non-root user.
# Migrations are embedded in the binary and run at start (AUTO_MIGRATE=true).

FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w -X main.Version=${VERSION}" -o /out/api ./cmd/api \
 && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/migrate ./cmd/migrate

FROM alpine:3.22
# ca-certificates: HTTPS to SMS and push gateways; tzdata: correct local dates on statements and reports.
RUN apk add --no-cache ca-certificates tzdata wget \
 && addgroup -S app && adduser -S -G app -h /app app \
 && mkdir -p /app/storage && chown app:app /app/storage
WORKDIR /app
COPY --from=build /out/api /out/migrate /app/
USER app
ENV APP_ENV=production PORT=8080 FILES_DIR=/app/storage TZ=Asia/Kolkata
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD wget -qO- http://127.0.0.1:8080/health || exit 1
ENTRYPOINT ["/app/api"]
