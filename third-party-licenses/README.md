# Lizenzen der mitgelieferten Binärteile

Ein Toolchain-Paket enthält neben dem Quelltext dieses Repositorys (MIT, siehe `LICENSE`)
vorgebaute Bibliotheken Dritter:

| Teil | Wo im Paket | Lizenz | Text |
|---|---|---|---|
| ANGLE (libEGL, libGLESv2), mit den Änderungen aus `angle-patches/klepton.patch` | `vendor/out/xros`, `vendor/out/xrsim` | BSD-3-Clause | `ANGLE-LICENSE.txt` |
| MoltenVK | `vendor-moltenvk/out` | Apache-2.0 | `MoltenVK-LICENSE.txt` |

Der Patch gegenüber dem ANGLE-Quelltext liegt vollständig in `angle-patches/klepton.patch`.
Spielinhalte und aus ihnen übersetzte Bibliotheken sind nie Teil eines Pakets.
