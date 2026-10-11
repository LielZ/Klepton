# Lizenzen der mitgelieferten Binärteile

Ein Toolchain-Paket enthält neben dem Quelltext dieses Repositorys (MIT, siehe `LICENSE`)
vorgebaute Bibliotheken Dritter:

| Teil | Wo im Paket | Lizenz | Text |
|---|---|---|---|
| ANGLE (libEGL, libGLESv2), mit den Änderungen aus `angle-patches/klepton.patch` | `vendor/out/xros`, `vendor/out/xrsim` | BSD-3-Clause | `ANGLE-LICENSE.txt` |
| MoltenVK | `vendor-moltenvk/out` | Apache-2.0 | `MoltenVK-LICENSE.txt` |

Dazu kommt Quelltext Dritter, der mit der Runtime übersetzt wird:

| Teil | Wo im Paket | Lizenz | Text |
|---|---|---|---|
| Fossilize (Valve), Stand 556da9f, nur die Bibliotheksquellen | `vendor-fossilize` | MIT | `vendor-fossilize/LICENSE` |
| RapidJSON (in Fossilize enthalten) | `vendor-fossilize/rapidjson` | MIT | `vendor-fossilize/rapidjson/license.txt` |
| miniz (in Fossilize enthalten) | `vendor-fossilize/miniz` | MIT | `vendor-fossilize/miniz/LICENSE` |
| Vulkan-Header (Khronos, in Fossilize enthalten) | `vendor-fossilize/khronos` | Apache-2.0 oder MIT | Kopf jeder Datei |

Das Aufzeichnen und Vorab-Bauen der Vulkan-Pipelines (`runtime/gfx/kl_fossilize.cpp`,
`runtime/gfx/kl_vk_pipe_hooks.h`, `tools/alyx_pipelines.py`) folgt Glovebox
(github.com/glovebox-vr/glovebox, MIT); die Dateien nennen das jeweils im Kopf.

Die Steam-Anbindung der Spiel-App (`visionos/SteamCloudKit`, Anmeldung und Steam-Cloud-Spielstände) besteht aus
Teilen von Glovebox' `SteamLauncherKit` (MIT, `visionos/SteamCloudKit/LICENSE-Glovebox.txt`); was übernommen und
was geändert ist, steht in `visionos/SteamCloudKit/README.md`.

Der Patch gegenüber dem ANGLE-Quelltext liegt vollständig in `angle-patches/klepton.patch`.
Spielinhalte und aus ihnen übersetzte Bibliotheken sind nie Teil eines Pakets.
