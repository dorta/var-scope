# syntax=docker/dockerfile:1.7
FROM golang:1.23-alpine AS build
ARG TARGETOS=linux
ARG TARGETARCH
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build \
    -trimpath -ldflags="-s -w" -o /out/var-scope ./cmd/dashboard && \
    mkdir -p /out/data

FROM scratch
ARG IMAGE_DESCRIPTION="Lightweight Variscite board diagnostics dashboard"
LABEL org.opencontainers.image.title="VAR-Scope"
LABEL org.opencontainers.image.description="${IMAGE_DESCRIPTION}"
COPY --from=build /out/var-scope /var-scope
COPY --from=build --chown=65532:65532 /out/data /data
COPY --from=build /etc/ssl/certs/ca-certificates.crt \
  /etc/ssl/certs/ca-certificates.crt
USER 65532:65532
EXPOSE 9090
ENTRYPOINT ["/var-scope"]
