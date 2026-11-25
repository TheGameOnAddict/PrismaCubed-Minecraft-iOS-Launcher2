For everyday play, use the [phone-tested performance checkpoint](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/releases/tag/perf-checkpoint-2026-11-25). This optional iPhone build is for anyone who wants the more detailed capture or wants to try the foreground rendering change. Its frame-rate impact on a phone is still unmeasured.

Download **PrismaCubic-62a02c9.ipa** under Assets.

- Foreground rendering skips the mutex used to park the renderer when iOS backgrounds the app. The macOS test checks both foreground calls and suspension/resume cycles.
- Diagnostic captures recognize C2ME generation workers and storage threads. Slow-frame reports can identify draw calls, buffer and texture uploads, shader work, synchronization and framebuffer blits when those calls appear in a sampled Java stack. Each label includes how many sampling rounds observed it.
- The IPA includes the same Magma driver as the performance checkpoint. The package verification checks its bytes against that build.

[Launcher changes](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/compare/f714bf5...62a02c9) · [iPhone build and tests](https://github.com/TheGameOnAddict/PrismaCubic-Minecraft-iOS-Launcher2/actions/runs/45674987685)

IPA SHA-256 `b9649720a21e58f9b962d593de645341b0a7fcf6ef382352644c792420570908`
