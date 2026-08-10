
{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;
in
{
  options = {
    system.service.dhcp4c = {
      client = mkOption { type = liminix.lib.types.serviceDefn; };
    };
  };
  config.system.service.dhcp4c = {
    client = config.system.callService ./client.nix {
      interface = mkOption {
        type = liminix.lib.types.interface;
        description = "interface to query for DHCP";
      };
    };
  };
  # this is already configured in modules/busybox.nix
  config.programs.busybox.applets = [ "udhcpc" ];
}
