# Makefile — dev-task runner for the ai session router.
#
# NOTE: this does NOT run the router. `ai` is a runtime dispatcher that must set
# CLAUDE_CONFIG_DIR / CODEX_HOME and exec INTO your interactive shell; make runs
# recipes in child processes, so an export here would never reach your shell.
# Use `ai ...` for routing. This Makefile only wraps repo dev tasks.

SHELL := /bin/zsh
BIN   := bin/ai
LIBS  := $(wildcard lib/*.zsh)
SNIPS := $(wildcard share/shell/*.zsh)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Syntax-check the router, all lib modules, and shell snippets (zsh -n)
	@rc=0; for f in $(BIN) $(LIBS) $(SNIPS); do \
		zsh -n "$$f" && echo "  ok $$f" || { echo "  FAIL $$f"; rc=1; }; \
	done; exit $$rc

.PHONY: test
test: ## Run the read-only / dry-run smoke battery
	@sh scripts/smoke.sh

.PHONY: check
check: lint test ## lint + test (use before committing)

.PHONY: install
install: ## Bootstrap symlink + config (idempotent; see install.sh)
	@sh install.sh

.PHONY: guard
guard: ## Print the ~/.zshrc line to enable the bare-tool guard (does not edit rc)
	@$(BIN) guard install

.PHONY: prompt
prompt: ## Print the ~/.zshrc line to enable the prompt profile segment (does not edit rc)
	@$(BIN) prompt install
