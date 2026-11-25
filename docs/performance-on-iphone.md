# Optimization mods tested on iPhone

For **Minecraft 1.20.1 with Forge 47.4.28**, the best full-resolution travel run so far used **Embeddium, FerriteCore, ModernFix, Radium and C2ME Forge** together. Choose the Forge build matching your Minecraft version when adding mods to a profile. The launcher IPA and the mods are separate downloads. [Tested launcher release](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/tag/perf-checkpoint-2026-11-25)

| Mod | Tested version | What the phone test tells us |
| --- | --- | --- |
| Embeddium | [0.3.31+mc1.20.1](https://modrinth.com/mod/embeddium/version/UTbfe5d1) | Terrain renderer used in all three captures, including the fastest run on Magma. |
| FerriteCore | [6.0.1 Forge](https://modrinth.com/mod/ferrite-core/version/DG5Fn9Sz) | Memory optimization mod present in all three captures. Its individual memory savings are unmeasured here. |
| ModernFix | [5.28.0 for Forge 1.20.1](https://www.curseforge.com/minecraft/mc-mods/modernfix/files/9685369) | Loaded alongside Embeddium and FerriteCore in all three captures. Its individual speedup is unmeasured here. |
| Radium | [0.12.4+git.26c9d8e](https://modrinth.com/mod/radium/version/n947JjJH) | Forge port of Lithium for game logic. Added together with C2ME Forge for the third capture. |
| C2ME Forge | [0.2.0-forge.9.9.6-all](https://www.curseforge.com/minecraft/mc-mods/concurrent-chunk-management-engine-forge/files/9387498) | Chunk processing mod tested alongside Radium. The log reported one configured worker on this phone. |

## Full-resolution results while moving

Each capture lasted 60 seconds on the same A19 Pro iPhone at 2868 × 1320, with Magma, shaders off, Java 21.0.8, a 2048 MiB heap, render distance 8 and simulation distance 6. The 99th-percentile column gives the time within which 99% of frame intervals finished. The last column counts visible hitches that lasted longer than a tenth of a second.

| Profile configuration | Average FPS | 99th-percentile frame interval¹ | Intervals over 100 ms |
| --- | ---: | ---: | ---: |
| Base pack with Diorama | 32.1 | 153 ms | 50 |
| Diorama disabled | 75.3 | 48 ms | 12 |
| Diorama disabled, Radium and C2ME Forge added | 95.9 | 34 ms | 2 |

¹ Frame interval upper bound from the capture histogram. Lower is better.

Diorama’s map workers were active during the first capture. If you use Diorama and see hitches while exploring, it is worth trying the same area with it disabled. The routes and loaded chunks differed across these runs, and Radium and C2ME were added together. These measurements describe how the complete configurations played. Isolating a gain for either mod would require a matched comparison.

## Why the mobs stopped stretching

In this build, selecting **MobileGlues (1.17+)** can load **Magma**. The runtime renderer string or the in-game renderer HUD tells you what actually loaded. PrismaCubic ships a custom build of the Magma/MobileGL Core Vulkan backend from Amethyst iOS MyRemastered, pinned to upstream commit `874b9e8`. [Upstream source](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/tree/874b9e8af7b74f886e97456ac2b82dce59baf406/Natives/external/MobileGL) · [PrismaCubic build recipe](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/f714bf5c16a978736a7142a63576c61eac2c49b6/scripts/build_pinned_mobilegl.sh)

Minecraft mods can draw an entity, overwrite an animation texture, then draw the next entity using that same texture. Magma could send the second upload to the GPU ahead of the first queued draw. That draw could then read the next pose’s data, which showed up on screen as flickering, stretched geometry or a disappearing mob.

PrismaCubic tracks textures used by pending draws. When the game rewrites one, Magma submits the earlier work before the new upload can overtake it. Unrelated uploads can still be batched. A regression test checks the output of two consecutive draws that use different data in the same texture. On iPhone the tester confirmed clean rendering on the Skrill, other Book of Dragons dragons and ordinary mobs. [Driver patch](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/f714bf5c16a978736a7142a63576c61eac2c49b6/patches/mobilegl-ordered-texture-updates.patch) · [Regression test](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/f714bf5c16a978736a7142a63576c61eac2c49b6/patches/mobilegl-ordered-texture-updates-test.patch) · [Original device-tested release](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/tag/magma-entity-fix-2026-11-24)

## Measuring render FPS above 120

The November 25 iPhone log showed that Magma could present only in FIFO mode, which paces visible frames to the display. The experimental build can measure how fast the GPU finishes real frames at your current resolution. It shows a preview up to 30 times a second during the measurement. [Download the experimental benchmark IPA](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/download/test-magma-throughput-ed583a1/PrismaCubic-ed583a1.ipa)

1. Use the **MobileGlues (1.17+)** renderer with the launcher's VSync lock disabled. Open the profile’s **… → Performance Test → Test Launch**.
2. Enter the world and open the in-game gear. Choose **Benchmark Render FPS → Start Benchmark**. The option appears when the launcher detects its supported Magma backend.
3. After 60 seconds, the result shows GPU-completed frames per second, preview swaps per second, and the panel’s maximum Hz. Open **Render Benchmark Result** in the gear to read it again. The diagnostics ZIP includes a plain-text copy in `render-throughput.txt`.

A value above 120 means the game and GPU completed more than 120 frames per second in that scene. Each measured frame waits for GPU completion, which can reduce throughput compared with overlapping frames in ordinary play. Use **Record 60 Seconds** when you want to measure the frame pacing you actually see while playing.

## Performance backlog

- [ ] **Investigate optional frame generation at full resolution.** Start with MetalFX frame interpolation on an iPhone that reports support. It takes two rendered images plus depth and motion vectors. Check whether Magma can expose the needed textures through MoltenVK and whether Minecraft or a companion mod can supply accurate motion for independently moving mobs. Composite the HUD separately so text and the crosshair stay sharp. [Apple’s frame interpolation overview](https://developer.apple.com/videos/play/wwdc2025/211/?time=437) · [MetalFX device support query and texture inputs](https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor)

  First test a steady 60 rendered FPS targeting 120 displayed FPS. Record both rates, input-to-display latency, GPU time, memory and thermal behavior. Inspect fast camera pans and the Skrill’s wings for ghosting. Frame generation can smooth motion between real frames. A long chunk-generation stall or a delayed game tick still needs its own fix.
