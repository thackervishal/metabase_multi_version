SHELL := /usr/bin/env bash

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help start stop nuke

help:
	@echo "Metabase local stack"
	@echo
	@echo "  make start [MB_VERSION=<version> DATASET=<dataset>]"
	@echo "  make stop  [MB_VERSION=<version> DATASET=<dataset>]"
	@echo "  make nuke  [MB_VERSION=<version> DATASET=<dataset>]"
	@echo
	@echo "Omit MB_VERSION to get an interactive stack picker."
	@echo "Create env/mb_versions/<version>.env from env/mb_versions/template.env.example."
	@echo "See README.md for setup instructions."

start:
ifneq ($(MB_VERSION),)
	@"$(ROOT_DIR)/scripts/start.sh" "$(MB_VERSION)" "$(DATASET)"
else
	@"$(ROOT_DIR)/scripts/pick.sh" start
endif

stop:
ifneq ($(MB_VERSION),)
	@"$(ROOT_DIR)/scripts/stop.sh" "$(MB_VERSION)" "$(DATASET)"
else
	@"$(ROOT_DIR)/scripts/pick.sh" stop
endif

nuke:
ifneq ($(MB_VERSION),)
	@"$(ROOT_DIR)/scripts/nuke.sh" "$(MB_VERSION)" "$(DATASET)"
else
	@"$(ROOT_DIR)/scripts/pick.sh" nuke
endif
