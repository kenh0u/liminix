# Liminix

> [!NOTE]
> **This is a personal fork** of [Liminix](https://github.com/telent/liminix)
> by [@kenh0u](https://github.com/kenh0u), created to port Liminix to the
> **ELECOM WAB-I1750-PS** access point (QCA9558 / ath79). It is not
> affiliated with upstream Liminix, and **no pull requests will be submitted
> upstream** from this fork.
>
> **LLM disclosure:** development on this fork (device support, tooling and
> documentation for the WAB-I1750-PS port) is assisted by LLM coding agents.
> This is one reason it will not be proposed upstream, whose policy declines
> LLM-assisted contributions.
>
> **Licensing:** unchanged from upstream. Original Liminix code is MIT
> (© Daniel Barlow and contributors); OpenWrt-derived DTS and kernel patches
> retain their upstream SPDX headers and licenses (GPL-2.0-or-later OR MIT
> for DTS, GPL-2.0 for patches). See `LICENSE`.
>
> **Branches:** `main` tracks upstream `main` (kept pristine, fast-forward
> only). All development happens on `wab-i1750-ps`, which is the default
> branch of this fork.
>
> 本リポジトリは ELECOM WAB-I1750-PS (QCA9558) への Liminix 移植を目的とした
> 個人 fork です。上流への PR は行いません。本 fork の WAB-I1750-PS 対応は
> LLM 支援開発を含みます。ライセンスは上流のまま（MIT + OpenWrt 由来部分は
> それぞれのライセンス）。

A Nix-based system for configuring consumer wifi routers or IoT device
devices, of the kind that OpenWrt or DD-WRT or Gargoyle or Tomato run
on. It's a reboot/restart/rewrite of NixWRT.

This is not NixOS-on-your-router: it's aimed at devices that are
underpowered for the full NixOS experience. It uses busybox tools,
musl instead of GNU libc, and s6-rc instead of systemd.

The Liminix name comes from Liminis, in Latin the genitive declension
of "limen", or "of the threshold". Your router stands at the threshold
of your (online) home and everything you send to/receive from the
outside word goes across it.


## Current status (does it work yet?)

Liminix 1.0 was released in April 2025. It works for me and I would
say it has seen lots of use in the particular applications of "home
wifi router" and "wireless extender".

It's not “finished” - we are still finding new and better ways to do
things - but we endeavour to signal future breaking changes through the
version number. This is “semver-adjacent”, in that minor bumps
(1.1, 1.2 …) are used for minor new features and major bumps (2.0 …)
for changes that are likely to break out-of-tree modules or
configurations. It won’t be semver exactly because [every change
breaks someone’s workflow](https://xkcd.com/1172/), but we aspire to
have the magnitude of the version delta correlate with the scale of
the consequences of upgrading.

The [NEWS](NEWS) file (available wherever you found this README) is
a high-level overview of breaking changes.

Development mostly happens on the `main` branch, which is therefore
not guaranteed to build or to work on every commit. For the latest
functioning version, see [the CI
system](https://build.liminix.org/jobset/liminix/build) and pick a
revision with all jobs green. Note that Liminix `main` branch is built
against the "unstable" version of nixpkgs/nixos, not against the
yy.mm release versions.


## Documentation

Documentation is in the [doc](doc/) directory. You can build it
by running

    nix-build -I liminix=`pwd`  ci.nix -A doc

Rendered documentation corresponding to the latest commit on `main`
is published to [https://www.liminix.org/doc/](https://www.liminix.org/doc/)


## Extremely online

There is a #liminix IRC channel on the [OFTC](https://www.oftc.net/)
network in which you are welcome. You can also connect with a Matrix
client by joining the room `#_oftc_#liminix:matrix.org`.

In the IRC channel, as in all Liminix project venues, please conduct yourself
according to the Liminix [Code of Conduct](CODE-OF-CONDUCT.md).
