SHELL := /usr/bin/env bash

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help start stop nuke new list services-up services-down done prune download-nyctaxi watch-remote-sync

help:
	@echo "Metabase local stack"
	@echo
	@echo "  make start        [MB_VERSION=<v> DATASET=<d>]  -- interactive picker, or direct if args supplied"
	@echo "  make stop         [MB_VERSION=<v> DATASET=<d>]  -- interactive picker, or direct if args supplied"
	@echo "  make nuke         [MB_VERSION=<v> DATASET=<d>]  -- interactive picker, or direct if args supplied"
	@echo "  make list                                        -- show all configured stacks and their status"
	@echo "  make new                                         -- create a new version env file, optionally start"
	@echo "  make services-up                                 -- start shared services (Mailpit + webhook tester)"
	@echo "  make services-down                               -- stop shared services"
	@echo "  make done                                        -- stop all running stacks and shared services"
	@echo "  make prune                                       -- remove all unused images (tagged and untagged) and orphaned volumes"
	@echo "  make download-nyctaxi [YEAR=<yyyy>]              -- one-time download of NYC taxi data for the clickhouse-nyctaxi dataset (defaults to 2025)"
	@echo "  make watch-remote-sync [MB_VERSION=<v> DATASET=<d>] -- auto-pull the remote-sync checkout whenever a push lands (Ctrl-C to stop)"
	@echo
	@echo "See README.md for setup instructions."

start:
ifneq ($(MB_VERSION),)
	@bash "$(ROOT_DIR)/scripts/start.sh" "$(MB_VERSION)" "$(DATASET)"
else
	@bash "$(ROOT_DIR)/scripts/pick.sh" start
endif

stop:
ifneq ($(MB_VERSION),)
	@bash "$(ROOT_DIR)/scripts/stop.sh" "$(MB_VERSION)" "$(DATASET)"
else
	@bash "$(ROOT_DIR)/scripts/pick.sh" stop
endif

nuke:
ifneq ($(MB_VERSION),)
	@bash "$(ROOT_DIR)/scripts/nuke.sh" "$(MB_VERSION)" "$(DATASET)"
else
	@bash "$(ROOT_DIR)/scripts/pick.sh" nuke
endif

new:
	@bash "$(ROOT_DIR)/scripts/new-stack.sh"

list:
	@bash "$(ROOT_DIR)/scripts/list-stacks.sh"

services-up:
	@bash "$(ROOT_DIR)/scripts/shared-services.sh" up

services-down:
	@bash "$(ROOT_DIR)/scripts/shared-services.sh" down

done:
	@bash "$(ROOT_DIR)/scripts/done.sh"

prune:
	@echo "Removing expired retained Metabase images..."
	@bash "$(ROOT_DIR)/scripts/prune-images.sh"
	@echo "Removing unused images (tagged and untagged)..."
	@docker image prune -a -f
	@echo "Removing orphaned volumes..."
	@docker volume prune -f

download-nyctaxi:
	@bash "$(ROOT_DIR)/scripts/download-nyctaxi-data.sh" "$(YEAR)"

watch-remote-sync:
ifneq ($(MB_VERSION),)
	@bash "$(ROOT_DIR)/scripts/watch-remote-sync.sh" "$(MB_VERSION)" "$(DATASET)"
else
	@bash "$(ROOT_DIR)/scripts/pick.sh" watch-remote-sync
endif
