PLIST := com.aekym.micbar.plist
AGENTS_DIR := $(HOME)/Library/LaunchAgents

install:
	cp $(PLIST) $(AGENTS_DIR)/$(PLIST)
	launchctl load $(AGENTS_DIR)/$(PLIST)

uninstall:
	-launchctl unload $(AGENTS_DIR)/$(PLIST)
	rm -f $(AGENTS_DIR)/$(PLIST)

restart:
	-launchctl unload $(AGENTS_DIR)/$(PLIST)
	launchctl load $(AGENTS_DIR)/$(PLIST)

run:
	./venv/bin/python3 mic-bar.py
