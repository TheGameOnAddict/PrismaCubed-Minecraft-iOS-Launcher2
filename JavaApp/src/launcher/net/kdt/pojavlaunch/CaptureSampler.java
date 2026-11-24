package net.kdt.pojavlaunch;

import java.io.IOException;
import java.io.InputStream;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadInfo;
import java.lang.management.ThreadMXBean;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.TimeUnit;

/** Test-launch-only snapshots of selected game threads. Exports fixed labels, never raw stacks. */
final class CaptureSampler implements Runnable {
    private static final long PERIOD_MS = 50;
    private static final int DURATION_MS = 60000;
    private static final int MAX_WORKERS = 6;
    private static final int MAX_MAP_THREADS = 2;
    private final Path marker;
    private final StringBuilder samples = new StringBuilder();
    private final List<Long> primary = new ArrayList<>(), workers = new ArrayList<>(), maps = new ArrayList<>();
    private int workerCursor, mapCursor, rounds;
    private long startMs;

    private CaptureSampler(Path marker) {
        this.marker = marker;
    }

    static void start(String markerName) {
        Path path = Paths.get(markerName);
        if (!path.isAbsolute()) return;
        Thread thread = new Thread(new CaptureSampler(path), "Prisma capture sampler");
        thread.setDaemon(true);
        thread.start();
    }

    private long readStart() throws IOException {
        if (!Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS)) return 0;
        long value = 0;
        // Native writes one Unix timestamp (ms) atomically. Refuse arbitrary marker contents.
        try (InputStream in = Files.newInputStream(marker, LinkOption.NOFOLLOW_LINKS)) {
            for (int i = 0; i < 13; i++) {
                int digit = in.read();
                if (digit < '0' || digit > '9') return 0;
                value = value * 10 + digit - '0';
            }
            return in.read() == '\n' && in.read() == -1 ? value : 0;
        }
    }

    @Override public void run() {
        try {
            while ((startMs = readStart()) == 0) Thread.sleep(400);
            long delay = startMs - System.currentTimeMillis();
            if (delay > 10000 || delay <= -DURATION_MS) return;
            if (delay > 0) Thread.sleep(delay);
            ThreadMXBean bean = ManagementFactory.getThreadMXBean();
            long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(startMs + DURATION_MS - System.currentTimeMillis());
            long nextRefresh = 0, nextSave = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
            String status = "completed";
            boolean first = true;
            while (System.nanoTime() < deadline && rounds < DURATION_MS / PERIOD_MS) {
                long begin = System.nanoTime(), timeMs = System.currentTimeMillis();
                if (first || begin >= nextRefresh) {
                    first = false;
                    if (!Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS)) { status = "interrupted"; break; }
                    refresh(bean);
                    nextRefresh = begin + TimeUnit.SECONDS.toNanos(1);
                }
                long[] ids = select();
                Set<String> work = new LinkedHashSet<>();
                if (ids.length > 0) {
                    for (ThreadInfo info : bean.getThreadInfo(ids, 32)) {
                        if (info == null) continue; // Thread exited after inventory.
                        String role = role(info.getThreadName());
                        if (role == null) continue;
                        String category = classify(role, info.getThreadState(), info.getStackTrace());
                        if (category != null) work.add(role + "/" + category);
                    }
                }
                long nanos = System.nanoTime() - begin;
                long probeMs = (nanos + 999999L) / 1000000L;
                if (rounds++ > 0) samples.append(',');
                samples.append("{\"atMs\":").append(timeMs + nanos / 2000000L)
                       .append(",\"probeMs\":").append(probeMs).append(",\"work\":[");
                boolean comma = false;
                for (String label : work) {
                    if (comma) samples.append(',');
                    samples.append('"').append(label).append('"');
                    comma = true;
                }
                samples.append("]}");
                if (System.nanoTime() >= nextSave) {
                    write("recording");
                    nextSave = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
                }
                // Never issue catch-up bursts when a safepoint delayed the sampler.
                Thread.sleep(PERIOD_MS);
            }
            write(status);
        } catch (IOException | InterruptedException | RuntimeException | LinkageError unavailable) {
            try {
                if (startMs != 0) write("unavailable");
            } catch (IOException | RuntimeException ignored) { }
        }
    }

    private void refresh(ThreadMXBean bean) {
        primary.clear(); workers.clear(); maps.clear();
        for (ThreadInfo info : bean.getThreadInfo(bean.getAllThreadIds(), 0)) {
            if (info == null) continue;
            String role = role(info.getThreadName());
            if ("render".equals(role) || "server".equals(role)) {
                if (primary.size() < 3) primary.add(info.getThreadId());
            } else if ("map-worker".equals(role)) maps.add(info.getThreadId());
            else if ("worker".equals(role)) workers.add(info.getThreadId());
        }
    }

    private long[] select() {
        List<Long> selected = new ArrayList<>(primary);
        mapCursor = rotate(selected, maps, mapCursor, MAX_MAP_THREADS);
        workerCursor = rotate(selected, workers, workerCursor, MAX_WORKERS);
        long[] ids = new long[selected.size()];
        for (int i = 0; i < ids.length; i++) ids[i] = selected.get(i);
        return ids;
    }

    private static int rotate(List<Long> out, List<Long> candidates, int cursor, int limit) {
        int size = candidates.size();
        if (size == 0) return 0;
        cursor %= size;
        for (int i = 0; i < Math.min(size, limit); i++) {
            out.add(candidates.get(cursor));
            cursor = (cursor + 1) % size;
        }
        return cursor;
    }

    static String role(String name) {
        name = name.toLowerCase(Locale.ROOT);
        if (name.equals("render thread") || name.equals("client thread")) return "render";
        if (name.equals("server thread")) return "server";
        if (name.contains("journeymap") || name.contains("xaero") || name.contains("diorama")) return "map-worker";
        if (name.startsWith("worker-") || name.startsWith("forkjoinpool-") || name.startsWith("chunk")
                || name.startsWith("io-worker") || name.contains("light engine") || name.startsWith("dh-")
                || name.contains("embeddium") || name.contains("sodium")) return "worker";
        return null;
    }

    static String classify(String role, Thread.State state, StackTraceElement[] stack) {
        boolean primary = role.equals("render") || role.equals("server");
        if (state != Thread.State.RUNNABLE || stack.length == 0) return primary ? "waiting" : null;
        StackTraceElement top = stack[0];
        if (top.isNativeMethod() && ("park".equals(top.getMethodName()) || "wait".equals(top.getMethodName())
                || "sleep".equals(top.getMethodName()) || "poll".equals(top.getMethodName())))
            return primary ? "waiting" : null;

        boolean graphics = false;
        for (StackTraceElement frame : stack) {
            String c = frame.getClassName(), m = frame.getMethodName();
            if (c.startsWith("org.lwjgl.opengl.") || c.startsWith("org.lwjgl.vulkan.") || c.startsWith("org.lwjgl.glfw.")
                    || c.startsWith("com.mojang.blaze3d.platform.GlStateManager") || c.startsWith("com.mojang.blaze3d.systems.RenderSystem")) {
                if (m.contains("SwapBuffers") || m.equals("flipFrame")) return "graphics-present";
                graphics = true;
            }
            if (c.startsWith("journeymap.") || c.startsWith("xaero.") || c.startsWith("dev.diorama.")) return "map-work";
            if (c.startsWith("net.minecraft.world.level.lighting.") || c.startsWith("net.minecraft.world.chunk.light.")
                    || c.contains("ThreadedLevelLightEngine") || c.contains("ServerLightingProvider")
                    || c.contains(".starlight.common.light.") || id(c, "3568") || id(c, "3558") || id(c, "3560") || id(c, "3227")) return "lighting";
            if (c.contains("ChunkRenderDispatcher$RenderChunk$RebuildTask") || c.contains("ChunkBuilder$BuiltChunk$RebuildTask")
                    || c.contains(".render.chunk.compile.") || c.contains(".render.chunk.tasks.")
                    || id(c, "846$class_851$class_4578")) return "chunk-meshing";
            if (c.startsWith("net.minecraft.world.level.levelgen.") || c.startsWith("net.minecraft.world.gen.")
                    || c.contains(".level.chunk.ChunkGenerator") || id(c, "3754") || id(c, "2794")) return "chunk-generation";
            if (c.startsWith("net.minecraft.world.level.chunk.storage.") || c.startsWith("net.minecraft.world.storage.")
                    || id(c, "2852") || id(c, "2861") || id(c, "4698")) return "chunk-io";
            if (c.startsWith("net.minecraft.server.level.ChunkMap") || c.startsWith("net.minecraft.server.level.ServerChunkCache")
                    || c.startsWith("net.minecraft.server.level.ChunkHolder") || id(c, "3898")) return "chunk-loading";
            if (c.startsWith("net.minecraft.client.renderer.entity.") || c.startsWith("net.minecraft.client.render.entity.")
                    || c.startsWith("net.minecraft.client.renderer.blockentity.") || c.startsWith("software.bernie.geckolib.renderer.")
                    || id(c, "898") || id(c, "897") || id(c, "922")) return "entity-rendering";
            if (c.contains(".level.entity.EntityTickList") || id(c, "5574") ||
                    ((c.startsWith("net.minecraft.world.entity.") || c.startsWith("net.minecraft.entity.")
                    || id(c, "1297") || id(c, "1309")) && (m.equals("tick") || m.equals("aiStep")
                    || m.equals("m_8119_") || m.equals("m_8107_") || m.equals("method_5773")))) return "entity-ticking";
        }
        return graphics ? "graphics-driver" : "other";
    }

    // Intermediary owners from 1.20.1 Yarn. Match inner classes while excluding numeric prefixes.
    private static boolean id(String owner, String id) {
        if (!owner.startsWith("net.minecraft.class_")) return false;
        int prefix = "net.minecraft.class_".length();
        int end = prefix + id.length();
        return owner.startsWith(id, prefix) && (owner.length() == end || owner.charAt(end) == '$');
    }

    private void write(String status) throws IOException {
        String json = "{\"schema\":1,\"status\":\"" + status + "\",\"captureStartEpochMs\":" + startMs
                + ",\"requestedPeriodMs\":" + PERIOD_MS + ",\"rounds\":" + rounds
                + ",\"samples\":[" + samples + "]}";
        Path out = marker.resolveSibling(marker.getFileName().toString() + ".json");
        Path temp = Files.createTempFile(out.getParent(), ".java-work-", ".tmp");
        try {
            Files.write(temp, json.getBytes(StandardCharsets.UTF_8));
            try {
                Files.move(temp, out, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temp, out, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            Files.deleteIfExists(temp);
        }
    }
}
