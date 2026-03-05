PLIST := com.aekym.micbar.plist
AGENTS_DIR := $(HOME)/Library/LaunchAgents
PROJECT_DIR := $(shell pwd)

$(PLIST): $(PLIST).template
	@sed 's|__PROJECT_DIR__|$(PROJECT_DIR)|g; s|__HOME__|$(HOME)|g' $(PLIST).template > $(PLIST)

install: $(PLIST)
	cp $(PLIST) $(AGENTS_DIR)/$(PLIST)
	launchctl load $(AGENTS_DIR)/$(PLIST)

uninstall:
	-launchctl unload $(AGENTS_DIR)/$(PLIST)
	rm -f $(AGENTS_DIR)/$(PLIST)

restart: $(PLIST)
	-launchctl unload $(AGENTS_DIR)/$(PLIST)
	cp $(PLIST) $(AGENTS_DIR)/$(PLIST)
	launchctl load $(AGENTS_DIR)/$(PLIST)

run:
	./venv/bin/python3 micbar.py

.PHONY: install uninstall restart run
