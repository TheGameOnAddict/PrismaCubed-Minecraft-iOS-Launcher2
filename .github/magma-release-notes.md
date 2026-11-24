Fixes a rendering bug where animated entities could flicker, stretch across the screen, or disappear. Magma now finishes submitting draws that use the current animation texture before uploading the next pose. The original driver failed the texture-ordering regression on two Vulkan implementations. The patched driver passed on both.

### iPhone test

A player verified that Book of Dragons dragons, including the Skrill, and ordinary mobs rendered correctly on an A19 Pro iPhone using **MobileGlues (1.17+)** with Minecraft 1.20.1 and Forge 47.4.28. With shaders off, a 60-second capture recorded 99.6 FPS at the renderer, with three frame intervals over 50 ms. This is a baseline from one session. Shader-enabled play still needs a separate test.

### Install

Download **PrismaCubic-Magma-Entity-Fix.ipa** under **Assets** and open it in your usual sideloading app. You can update over the previous test build using the same signing setup and launch your existing profile.

This is the exact IPA from the successful phone test. It pairs launcher commit `d23a51f` with the patched Magma driver. The launcher's diagnostics ZIP therefore still reports `d23a51f`. [Signed package workflow](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/actions/runs/45444268762) · [Renderer patch](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/blob/bc4ea4243401652feb956ecddd282749be581f1b/patches/mobilegl-ordered-texture-updates.patch)

IPA SHA-256: `1a3ffc974b6e3ffbb24bfed85aa8bcc81167260e9f888e1f0ce987dc7fdfc3de`
