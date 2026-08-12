# Z install

[![GitHub Actions](https://github.com/XIN-1/Zinstall/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/XIN-1/Zinstall/actions)
[![GitHub License](https://img.shields.io/github/license/XIN-1/Zinstall?color=%23C96FAD)](https://github.com/XIN-1/Zinstall/blob/main/LICENSE)

**Z install** is a lightweight IPA installer for iOS — a trimmed-down fork of [Feather](https://github.com/claration/Feather).

Unlike the full Feather, **Z install removes all signing features**. It is built to **install already-signed IPA files** onto your device using built-in installation techniques. You bring your own signing (your certificate, or on-device signing via Feather/Zsign); Z install handles the install.

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="Images/Image-dark.png"><source media="(prefers-color-scheme: light)" srcset="Images/Image-light.png"><img alt="Z install" src="Images/Image-light.png"></picture></p>

### Features

- User friendly, clean UI.
- Install already-signed applications (`.ipa`).
- Supports [AltStore](https://faq.altstore.io/distribute-your-apps/make-a-source#apps) repositories.
- View detailed information about installed apps.
- Tweak support for advanced users, using [Ellekit](https://github.com/tealbathingsuit/ellekit) for injection.
  - Supports injecting `.deb` and `.dylib` files.
- Liquid Glass UI (iOS 26).
- No tracking or analytics — your privacy is respected.
- Open source and free.

## Download / Build

Z install is distributed as an **unsigned** IPA. Because it is unsigned, iOS will not install it directly — you must sign it yourself (with your own certificate, or on-device via Feather/Zsign) before installing.

To get a build:

1. Go to the **Actions** tab of this repo.
2. Open the **Build Z install (unsigned IPA)** workflow.
3. Download the **`Zinstall-unsigned`** artifact — inside is **`Zinstall-unsigned.ipa`**.
4. Sign it with your certificate / on-device tool, then install.

## How does it work?

Visit the [HOW IT WORKS](./HOW_IT_WORKS.md) page (inherited from Feather).

## Acknowledgements

- [Feather](https://github.com/claration/Feather) - The original project this is forked from.
- [idevice](https://github.com/jkcoxson/idevice) - Backend for builds with this included, used for communication with `installd`.
- [*.backloop.dev](https://backloop.dev/) - localhost with public CA signed SSL certificate
- [Vapor](https://github.com/vapor/vapor) - A server-side Swift HTTP web framework.
- [Zsign](https://github.com/zhlynn/zsign) - Allowing to sign on-device.
- [LiveContainer](https://github.com/LiveContainer/LiveContainer) - Fixes/some help
- [Nuke](https://github.com/kean/Nuke) - Image caching.
- [Asspp](https://github.com/Lakr233/Asspp) - Some code for setting up the http server.
- [plistserver](https://github.com/nekohaxx/plistserver) - Hosted on https://api.palera.in.

## License

This project is licensed under the GPL-3.0 license. See [LICENSE](./LICENSE).
