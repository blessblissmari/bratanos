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
	@find src -type f -name '*.sh' -o -name 'pacman' -o -name 'bratan-tidy' -o -name 'bratanos-grub-install' \
	  | xargs -I{} bash -n "{}" && echo "[lint] all bash scripts parse cleanly"
