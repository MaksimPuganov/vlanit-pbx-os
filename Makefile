# VLANit PBX OS — сборка установочного ISO

.PHONY: all iso image test clean help check

all: iso

# Полная сборка ISO. Сборка ВСЕГДА внутри привилегированного build-контейнера
# Debian 13 (root внутри контейнера): сборка на хосте под обычным
# пользователем приводит к rootfs с uid 1000 и неработающему sudo (полевой
# дефект 1.2.4, см. docs/specs/1.2.7-field-fixes.md).
iso: check image
	docker run --rm --privileged -v "$$PWD:/build" vlanit-build:1.1 bash scripts/build.sh

# build-контейнер (scripts/Dockerfile.build)
image:
	docker build -q -t vlanit-build:1.1 -f scripts/Dockerfile.build scripts/ >/dev/null

# Автоматизированные тесты в QEMU/KVM
test: check
	bash scripts/test-qemu.sh

check:
	@command -v docker >/dev/null || { echo "ERROR: нужен docker (build host)"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "ERROR: docker daemon недоступен"; exit 1; }
	@test -f build/payload/mikopbx.tar.zst || { echo "NOTE: payload MikoPBX отсутствует, будет выполнен scripts/pull-mikopbx.sh"; }

clean:
	rm -rf build/rootfs build/live build/iso-staging build/initramfs
	rm -f build/*.log dist/*.iso dist/*.sha256

# чистка тестовых прогонов (оставляет 3 последних; KEEP_RUNS=N для Override)
clean-tests:
	@ls -1dt build/qemu/2* 2>/dev/null | tail -n +4 | xargs -r rm -rf
	@rm -f /tmp/vlanit-*-usb-*.raw /tmp/vlanit-*-pkg-*
	@echo "тестовые прогоны очищены"

help:
	@echo "VLANit PBX OS build system"
	@echo ""
	@echo "  make iso    — полная сборка ISO (scripts/build.sh)"
	@echo "  make test   — тесты в QEMU/KVM (scripts/test-qemu.sh)"
	@echo "  make clean  — очистка сборочных каталогов (не трогает payload и tools)"
	@echo ""
	@echo "Ключевые артефакты:"
	@echo "  build/payload/mikopbx.tar.zst — контейнерный образ MikoPBX"
	@echo "  dist/VLANit-PBX-1.2.7-amd64.iso — итоговый ISO"
