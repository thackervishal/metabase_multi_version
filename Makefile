SHELL := /usr/bin/env bash

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

include $(ROOT_DIR)/versions.mk

MB_VERSION ?= $(DEFAULT_VERSION)
DATASET ?= $(DEFAULT_DATASET)

.PHONY: help start stop nuke

help:
	@echo "Metabase local stack"
	@echo
	@echo "  make start MB_VERSION=<version> DATASET=<dataset>"
	@echo "  make stop MB_VERSION=<version> DATASET=<dataset>"
	@echo "  make nuke MB_VERSION=<version> DATASET=<dataset>"
	@echo
	@echo "Defaults: MB_VERSION=$(DEFAULT_VERSION) DATASET=$(DEFAULT_DATASET)"
	@echo "Available versions: $(MB_VERSIONS)"
	@echo "Available datasets: $(DATASETS)"

start:
	@"$(ROOT_DIR)/scripts/start.sh" "$(MB_VERSION)" "$(DATASET)"

stop:
	@"$(ROOT_DIR)/scripts/stop.sh" "$(MB_VERSION)" "$(DATASET)"

nuke:
	@"$(ROOT_DIR)/scripts/nuke.sh" "$(MB_VERSION)" "$(DATASET)"
