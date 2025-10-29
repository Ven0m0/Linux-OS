#!/usr/bin/env bash
LC_ALL=C

go install github.com/dkorunic/betteralign/cmd/betteralign@latest
go install github.com/johnsiilver/goptimizer@latest
betteralign -apply -fix -generated_files ./...
goptimizer --goflags="--ldflags=-s -w"
