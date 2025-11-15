#!/usr/bin/env bash
LC_ALL=C
# CGO_ENABLED=0
export GOGC=200 GOMAXPROCS="$(nproc)" GOFLAGS="-ldflags=-s -w -trimpath -modcacherw -pgo auto"
go telemetry off
go install github.com/dkorunic/betteralign/cmd/betteralign@latest
go install github.com/johnsiilver/goptimizer@latest
betteralign -apply -fix -generated_files ./...
goptimizer --goflags="--ldflags=-s -w -trimpath -modcacherw"
