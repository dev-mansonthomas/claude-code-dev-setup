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
	@echo "  make new-project NAME=app  # scaffold ../app from the template"

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
	@shellcheck -x --source-path=SCRIPTDIR setup.sh doctor.sh grafana-up.sh grafana-down.sh scripts/*.sh claude-config/hooks/*.sh && echo "shellcheck: clean"

## new-project: scaffold a new project from project-template/ (NAME=... [DEST=...])
.PHONY: new-project
new-project:
	@test -n "$(NAME)" || { echo "Usage: make new-project NAME=my-app [DEST=path]"; exit 1; }
	@dest="$(DEST)"; dest="$${dest:-../$(NAME)}"; \
	 test ! -e "$$dest" || { echo "Error: $$dest already exists"; exit 1; }; \
	 mkdir -p "$$dest"; \
	 cp -R project-template/. "$$dest"/; \
	 find "$$dest" -type f \( -name '*.md' -o -name '*.json' -o -name '*.toml' -o -name '*.yml' \) \
	   -exec sed -i.bak -e 's/{{PROJECT_NAME}}/$(NAME)/g' -e "s/{{DATE}}/$$(date +%F)/g" {} +; \
	 find "$$dest" -name '*.bak' -delete; \
	 ( cd "$$dest" && git init -q && git add -A ); \
	 echo "✓ Created $$dest"; \
	 echo "  Next: cd $$dest && claude   (then run /brainstorm to qualify the idea)"
