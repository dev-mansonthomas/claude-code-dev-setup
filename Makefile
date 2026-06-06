.DEFAULT_GOAL := help
SHELL := /bin/bash

## help: show this help
.PHONY: help
help:
	@echo "claude-code-dev-setup"
	@echo
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
	@echo
	@echo "Examples:"
	@echo "  make setup                 # install & configure everything"
	@echo "  make doctor                # read-only health check"
	@echo "  ./new-project.sh app       # scaffold ../app  (or: make new-project NAME=app)"

## setup: install Claude Code, skills, MCP, and global config
.PHONY: setup
setup:
	@./setup.sh

## doctor: print what's installed/configured (read-only)
.PHONY: doctor
doctor:
	@./doctor.sh

## lint: shellcheck all shell scripts
.PHONY: lint
lint:
	@shellcheck -x --source-path=SCRIPTDIR setup.sh doctor.sh grafana-up.sh grafana-down.sh new-project.sh scripts/*.sh claude-config/hooks/*.sh && echo "shellcheck: clean"

## new-project: scaffold a new project from project-template/ (NAME=... [DEST=...])
.PHONY: new-project
new-project:
	@test -n "$(NAME)" || { echo "Usage: make new-project NAME=my-app [DEST=path]  (or just: ./new-project.sh my-app)"; exit 1; }
	@./new-project.sh "$(NAME)" "$(DEST)"
