.PHONY: help build test test-pty lint format demo check linux-shell linux-build linux-test linux-ci

help:
	@printf '%s\n' \
	  'Available targets:' \
	  '  make build        Build with warnings as errors' \
	  '  make test         Run the unit tests with warnings as errors' \
	  '  make test-pty     Drive the demo through a real pseudo-terminal' \
	  '  make lint         Run swift-format lint --strict' \
	  '  make format       Run swift-format in place' \
	  '  make demo         Run the component tour' \
	  '  make check        Run the local gates that mirror CI' \
	  '  make linux-shell  Open the pinned Swift Linux Docker shell' \
	  '  make linux-build  Run the Linux Docker build with warnings as errors' \
	  '  make linux-test   Run the Linux Docker tests with warnings as errors' \
	  '  make linux-ci     Run the Linux Docker build + test flow'

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test -Xswiftc -warnings-as-errors

test-pty: build
	python3 -I Scripts/test-pty.py

lint:
	swift-format lint --strict --recursive Sources Tests Package.swift

format:
	swift-format format --in-place --recursive Sources Tests Package.swift

demo:
	swift run swifty-terminal-demo

check: lint test test-pty linux-ci

linux-shell:
	Scripts/linux-shell.sh

linux-build:
	Scripts/linux-build.sh

linux-test:
	Scripts/linux-test.sh

linux-ci:
	Scripts/linux-ci.sh
