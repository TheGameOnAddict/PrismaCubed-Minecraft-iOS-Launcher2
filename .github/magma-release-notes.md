This is the iPhone build used for the November 25 full-resolution performance captures. Download **PrismaCubic-f714bf5.ipa** below and open it in your normal sideloading app. Existing profiles can be used with this build.

### What this build includes

- PrismaCubic’s patched Magma renderer, available as **MobileGlues (1.17+)**. Magma now submits draws that reference an animation texture before uploading new data to the same texture. On iPhone this fixed flickering, stretching and disappearing Book of Dragons dragons and ordinary mobs. [Driver patch](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/f714bf5c16a978736a7142a63576c61eac2c49b6/patches/mobilegl-ordered-texture-updates.patch)
- Startup refresh-rate handling, reduced launcher image-cache use during play, and a profile-menu **Performance Test** with a shareable diagnostics ZIP.
- In two 60-second travel captures at 2868 × 1320, with Diorama disabled, the run with Radium and C2ME Forge together averaged **95.9 FPS** versus **75.3 FPS** before adding them. The 99th-percentile frame interval improved from 48 to 34 ms, and intervals over 100 ms fell from 12 to 2. The routes differed. Individual mod contributions and performance on other devices remain unmeasured.

Test configuration: Minecraft 1.20.1, Forge 47.4.28, Java 21.0.8, 2048 MiB heap, shaders off, render distance 8, simulation distance 6. Optimization mods are installed separately into a compatible profile.

IPA SHA-256: `e206bdc8ca59cb0b897a3bf04a9d12f163cbe5a3807b26994e2eb743f0fc7f22`. [Launcher source](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/tree/f714bf5c16a978736a7142a63576c61eac2c49b6) · [Packaging workflow used for these bytes](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/actions/runs/45500370395)
