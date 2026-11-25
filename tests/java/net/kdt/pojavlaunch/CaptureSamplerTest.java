package net.kdt.pojavlaunch;

import java.nio.file.*;
import java.util.ArrayList;
import java.util.List;

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
        assert work("render", "org.lwjgl.opengl.GL32C", "nglDrawElementsBaseVertex").equals("graphics-draw");
        assert work("render", "org.lwjgl.opengl.GL20C", "glDrawBuffers").equals("graphics-driver");
        assert work("render", "com.mojang.blaze3d.platform.GlStateManager", "_glBufferData").equals("graphics-buffer-upload");
        assert work("render", "org.lwjgl.opengl.GL11C", "nglTexSubImage2D").equals("graphics-texture-upload");
        assert work("render", "org.lwjgl.opengl.GL11C", "glGetTexImage").equals("graphics-driver");
        assert work("render", "org.lwjgl.opengl.GL20C", "glLinkProgram").equals("graphics-shader");
        assert work("render", "org.lwjgl.opengl.GL32C", "glClientWaitSync").equals("graphics-sync");
        assert work("render", "org.lwjgl.vulkan.VK10", "nvkCmdBlitImage").equals("graphics-blit");
        assert work("render", "unrecognized.mod.Custom", "glDrawArrays").equals("other");
        assert work("render", "com.mojang.blaze3d.platform.GlStateManager", "_drawElements").equals("graphics-draw");
        assert work("render", "com.mojang.blaze3d.platform.GlStateManager", "_texImage2D").equals("graphics-texture-upload");
        assert work("render", "com.mojang.blaze3d.platform.GlStateManager", "_glBlitFrameBuffer").equals("graphics-blit");
        StackTraceElement[] drainQueue = {
                new StackTraceElement("org.lwjgl.opengl.GL15C", "nglBufferSubData", "", -2),
                new StackTraceElement("com.mojang.blaze3d.systems.RenderSystem", "flipFrame", "", 1)
        };
        assert CaptureSampler.classify("render", Thread.State.RUNNABLE, drainQueue).equals("graphics-buffer-upload");
        StackTraceElement[] drawEntity = {
                new StackTraceElement("org.lwjgl.opengl.GL11C", "nglDrawElements", "", -2),
                new StackTraceElement("net.minecraft.client.renderer.entity.EntityRenderer", "render", "", 1)
        };
        assert CaptureSampler.classify("render", Thread.State.RUNNABLE, drawEntity).equals("entity-rendering");
        assert CaptureSampler.role("C2ME worker #1").equals("c2me-worker");
        assert CaptureSampler.role("C2ME Storage #15").equals("c2me-storage");
        assert CaptureSampler.role("C2ME hardware info") == null;
        assert CaptureSampler.role("c2me-adaptive-feed") == null;
        assert work("c2me-worker", "com.ishland.c2me.opts.worldgen.dfc.common.ast.AstNode", "eval")
                .equals("chunk-generation");
        assert work("c2me-storage", "com.ishland.c2me.rewrites.chunkio.common.C2MEStorageThread", "writeChunk")
                .equals("chunk-io");
        assert work("c2me-worker", "com.ishland.c2me.threading.lighting.common.LightTask", "update")
                .equals("lighting");
        assert work("c2me-worker", "unrecognized.mod.Custom", "method").equals("other");
        assert CaptureSampler.classify("c2me-storage", Thread.State.RUNNABLE, new StackTraceElement[] {
                new StackTraceElement("jdk.internal.misc.Unsafe", "park", "", -2)
        }) == null;
        assert CaptureSampler.role("diorama-baker-1").equals("map-worker");
        assert CaptureSampler.role("Prisma capture sampler") == null;
        assert CaptureSampler.classify("worker", Thread.State.WAITING, new StackTraceElement[0]) == null;
        assert work("worker", "unrecognized.mod.Custom", "method").equals("other");

        Path marker = Paths.get(args[0]);
        Thread render = new Thread(() -> {
            while (running) Thread.yield();
        }, "Render thread");
        Thread c2me = new Thread(() -> {
            while (running) Thread.yield();
        }, "C2ME worker #1");
        Thread storage = new Thread(() -> {
            while (running) Thread.yield();
        }, "C2ME Storage #15");
        List<Long> storagePool = new ArrayList<>(), observed = new ArrayList<>();
        for (long id = 1; id <= 15; id++) storagePool.add(id);
        int cursor = 0;
        for (int round = 0; round < storagePool.size(); round++) {
            cursor = CaptureSampler.rotate(observed, storagePool, cursor, 1);
        }
        assert observed.equals(storagePool);
        Thread idle = new Thread(() -> {
            try { Thread.sleep(30000); } catch (InterruptedException done) { }
        }, "C2ME Storage #1");
        idle.start();
        render.start();
        c2me.start();
        storage.start();
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
            String json = new String(Files.readAllBytes(output), "UTF-8");
            assert json.contains("c2me-worker/other");
            assert json.contains("c2me-storage/other");
            assert !json.contains("c2me-storage/waiting");
        } finally {
            running = false;
            idle.interrupt();
            idle.join();
            render.join();
            c2me.join();
            storage.join();
        }
    }
}
