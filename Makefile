.PHONY: install uninstall check

DESTDIR = /usr/local
SUDOERSDIR = /etc/sudoers.d
DAEMONDIR = /Library/LaunchDaemons

ch = chris-cafe
lab = com.chrispennello.chris-cafe.reset

cht = $(DESTDIR)/bin/$(ch)
sut = $(SUDOERSDIR)/$(ch)
dat = $(DAEMONDIR)/$(lab).plist

install: $(cht) $(sut) $(dat)

$(cht): $(ch)
	install $< $@

$(sut): $(ch).sudoers
	visudo -c -f $<
	install -m 0440 -o root -g wheel $< $@

$(dat): $(lab).plist
	install -m 0644 -o root -g wheel $< $@
	@launchctl bootout system $@ >/dev/null 2>&1 || true
	launchctl bootstrap system $@
	@pgrep -f '$(DESTDIR)/bin/$(ch)' >/dev/null 2>&1 && \
	  echo 'WARNING: a $(ch) is running. Bootstrapping the daemon cleared' >&2 && \
	  echo '         its override. It re-takes it within one interval.' >&2 || true

check:
	@test "$$(id -u)" -ne 0 || { \
	  echo 'run make check as yourself, not under sudo:' >&2; \
	  echo 'as root every sudo test passes and proves nothing' >&2; exit 1; }
	@./$(ch) --vectors | while IFS= read -r v; do \
	  grep -qF -- "$$v" $(ch).sudoers || { \
	    echo "sudoers file does not carry: $$v" >&2; exit 1; }; \
	done || exit 1
	@echo 'sudoers file: carries all four script vectors'
	@./$(ch) --vectors | while IFS= read -r v; do \
	  sudo -k -n -l $$v >/dev/null 2>&1 || { \
	    echo "sudo policy denies: $$v" >&2; exit 1; }; \
	done || { echo 'run sudo make install' >&2; exit 1; }
	@echo 'sudo policy: all four permitted'
	@launchctl print system/$(lab) >/dev/null 2>&1 || { \
	  echo 'reset daemon: not loaded; run sudo make install' >&2; exit 1; }
	@echo "reset daemon: loaded ($$(launchctl print system/$(lab) | \
	  sed -n 's/.*last exit code = /last exit code /p' | head -1))"

uninstall:
	pmset -a disablesleep 0
	@launchctl bootout system $(dat) >/dev/null 2>&1 || true
	rm -f $(cht) $(sut) $(dat)
