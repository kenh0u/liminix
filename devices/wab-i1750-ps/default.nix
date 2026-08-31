{
  # device/wab-i1750-ps/default.nix — ELECOM WAB-I1750-PS (QCA9558) device
  # definition for Liminix.
  #
  # Patterned on `liminix/devices/gl-ar750/default.nix` (QCA9531, ath79, 16 MiB
  # NOR, ath9k + ath10k, mipseb). The QCA9558 WAB is structurally similar but:
  #   * 2.4G SoC ath9k (caldata at art+0x1000/0x440)
  #   * 5G QCA9880 PCIe ath10k (caldata at art+0x5000/0x844 — same offsets as
  #     gl-ar750 QCA9887)
  #   * 2x GbE on separate GMACs (no switch chip)
  #   * 2x UARTs (SERVICE ttyS0 = 8250/16550, SERIAL ttyATH1 = ar9330-compat)
  #   * GPIO12 external wdt-gpio, always-running
  #   * GPIO-controlled buzzer, USB 2.0, 3 LEDs, 3 buttons
  #
  # See PLAN.md §2 (hardware facts) and §6.2 (design sketch).
  #

  system = {
    crossSystem = {
      config = "mips-unknown-linux-musl";
      gcc = {
        abi = "32";
        arch = "24kc";
      };
    };
  };

  description = ''

    == ELECOM WAB-I1750-PS

    === Hardware summary

    The ELECOM WAB-I1750-PS is a PoE-powered enterprise access point with:

    * Qualcomm Atheros QCA9558 SoC, MIPS 74Kc big-endian @ 720 MHz
    * 128 MiB DDR2 RAM
    * 16 MiB SPI-NOR (Macronix MX25L12835FMI-10G, 64 KiB erase blocks)
    * 2.4 GHz radio (SoC ath9k via AHB)
    * 5 GHz radio (QCA9880 via PCIe, ath10k)
    * 2x 10/100/1000 Ethernet (no switch chip; independent netdevs)
      * eth0 — GMAC0 RGMII, AR8035 PHY, "PD" port (PoE-in)
      * eth1 — GMAC1 SGMII, AR8033 PHY, "PSE" port (PoE-out when powered
        by DC or 802.3at)
    * USB 2.0 Type-A (vbus on GPIO11)
    * 3 LEDs (status / USB / 2.4G WLAN), 3 buttons (WPS / reset / eject),
      GPIO buzzer
    * External watchdog: GPIO12 linux,wdt-gpio, toggle, 300 ms margin,
      always-running

    === Installation

    The factory WebUI accepts the OpenWrt factory.bin image (128B elx-header
    + XOR 8844A2D168B45A2D). Liminix builds a plain uImage which must be
    written to the firmware partition via U-Boot (`outputs.mtdimage`) or
    via `mtd write` from a Liminix/OpenWrt RAM-boot (see RECOVERY.md path A).

    === Cables and power

    Two RJ-45 ports on the case provide serial access:

    * SERVICE — TTL 3.3V, **3.3V line (pin 1) must be supplied** for the
      74HC126D OE gate to enable TX output. Pinout: 1=3.3V, 2=GND,
      3=TX (to host RX), 4=RX (from host TX). 115200n8. ttyS0.
    * SERIAL — RS-232C ±12V, Cisco console cable compatible. Pinout:
      3=TXD, 4=GND, 5=GND, 6=RXD. 115200n8. ttyATH1.
      **Do not connect a 3.3V TTL adapter to this port.**

    Power: DC jack 12 V / 1.04 A, or PoE 802.3af/at on the PD port.

    OpenWrt commit b18edb1bfa34 documents the same hardware; the device
    tree and patches we use are sourced from OpenWrt v25.12.3.
  '';

  module =
    {
      pkgs,
      config,
      lim,
      lib,
      ...
    }:
    let
      inherit (lib) mkForce;
      inherit (pkgs.pseudofile) dir symlink;
      openwrt = pkgs.openwrt_25_12;
      firmwareBlobs = pkgs.pkgsBuildBuild.fetchgit {
        url = "https://git.codelinaro.org/clo/ath-firmware/ath10k-firmware";
        # Same rev pin as gl-ar750 — CodeLinaro bundles QCA988X/hw2.0 (the
        # chip family used by WAB's QCA9880) alongside QCA9887/hw1.0 in this
        # commit; if that turns out to be false we revise the rev or fall
        # back to a different path.
        rev = "e1d4991c717ecb252aeabd5f1a3c97551a1906f2";
        hash = "sha256-skH12f4ZQouBU6Gb8dgWJYT3kkDFNEq7lg/0RDGJ8LY=";
      };
      firmware = pkgs.stdenv.mkDerivation {
        name = "wlan-firmware";
        phases = [ "installPhase" ];
        installPhase = ''
          # QCA9880 chip (WAB's 5G radio) is QCA988X family, hw revision 2.0.
          # The runtime path the kernel looks up is /lib/firmware/ath10k/QCA988X/hw2.0/
          # (same convention as OpenWrt's ath10k-firmware-qca988x package).
          mkdir -p $out/ath10k/QCA988X/hw2.0/
          blobdir=${firmwareBlobs}/QCA988X/hw2.0
          cp $blobdir/10.2.4-1.0/firmware-5.bin_10.2.4-1.0-00047 \
             $out/ath10k/QCA988X/hw2.0/firmware-5.bin
          cp $blobdir/board.bin \
             $out/ath10k/QCA988X/hw2.0/
        '';
      };
      mac80211 = pkgs.kmodloader.override {
        targets = [
          "ath9k"
          "ath10k_pci"
        ];
        inherit (config.system.outputs) kernel;
        dependencies = [ ath10k_cal_data ];
      };
      ath10k_cal_data =
        let
          offset = lim.parseInt "0x5000";
          size = lim.parseInt "0x844";
        in
        pkgs.liminix.services.oneshot rec {
          name = "ath10k_cal_data";
          up = ''
            part=$(basename $(dirname $(grep -l art /sys/class/mtd/*/name)))
            echo ART partition is ''${part-unset}
            test -n "$part" || exit 1
            (in_outputs ${name}
             dd if=/dev/$part of=data iflag=skip_bytes,fullblock bs=${toString size} skip=${toString offset} count=1
            )
          '';
        };
    in
    {
      imports = [
        ../../modules/network
        ../../modules/arch/mipseb.nix
        ../../modules/outputs/tftpboot.nix
        ../../modules/outputs/mtdimage.nix
        ../../modules/outputs/jffs2.nix
      ];

      programs.busybox.options = {
        FEATURE_DD_IBS_OBS = "y"; # ath10k_cal_data needs skip_bytes,fullblock
      };

      hardware = {
        defaultOutput = "mtdimage";
        # Confirmed by selftest against the OpenWrt v25.12.3 factory image:
        # the embedded uImage uses load=entry=0x80060000. PLAN §6.2 prediction.
        loadAddress = lim.parseInt "0x80060000";
        entryPoint = lim.parseInt "0x80060000";
        flash = {
          # KSEG1 view of the firmware partition (16 MiB NOR layout).
          address = lim.parseInt "0x9F070000";
          size = lim.parseInt "0xE00000";  # 14 MiB
          eraseBlockSize = 65536;
        };
        # TODO(phase3): verify on a real OpenWrt baseline that
        # MTD_SPLIT_UIMAGE_FW yields the expected /dev/mtdblock<N> for the
        # post-split rootfs. Likely candidates are mtdblock8 or mtdblock9
        # (firmware is /dev/mtd4; sub-MTDs after split are numbered after
        # the highest existing index).
        rootDevice = "/dev/mtdblock6";
        dts = {
          src = "${openwrt.src}/target/linux/ath79/dts/qca9558_elecom_wab-i1750-ps.dts";
          includePaths = [
            "${openwrt.src}/target/linux/ath79/dts"
          ];
        };

        networkInterfaces =
          let
            inherit (config.system.service.network) link;
          in
          {
            lan0 = link.build {
              ifname = "lan0";
              devpath = "/devices/platform/ahb/19000000.eth";
            };
            lan1 = link.build {
              ifname = "lan1";
              devpath = "/devices/platform/ahb/1a000000.eth";
            };
            wlan0 = link.build {
              ifname = "wlan0";
              dependencies = [ mac80211 ];
            };
            wlan5 = link.build {
              ifname = "wlan5";
              dependencies = [
                ath10k_cal_data
                mac80211
              ];
            };
          };
      };

      filesystem = dir {
        lib = dir {
          firmware = dir {
            ath10k = dir {
              QCA988X = symlink "${firmware}/ath10k/QCA988X";
              "cal-pci-0000:00:00.0.bin" = symlink "${ath10k_cal_data}/.outputs/data";
            };
          };
        };
      };

      # Kernel command line.
      #
      # mipseb.nix provides `console=ttyS0,115200`. We mkForce it to include
      # both consoles so that kernel logs appear on both SERVICE (ttyS0)
      # and SERIAL (ttyATH1, RS-232C ±12V) ports. The LAST console= wins
      # for /dev/console selection, which becomes the sysfs-active tty for
      # s6 getty, so we keep ttyS0 last to ensure login lands on SERVICE.
      #
      # Phase 4 will add an explicit second s6 getty on ttyATH1 to provide
      # shell access on the SERIAL port too.
      boot.commandLine = mkForce [
        "console=ttyATH1,115200n8"
        "console=ttyS0,115200n8"
      ];

      boot.tftp = {
        # TODO(phase1): replace with the U-Boot default `loadaddr` value
        # once Phase 1 prints it from the real device. 0x81000000 is a
        # high-RAM scratch address that leaves room for kernel/rootfs/dtb
        # below it; 128 MiB RAM provides ample headroom.
        loadAddress = lim.parseInt "0x81000000";
        appendDTB = true;
        # Bench-default TFTP endpoints. Override per build in user configs
        # if the bench network changes.
        serverip = "192.168.3.10";
        ipaddr = "192.168.3.12";
      };

      kernel = {
        src = openwrt.kernelSrc;
        version = openwrt.kernelVersion;
        extraPatchPhase = ''
          ${openwrt.applyPatches.ath79}
          sed -i.bak -e '\,include <linux/hw_random.h>,a #include <linux/gpio/driver.h>'  drivers/net/wireless/ath/ath9k/ath9k.h # context reqd for next patch
        '';

        config = {
          # Base (mirrors devices/gl-ar750/default.nix)
          ATH79 = "y";
          PCI = "y";
          PCI_AR724X = "y";

          # Base 8250 console for ttyS0 (SERVICE)
          SERIAL_8250_CONSOLE = "y";
          SERIAL_8250 = "y";
          SERIAL_CORE_CONSOLE = "y";
          SERIAL_OF_PLATFORM = "y"; # opens /dev/console at boot

          # Second UART for ttyATH1 (SERIAL, RS-232C). The ar933x UART in
          # the QCA9558 is qca,ar9330-uart compatible, exposed at
          # 0x18500000 (see WAB DTS uart1 node). Linux 6.12 needs the
          # SERIAL_AR933X driver; OpenWrt patches make the IP block
          # actually present on this SoC.
          SERIAL_AR933X = "y";
          SERIAL_AR933X_CONSOLE = "y";
          # Correct symbol name (NOT NR_UARTS, which is the 8250 driver
          # generic and was being silently dropped by olddefconfig).
          SERIAL_AR933X_NR_UARTS = "2";

          CONSOLE_LOGLEVEL_DEFAULT = "8";
          CONSOLE_LOGLEVEL_QUIET = "4";

          NET = "y";
          ETHERNET = "y";
          NET_VENDOR_ATHEROS = "y";
          AG71XX_LEGACY = "y"; # ethernet (qca,qca9530-eth)
          MFD_SYSCON = "y"; # ethernet (compatible "syscon")
          AT803X_PHY = "y"; # AR8035 (eth0) and AR8033 (eth1)
          # AR8216_PHY omitted — WAB has no switch chip

          MTD_SPI_NOR = "y";

          SPI_ATH79 = "y";
          SPI_MASTER = "y";
          SPI_MEM = "y";
          SPI_AR934X = "y";
          SPI_BITBANG = "y";
          SPI_GPIO = "y";

          GPIO_ATH79 = "y";
          GPIOLIB = "y";
          EXPERT = "y";
          GPIO_SYSFS = "y"; # required by patches-5.15/0004-phy-add-ath79-usb-phys.patch
          OF_GPIO = "y";
          SYSFS = "y";
          SPI = "y";
          MTD = "y";
          MTD_BLOCK = "y";

          # External watchdog on GPIO12 (always-running toggle, 300 ms).
          # The SoC's own wdt is disabled in DTS (&wdt status="disabled").
          # We must feed the GPIO wdt — without this the board will reset
          # every ~300 ms once Linux takes over the pin.
          #
          # WATCHDOG (the menuconfig) must be set explicitly — the
          # sub-options WATCHDOG_CORE and GPIO_WATCHDOG live in an
          # `if WATCHDOG` block, so they're silently dropped without it.
          WATCHDOG = "y";
          WATCHDOG_CORE = "y";
          GPIO_WATCHDOG = "y";
          # ATH79_WDT intentionally not set — DTS disables it.

          # USB 2.0 Type-A (vbus on GPIO11, regulator-fixed). OpenWrt's
          # ath79 defconfig leaves this to userspace (kmod-usb2); we
          # build it in to keep the kernel self-contained.
          # NOTE: Correct symbol names use _HCD_PLATFORM (NOT _PLATFORM).
          USB_SUPPORT = "y";
          USB = "y";
          USB_COMMON = "y";
          USB_EHCI_HCD = "y";
          USB_EHCI_HCD_PLATFORM = "y";
          USB_OHCI_HCD = "y";
          USB_OHCI_HCD_PLATFORM = "y";
          USB_PHY = "y";
          NOP_USB_XCEIV = "y";
          USB_ULPI = "y";
          # USB_LED_TRIG depends on LEDS_TRIGGERS; auto-set when that's y.

          # LEDs (status / USB / WLAN), buttons (WPS / reset / eject), buzzer.
          # LEDS_TRIGGERS is a menuconfig that must be set for the
          # sub-options to take effect. The actual `phy1tpt` and `usbport`
          # triggers are auto-registered by the phy/usb subsystems when
          # LEDS_TRIGGERS=y (no separate CONFIG symbol).
          LEDS_TRIGGERS = "y";
          LEDS_TRIGGER_TIMER = "y";
          LEDS_TRIGGER_HEARTBEAT = "y";
          INPUT = "y";
          INPUT_EVDEV = "y";
          KEYBOARD_GPIO = "y";
          INPUT_GPIO_BEEPER = "y";

          EARLY_PRINTK = "y";
          PRINTK_TIME = "y";
        };

        conditionalConfig = {
          WLAN = {
            WLAN_VENDOR_ATH = "y";
            ATH_COMMON = "m";
            ATH9K = "m";
            ATH9K_AHB = "m";
            ATH9K_HTC = "m";
            ATH10K = "m";
            ATH10K_PCI = "m";
            ATH10K_DEBUG = "y";
          };
        };
      };
    };
}
