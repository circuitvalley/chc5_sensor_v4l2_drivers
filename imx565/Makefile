obj-m += imx565.o

KDIR ?= /lib/modules/$(shell uname -r)/build

# The driver source itself still builds on the CHC5 kernel (Xilinx 6.6 LTS) via
# its LINUX_VERSION_CODE shims, so the floor is enforced here in the package
# rather than with an #error in the .c file.
#
# Ask kbuild for the version rather than parsing $(KDIR)/Makefile: on Raspberry
# Pi OS that file is a one-line stub that includes the real Makefile from a
# separate -common- headers package, so it carries no VERSION/PATCHLEVEL of its
# own and grepping it wrongly reports "no kernel build tree".
KVER       := $(shell $(MAKE) -s -C $(KDIR) kernelversion 2>/dev/null)
KVER_MAJOR := $(firstword $(subst ., ,$(KVER)))
KVER_MINOR := $(word 2,$(subst ., ,$(KVER)))

all: check-kernel
	$(MAKE) -C $(KDIR) M=$(shell pwd) modules

check-kernel:
	@if [ -z "$(KVER)" ]; then \
		echo "ERROR: no usable kernel build tree at $(KDIR)"; \
		echo "       install the matching linux-headers package first"; \
		exit 1; \
	fi
	@if [ "$(KVER_MAJOR)" -lt 6 ] || { [ "$(KVER_MAJOR)" -eq 6 ] && [ "$(KVER_MINOR)" -lt 12 ]; }; then \
		echo "ERROR: this package needs Linux 6.12 or newer (found $(KVER))"; \
		exit 1; \
	fi

clean:
	$(MAKE) -C $(KDIR) M=$(shell pwd) clean

%.dtbo: %.dts
	dtc -@ -I dts -O dtb -o $@ $<

.PHONY: all clean check-kernel
