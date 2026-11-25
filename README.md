<p align="center"><img src="https://raw.githubusercontent.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/aea7b020b34dc14a45061861713c8eddb74863b7/Natives/Assets.xcassets/CubicBrand.imageset/cube.svg" width="72" height="72" alt=""></p>
<h1 align="center">PrismaCubic</h1>
<p align="center">Play Minecraft: Java Edition on iPhone and iPad. Give each modpack its own profile, manage its mods, and choose its renderer.</p>
<p align="center"><a href="https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/actions/workflows/development.yml?query=branch%3Afeature%2Fprismacubic-ui+is%3Asuccess">iOS test builds</a> · <a href="https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/tree/feature/prismacubic-ui">Development branch</a> · <a href="https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/3db337429cf7b1448682cb7cc66df7543d9f6de4/README.md#original-chinese-readme">中文上游说明</a></p>

## Try the new gameplay settings

Open **Settings → Renderer** to change **Cap at 120 FPS** or **Upscaling**, then launch your profile with **Play**. The cap starts on. Turn it off to let the patched Magma renderer run ahead of the display when the scene is light enough. In a 60-second A19 Pro test at 1912 × 880, the pack averaged 107.7 FPS with the cap off. Rendering rarely ran ahead of presentation. [Download the test IPA](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/download/test-gameplay-settings-e5dd5d4/PrismaCubic-e5dd5d4.ipa) · [How to try upscaling](docs/performance-on-iphone.md#trying-upscaling)

**Better MC [Forge] BMC4 test build.** Forge 47.4.20 rejected a mod requiring OpenGL 3.2 because its startup window reported Magma as OpenGL 0.0. This build fixes the version query. Launch your existing Better MC profile with Magma to test it on iPhone. [Download the Better MC test IPA](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/download/test-bettermc-gl-f3bcab1/PrismaCubic-f3bcab1.ipa)

## Tested iPhone build

**November 25 performance checkpoint.** This build includes PrismaCubic’s patched Magma renderer and the in-game performance capture. On an A19 Pro iPhone, a full-resolution Forge pack averaged **95.9 FPS** while moving with Radium and C2ME Forge enabled. The run still had two frame intervals over 100 ms. [Download the tested IPA](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/download/perf-checkpoint-2026-11-25/PrismaCubic-f714bf5.ipa) · [Checkpoint notes](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/tag/perf-checkpoint-2026-11-25)

**Choosing mods or a renderer?** Start with the exact Forge builds tested on iPhone. The guide includes frame timings, the Diorama comparison, and how PrismaCubic fixed Magma’s flickering and stretching mobs. [Tested optimization mods and renderer notes](docs/performance-on-iphone.md)

## Install a development build

1. Sign in to GitHub, open **iOS test builds** above, and choose a successful run.
2. Under **Artifacts**, download **com.prisma-devs.prisma-ios.ipa**. Unzip the download and open the IPA in your sideloading app. The separate TIPA is for TrollStore.
3. Enable JIT for PrismaCubic using the method supported by your iOS version and signing setup. [Device and JIT setup guide](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/3db337429cf7b1448682cb7cc66df7543d9f6de4/README.md#quick-start)

## Set up a pack

- **My Profiles** keeps your worlds, mods, and profile options together. Compatible Forge packs can reuse a verified runtime.
- **Browse Modpacks** installs packs from the launcher. **Import** accepts a pack file or a CurseForge profile share code.
- **Downloads** in the title bar shows what is installing. Open a job to read the log during an install or after it finishes or fails.
- **Profile Options** lives under the profile’s **…** menu. Change the picture, edit the description, or choose a renderer for that pack. Mithril and TGLMT are experimental. Compatibility with Forge mods and shaders is being tested.

## Check performance on your device

The in-game HUD can show which renderer Minecraft actually loaded beside FPS and memory. Open a profile’s **…** menu to start a **Performance Test**. After playing, choose **Export Diagnostics ZIP** from the profile menu to share the frame timings, renderer details, and available logs from that run.

## Credits and license

PrismaCubic builds on Prisma 2 and Amethyst iOS MyRemastered. The launcher is distributed under the GNU Affero General Public License v3. Third-party components retain their respective licenses. [Prisma 2](https://github.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2) · [Amethyst](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered) · [License](LICENSE) · [Upstream credits and component licenses](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/3db337429cf7b1448682cb7cc66df7543d9f6de4/README.md#third-party-components)

This independent community project is unaffiliated with Mojang or Microsoft. The upstream regional distribution notice applies. [Regional notice](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/3db337429cf7b1448682cb7cc66df7543d9f6de4/README.md)
