.PHONY: build test image image-arm64 run

build:
	go build ./cmd/dashboard

test:
	./scripts/check-line-length
	go test ./...

image:
	docker build -t var-scope:experimental .

image-arm64:
	docker build --build-arg TARGETARCH=arm64 -t var-scope:experimental-arm64 .

run:
	docker compose up -d --build
