.PHONY: help install uninstall lint test

help:
	@echo "Targets: install, uninstall, lint, test"

install:
	@./install.sh

uninstall:
	@./uninstall.sh

lint:
	@bash -n bin/byobu-session-state
	@bash -n bin/byobu
	@bash -n bin/byobu-codex
	@bash -n bin/byobu-remote
	@bash -n bin/byobu-git-sync
	@bash -n tests/byobu-wrapper.sh
	@bash -n tests/byobu-remote.sh
	@bash -n tests/dynamic-tabs.sh
	@bash -n tests/autosave-guard.sh
	@bash -n tests/doctor-prune.sh
	@bash -n tests/watchdog.sh
	@bash -n install.sh
	@bash -n uninstall.sh
	@bash -n tests/cli.sh
	@bash -n tests/codex.sh
	@bash -n tests/git-sync.sh
	@bash -n tests/smoke.sh

test: lint
	@./tests/cli.sh
	@./tests/autosave-guard.sh
	@./tests/doctor-prune.sh
	@./tests/watchdog.sh
	@./tests/byobu-wrapper.sh
	@./tests/byobu-remote.sh
	@./tests/dynamic-tabs.sh
	@./tests/codex.sh
	@./tests/git-sync.sh
	@./tests/smoke.sh
