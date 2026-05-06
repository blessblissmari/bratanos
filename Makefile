# BratanOS build helper.
#
# `make stage` copies source files into archiso/airootfs at the right paths.
# `make iso`   runs mkarchiso to build the bootable ISO (must be on Arch).
# `make clean` clears generated artifacts.
# `make qemu`  boots the most recently built ISO in QEMU/UEFI.

ROOT      := $(CURDIR)
PROFILE   := $(ROOT)/archiso
AIROOT    := $(PROFILE)/airootfs
OUT       := $(ROOT)/out
WORK      := $(ROOT)/work
ISO_NAME  := bratanos

.PHONY: all stage iso iso-docker clean qemu lint help

help:
	@echo "Targets:"
	@echo "  stage       — copy src/ scripts into archiso/airootfs"
	@echo "  iso         — build ISO via mkarchiso (needs root + arch host)"
	@echo "  iso-docker  — build ISO inside an arch container (works on any Linux)"
	@echo "  clean       — remove out/ and work/"
	@echo "  qemu        — boot the latest built ISO in QEMU UEFI"
	@echo "  lint        — bash -n every shell script"

stage:
	install -Dm0755 src/bratan-tidy/bratan-tidy        $(AIROOT)/usr/bin/bratan-tidy
	install -Dm0644 src/bratan-tidy/bratan-tidy.1      $(AIROOT)/usr/share/man/man1/bratan-tidy.1
	install -Dm0644 src/bratan-tidy/tidy.conf          $(AIROOT)/etc/bratanos/tidy.conf
	install -Dm0755 src/bratan-pacman/pacman           $(AIROOT)/usr/local/bin/pacman
	install -Dm0644 src/bratan-pacman/paru.conf        $(AIROOT)/etc/paru.conf
	install -Dm0755 src/bratan-pacman/00-bratanos-pacman-path.sh \
	                                                   $(AIROOT)/etc/profile.d/00-bratanos-pacman-path.sh
	install -Dm0755 src/bratan-grub/bratanos-grub-install \
	                                                   $(AIROOT)/usr/bin/bratanos-grub-install
	# bratan-recorder
	install -Dm0755 src/bratan-recorder/bratan-recorder \
	                                                   $(AIROOT)/usr/bin/bratan-recorder
	install -Dm0644 src/bratan-recorder/bratan-recorder.desktop \
	                                                   $(AIROOT)/usr/share/applications/bratan-recorder.desktop
	# bratan-photos
	install -Dm0755 src/bratan-photos/bratan-photos \
	                                                   $(AIROOT)/usr/bin/bratan-photos
	install -Dm0644 src/bratan-photos/bratan-photos.desktop \
	                                                   $(AIROOT)/usr/share/applications/bratan-photos.desktop
	# bratan-music
	install -Dm0755 src/bratan-music/bratan-music \
	                                                   $(AIROOT)/usr/bin/bratan-music
	install -Dm0644 src/bratan-music/bratan-music.desktop \
	                                                   $(AIROOT)/usr/share/applications/bratan-music.desktop
	# bratan-mail
	install -Dm0755 src/bratan-mail/bratan-mail \
	                                                   $(AIROOT)/usr/bin/bratan-mail
	install -Dm0644 src/bratan-mail/bratan-mail.desktop \
	                                                   $(AIROOT)/usr/share/applications/bratan-mail.desktop
	# bratan-browser
	install -Dm0755 src/bratan-browser/bratan-browser \
	                                                   $(AIROOT)/usr/bin/bratan-browser
	install -Dm0644 src/bratan-browser/bratan-browser.desktop \
	                                                   $(AIROOT)/usr/share/applications/bratan-browser.desktop
	install -Dm0644 src/bratan-browser/policies.json \
	                                                   $(AIROOT)/etc/bratan-browser/policies.json
	install -Dm0644 src/bratan-browser/policies.json \
	                                                   $(AIROOT)/usr/lib/firefox/distribution/policies.json
	# bratan-office
	install -Dm0755 src/bratan-office/bratan-office \
	                                                   $(AIROOT)/usr/bin/bratan-office
	install -Dm0644 src/bratan-office/bratan-office.desktop \
	                                                   $(AIROOT)/usr/share/applications/bratan-office.desktop
	# bratan-flash-persistent (carve a persistence partition next to the ISO)
	install -Dm0755 src/bratan-flash-persistent/bratan-flash-persistent \
	                                                   $(AIROOT)/usr/bin/bratan-flash-persistent
	@echo "[stage] sources copied into airootfs"

iso: stage
	@command -v mkarchiso >/dev/null || { echo "mkarchiso not found (install archiso)"; exit 1; }
	@[ "$$(id -u)" = 0 ] || { echo "must be root to build ISO"; exit 1; }
	rm -rf $(WORK)
	mkdir -p $(OUT) $(WORK)
	mkarchiso -v -w $(WORK) -o $(OUT) $(PROFILE)
	@echo "[iso] built artifacts in $(OUT)/"

iso-docker:
	@command -v docker >/dev/null || { echo "docker not found"; exit 1; }
	docker build -t bratanos-builder .
	docker run --rm --privileged -v "$(ROOT)":/build -w /build bratanos-builder make iso

qemu:
	@iso=$$(ls -t $(OUT)/$(ISO_NAME)-*.iso 2>/dev/null | head -1); \
	[ -n "$$iso" ] || { echo "no ISO in $(OUT)/ — run 'make iso' first"; exit 1; }; \
	echo "[qemu] booting $$iso"; \
	qemu-system-x86_64 -m 4G -enable-kvm -cpu host -smp 2 \
	    -bios /usr/share/ovmf/x64/OVMF.4m.fd \
	    -cdrom "$$iso"

clean:
	rm -rf $(OUT) $(WORK)

lint:
	@scripts=$$( \
	    find src -type f \
	      \( -name '*.sh' -o -name 'pacman' -o -name 'bratan-*' -o -name 'bratanos-*' \) \
	      ! -name '*.desktop' ! -name '*.conf' ! -name '*.json' ! -name '*.1' \
	  ); \
	  for s in $$scripts; do bash -n "$$s" || exit 1; done; \
	  echo "[lint] all bash scripts parse cleanly"
