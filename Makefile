SHELL := /usr/bin/env bash

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help start stop nuke new remove list

help:
	@echo "Metabase local stack"
	@echo
	@echo "  make start        [MB_VERSION=<v> DATASET=<d>]  -- interactive picker, or direct if args supplied"
	@echo "  make stop         [MB_VERSION=<v> DATASET=<d>]  -- interactive picker, or direct if args supplied"
	@echo "  make nuke         [MB_VERSION=<v> DATASET=<d>]  -- interactive picker, or direct if args supplied"
	@echo "  make list                                        -- show all configured stacks and their status"
	@echo "  make new                                         -- create a new version env file, optionally start"
	@echo "  make remove                                      -- nuke a stack and delete its env file"
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

remove:
	@bash "$(ROOT_DIR)/scripts/remove-stack.sh"

list:
	@bash "$(ROOT_DIR)/scripts/list-stacks.sh"
