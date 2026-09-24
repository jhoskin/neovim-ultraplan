NVIM ?= nvim

.PHONY: test unit test-e2e health lint

# Launch Neovim with the minimal test config (interactive)
test:
	$(NVIM) -u tests/minimal_init.lua

# Fast headless unit tests (no external deps)
unit:
	$(NVIM) --headless -l tests/unit/run.lua

# End-to-end tests (tmux-driven; needs tmux and jq)
test-e2e:
	bash tests/e2e/run_all.sh

# Health check in headless mode
health:
	$(NVIM) -u tests/minimal_init.lua --headless -c 'checkhealth ultraplan' -c 'w! /dev/stderr | qa!'

# Lint with luacheck (install: luarocks install luacheck)
lint:
	luacheck lua/ plugin/ --no-unused-args --no-max-line-length
