{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.bazarr;
  nixarr = config.nixarr;
in {
  imports = [
    ./bazarr-module
  ];

  options.nixarr.bazarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Bazarr service.

        **Required options:** [`nixarr.enable`](#nixarr.enable)
      '';
    };

    package = mkPackageOption pkgs "bazarr" { };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/bazarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/bazarr"'';
      example = "/nixarr/.state/bazarr";
      description = ''
        The location of the state directory for the Bazarr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        > 
        > ```nix
        >   stateDir = /home/user/nixarr/.state/bazarr
        > ```
        > 
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.bazarr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Bazarr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Bazarr traffic through the VPN.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.bazarr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.enable -> nixarr.enable;
        message = ''
          The nixarr.bazarr.enable option requires the nixarr.enable option
          to be set, but it was not.
        '';
      }
    ];

    util-nixarr.services.bazarr = {
      enable = cfg.enable;
      package = cfg.package;
      user = "bazarr";
      group = "media";
      openFirewall = cfg.openFirewall;
      dataDir = cfg.stateDir;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.bazarr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # Port mappings
    # TODO: openports
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = config.bazarr.listenPort;
          to = config.bazarr.listenPort;
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString config.bazarr.listenPort}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = config.bazarr.listenPort;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString config.bazarr.listenPort}";
        };
      };
    };
  };
}
