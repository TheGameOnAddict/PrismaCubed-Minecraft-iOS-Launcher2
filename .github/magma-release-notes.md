Download **PrismaCubic-e5dd5d4.ipa** under Assets. This test build carries the Magma driver previously verified on dragons and ordinary mobs. The [phone-tested performance checkpoint](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/tag/perf-checkpoint-2026-11-25) is also available.

**Cap at 120 FPS** is on by default in the renderer settings. It limits Minecraft to the lower of 120 FPS and the display’s maximum refresh rate. Turn it off and relaunch to try uncapped rendering in regular gameplay with supported Magma. Low Power Mode keeps regular presentation. The HUD shows render FPS and presentation rate separately when the uncapped Magma path is active. Visible updates depend on display refresh. The separate 60-second GPU benchmark remains available in a Magma Performance Test launch with the cap off.

**Upscaling** now shows the game’s internal rendering scale beside each preset. For native resolution use **Output resolution 100%** and **Upscaling Off (100%)**. To try a lighter load at the same output size, select **Quality (67%)** and relaunch. That percentage applies to both width and height.

The iPhone build checks the presentation scheduler, GPU fences, frame counts, diagnostic sampler, arm64 executable, shared Java launcher and bundled resources. On-device gameplay rates for this version are pending.

[Source changes](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/compare/ed583a1...e5dd5d4) · [Build and tests](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/actions/runs/45681221563)

IPA SHA-256 `8fa353046a0f0351f34b6823c15ed95e15cde3ffb58cf06000a7a9bd9900e93c`
