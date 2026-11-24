package net.kdt.pojavlaunch;

import java.nio.file.*;

public class CaptureSamplerTest {
    private static volatile boolean running = true;

    static String work(String role, String owner, String method) {
        StackTraceElement[] stack = {new StackTraceElement(owner, method, "", 1)};
        return CaptureSampler.classify(role, Thread.State.RUNNABLE, stack);
    }

    public static void main(String[] args) throws Exception {
        assert work("worker", "net.minecraft.world.level.levelgen.NoiseBasedChunkGenerator", "m_123_").equals("chunk-generation");
        assert work("server", "net.minecraft.world.entity.Entity", "m_8119_").equals("entity-ticking");
        assert work("server", "net.minecraft.world.entity.Entity", "getId").equals("other");
        assert work("render", "net.minecraft.class_898", "method_3954").equals("entity-rendering");
        assert work("render", "net.minecraft.class_8980", "m").equals("other");
        assert work("worker", "net.minecraft.class_3568", "method").equals("lighting");
        assert work("worker", "net.minecraft.class_846$class_851$class_4578", "method").equals("chunk-meshing");
        assert work("map-worker", "dev.diorama.DioramaClient", "tick").equals("map-work");
        assert work("render", "org.lwjgl.glfw.GLFW", "glfwSwapBuffers").equals("graphics-present");
        assert CaptureSampler.role("diorama-baker-1").equals("map-worker");
        assert CaptureSampler.role("Prisma capture sampler") == null;
        assert CaptureSampler.classify("worker", Thread.State.WAITING, new StackTraceElement[0]) == null;
        assert work("worker", "unrecognized.mod.Custom", "method").equals("other");

        Path marker = Paths.get(args[0]);
        Thread render = new Thread(() -> {
            while (running) Thread.yield();
        }, "Render thread");
        render.start();
        try {
            CaptureSampler.start(marker.toString());
            Thread.sleep(700);
            assert !Files.exists(Paths.get(marker.toString() + ".json"));
            boolean interrupt = "interrupt".equals(args[1]);
            long epoch = System.currentTimeMillis() - (interrupt ? 0 : 58000);
            Files.write(marker, (epoch + "\n").getBytes("US-ASCII"));
            if (interrupt) {
                Thread.sleep(1700);
                Files.delete(marker);
            }
            Path output = Paths.get(marker.toString() + ".json");
            long stop = System.nanoTime() + 7000000000L;
            while (!Files.exists(output) && System.nanoTime() < stop) Thread.sleep(30);
            assert Files.exists(output);
        } finally { running = false; render.join(); }
    }
}
