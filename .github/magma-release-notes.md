Download **PrismaCubic-ed583a1.ipa** under Assets to try the optional Magma render benchmark. For everyday play, the [phone-tested performance checkpoint](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/tag/perf-checkpoint-2026-11-25) remains available.

1. With Magma selected, choose **Performance Test → Test Launch** from the profile menu and enter your world. For a throughput measurement, set Minecraft’s FPS limit to Unlimited and disable VSync in the game settings.
2. Open the in-game gear, choose **Benchmark Render FPS**, then **Start Benchmark**. Recording begins after three seconds and runs for one minute.
3. Choose **Render Benchmark Result** from the gear to see GPU-completed frames per second, preview swaps per second and the panel’s maximum refresh rate. The profile’s diagnostics ZIP includes the result.

Game frames render at your chosen resolution. The launcher waits for a GPU fence each frame and updates the visible preview at most 30 times per second. The GPU rate can exceed the panel rate when the device, scene and game settings allow it. Waiting for each fence changes CPU/GPU overlap, so compare readings taken in this same benchmark mode. Use the ordinary capture for gameplay frame pacing and Java hitch details. The launcher restores regular presentation after the test, when you stop it, or when it loses foreground focus.

This build uses the byte-identical, mob-tested Magma driver from the checkpoint. Device measurements for this benchmark are pending. The package workflow checks the fence and frame counters, hitch summaries, arm64 binary, signature and bundled translations.

[Source changes](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/compare/62a02c9...ed583a1) · [iPhone build and tests](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/actions/runs/45676977215)

IPA SHA-256 `326809c2f2d662952a74bad6e21faf69052fe7d9b9f7d89caa8d6235767b64e7`
