SHELL := /usr/bin/env bash

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help start stop nuke

help:
	@echo "Metabase local stack"
	@echo
	@echo "  make start MB_VERSION=<version> DATASET=<dataset>"
	@echo "  make stop  MB_VERSION=<version> DATASET=<dataset>"
	@echo "  make nuke  MB_VERSION=<version> DATASET=<dataset>"
	@echo
	@echo "MB_VERSION and DATASET are always required."
	@echo "Create env/mb_versions/<version>.env from env/mb_versions/template.env.example."
	@echo "See README.md for setup instructions."

start:
	@"$(ROOT_DIR)/scripts/start.sh" "$(MB_VERSION)" "$(DATASET)"

stop:
	@"$(ROOT_DIR)/scripts/stop.sh" "$(MB_VERSION)" "$(DATASET)"

nuke:
	@"$(ROOT_DIR)/scripts/nuke.sh" "$(MB_VERSION)" "$(DATASET)"
