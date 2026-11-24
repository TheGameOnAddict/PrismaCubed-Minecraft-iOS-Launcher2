package dev.prismacubic.entityprobe;

import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.util.function.Consumer;
import org.lwjgl.opengl.GL;
import org.lwjgl.opengl.GLCapabilities;
import org.lwjgl.system.MemoryStack;

import static org.lwjgl.opengl.GL11C.*;
import static org.lwjgl.opengl.GL12C.*;
import static org.lwjgl.opengl.GL13C.*;
import static org.lwjgl.opengl.GL15C.*;
import static org.lwjgl.opengl.GL20C.*;
import static org.lwjgl.opengl.GL21C.*;
import static org.lwjgl.opengl.GL30C.*;
import static org.lwjgl.opengl.GL33C.*;
import static org.lwjgl.opengl.GL42C.GL_TRANSFORM_FEEDBACK_ACTIVE;
import static org.lwjgl.opengl.GL41C.glGetFloati_v;
import static org.lwjgl.opengl.GL41C.glViewportIndexedf;

/** One-shot renderer diagnostic. Invoke on the render thread with a current OpenGL context. */
public final class EntityDrawProbe {
    private EntityDrawProbe() {}

    private static final int WIDTH = 32, HEIGHT = 16, STRIDE = 12;
    private static final int ORANGE = 0xff6000ff, BLUE = 0x40c8ffff, BLACK = 0x000000ff;
    private static final String VERTEX = """
        #version 130
        in vec2 position;
        in vec4 color;
        uniform mat4 pose;
        uniform sampler2D bones;
        uniform int useBones;
        out vec4 rgba;
        void main() {
            vec4 vertex = vec4(position, 0, 1);
            if (useBones != 0) {
                mat4 bone = mat4(texelFetch(bones, ivec2(0,0), 0),
                                 texelFetch(bones, ivec2(1,0), 0),
                                 texelFetch(bones, ivec2(2,0), 0),
                                 texelFetch(bones, ivec2(3,0), 0));
                vertex = bone * vertex;
            }
            vec2 pixel = (pose * vertex).xy;
            gl_Position = vec4(pixel / vec2(16, 8) - vec2(1), 0, 1);
            rgba = color;
        }
        """;
    private static final String FRAGMENT = """
        #version 130
        in vec4 rgba;
        out vec4 result;
        void main() { result = rgba; }
        """;

    private enum Update { INTERLEAVED_VERTEX_BUFFER, PER_DRAW_MATRIX_UNIFORM, FLOAT_BONE_TEXTURE }

    public static void run(Consumer<String> report) {
        try {
            GLCapabilities caps = GL.getCapabilities();
            if (!caps.OpenGL30) {
                report.accept("Entity draw probe skipped: desktop OpenGL 3.0 is required.");
                return;
            }
            if ((caps.OpenGL40 || caps.GL_ARB_transform_feedback2) && glGetBoolean(GL_TRANSFORM_FEEDBACK_ACTIVE)) {
                report.accept("Entity draw probe skipped: transform feedback is active.");
                return;
            }
            report.accept("Entity draw probe started: GL_RENDERER=" + glGetString(GL_RENDERER)
                    + ", GL_VERSION=" + glGetString(GL_VERSION));
            try (MemoryStack stack = MemoryStack.stackPush()) {
                State state = new State(caps, stack);
                Draw draw = new Draw(stack);
                try {
                    state.prepare();
                    draw.setup();
                    for (Update update : Update.values()) {
                        report.accept(update + ": starting offscreen draws");
                        String result = draw.check(update, false);
                        report.accept(update + ": " + result);
                        if (!result.equals("PASS")) {
                            report.accept(update + ": repeating with CPU pixel readback between draws");
                            report.accept(update + " synchronized reference: " + draw.check(update, true));
                        }
                    }
                } finally {
                    try { state.restore(); } finally { draw.delete(); }
                }
            }
        } catch (RuntimeException | LinkageError ex) {
            report.accept("Entity draw probe could not finish: " + ex);
        }
    }

    /** Create only private objects; Minecraft's buffers, textures and shader uniforms are never edited. */
    private static final class Draw {
        private final ByteBuffer vertices, pixels, referencePixel;
        private final FloatBuffer matrix, clearColor;
        private int program, vao, vbo, fbo, target, bones, pose, useBones;
        Draw(MemoryStack stack) {
            vertices = stack.malloc(4 * STRIDE);
            pixels = stack.malloc(WIDTH * HEIGHT * 4);
            referencePixel = stack.malloc(4);
            matrix = stack.mallocFloat(16);
            clearColor = stack.floats(0f, 0f, 0f, 1f);
        }
        void setup() {
            program = glCreateProgram();
            int vertex = 0, fragment = 0;
            try {
                vertex = compile(GL_VERTEX_SHADER, VERTEX);
                fragment = compile(GL_FRAGMENT_SHADER, FRAGMENT);
                glAttachShader(program, vertex);
                glAttachShader(program, fragment);
                glBindAttribLocation(program, 0, "position");
                glBindAttribLocation(program, 1, "color");
                glBindFragDataLocation(program, 0, "result");
                glLinkProgram(program);
                if (glGetProgrami(program, GL_LINK_STATUS) == GL_FALSE)
                    throw new IllegalStateException("Probe program link failed: " + glGetProgramInfoLog(program));
            } finally {
                if (vertex != 0) glDeleteShader(vertex);
                if (fragment != 0) glDeleteShader(fragment);
            }
            glUseProgram(program);
            pose = glGetUniformLocation(program, "pose");
            useBones = glGetUniformLocation(program, "useBones");
            int sampler = glGetUniformLocation(program, "bones");
            if (pose < 0 || sampler < 0 || useBones < 0) throw new IllegalStateException("Missing probe uniform");
            glUniform1i(sampler, glGetInteger(GL_ACTIVE_TEXTURE) - GL_TEXTURE0);
            vao = glGenVertexArrays();
            glBindVertexArray(vao);
            vbo = glGenBuffers();
            glBindBuffer(GL_ARRAY_BUFFER, vbo);
            glBufferData(GL_ARRAY_BUFFER, 4L * STRIDE, GL_STREAM_DRAW);
            glVertexAttribPointer(0, 2, GL_FLOAT, false, STRIDE, 0L);
            glVertexAttribPointer(1, 4, GL_UNSIGNED_BYTE, true, STRIDE, 8L);
            glEnableVertexAttribArray(0);
            glEnableVertexAttribArray(1);

            target = glGenTextures();
            glBindTexture(GL_TEXTURE_2D, target);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, WIDTH, HEIGHT, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0L);
            fbo = glGenFramebuffers();
            glBindFramebuffer(GL_FRAMEBUFFER, fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, target, 0);
            glDrawBuffer(GL_COLOR_ATTACHMENT0);
            glReadBuffer(GL_COLOR_ATTACHMENT0);
            int status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            if (status != GL_FRAMEBUFFER_COMPLETE)
                throw new IllegalStateException("Probe framebuffer incomplete: 0x" + Integer.toHexString(status));
            bones = glGenTextures();
            glBindTexture(GL_TEXTURE_2D, bones);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, 4, 1, 0, GL_RGBA, GL_FLOAT, 0L);
        }
        private static int compile(int type, String source) {
            int shader = glCreateShader(type);
            glShaderSource(shader, source);
            glCompileShader(shader);
            if (glGetShaderi(shader, GL_COMPILE_STATUS) == GL_FALSE) {
                String log = glGetShaderInfoLog(shader);
                glDeleteShader(shader);
                throw new IllegalStateException("Probe shader compile failed: " + log);
            }
            return shader;
        }
        private FloatBuffer translation(int x) {
            for (int i = 0; i < 16; i++) matrix.put(i, i % 5 == 0 ? 1f : 0f);
            matrix.put(12, x);
            return matrix;
        }
        private void uploadBone(int x) {
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 4, 1, GL_RGBA, GL_FLOAT, translation(x));
        }
        private void uploadQuad(int x, int rgba) {
            vertices.clear();
            for (int i = 0; i < 4; i++) {
                vertices.putFloat(x + (i % 2) * 8).putFloat(4 + (i / 2) * 8);
                vertices.put((byte)(rgba >>> 24)).put((byte)(rgba >>> 16)).put((byte)(rgba >>> 8)).put((byte)rgba);
            }
            vertices.flip();
            glBufferSubData(GL_ARRAY_BUFFER, 0L, vertices);
        }
        String check(Update update, boolean synchronizedDraws) {
            glClearBufferfv(GL_COLOR, 0, clearColor);
            glUniformMatrix4fv(pose, false, translation(0));
            glUniform1i(useBones, update == Update.FLOAT_BONE_TEXTURE ? 1 : 0);
            if (update != Update.INTERLEAVED_VERTEX_BUFFER) uploadQuad(0, ORANGE);
            boolean firstDrawWasOrange = true;
            for (int i = 0; i < 2; i++) {
                int x = 4 + 16 * i;
                switch (update) {
                    case INTERLEAVED_VERTEX_BUFFER -> uploadQuad(x, i == 0 ? ORANGE : BLUE);
                    case PER_DRAW_MATRIX_UNIFORM -> glUniformMatrix4fv(pose, false, translation(x));
                    case FLOAT_BONE_TEXTURE -> uploadBone(x);
                }
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                if (synchronizedDraws && i == 0) {
                    // Force the first draw's pixels across the GPU/CPU boundary before
                    // updating its source; some translation layers implement glFinish as a no-op.
                    referencePixel.putInt(0, 0);
                    glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, referencePixel);
                    firstDrawWasOrange = rgbaAt(referencePixel, 0) == ORANGE;
                }
            }
            // Readback synchronizes only after both normal draws have been submitted.
            for (int i = 0; i < pixels.capacity(); i++) pixels.put(i, (byte)0xa5);
            glReadPixels(0, 0, WIDTH, HEIGHT, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
            int errors = 0;
            String first = "";
            for (int y = 0; y < HEIGHT; y++) {
                for (int x = 0; x < WIDTH; x++) {
                    int expected = BLACK;
                    if (y >= 4 && y < 12) {
                        if (x >= 4 && x < 12) expected = ORANGE;
                        if (x >= 20 && x < 28) expected = update == Update.INTERLEAVED_VERTEX_BUFFER ? BLUE : ORANGE;
                    }
                    int offset = 4 * (y * WIDTH + x);
                    int actual = rgbaAt(pixels, offset);
                    if (actual != expected) {
                        if (errors == 0) first = String.format("first=(%d,%d) expected=%08X actual=%08X", x, y, expected, actual);
                        errors++;
                    }
                }
            }
            if (errors == 0 && firstDrawWasOrange) return "PASS";
            return "FAIL pixels=" + errors + "/" + (WIDTH * HEIGHT) + " " + first
                    + (firstDrawWasOrange ? "" : " first draw was already incorrect at synchronization");
        }
        private static int rgbaAt(ByteBuffer buffer, int offset) {
            return ((buffer.get(offset) & 255) << 24) | ((buffer.get(offset + 1) & 255) << 16)
                    | ((buffer.get(offset + 2) & 255) << 8) | (buffer.get(offset + 3) & 255);
        }
        void delete() {
            if (fbo != 0) glDeleteFramebuffers(fbo);
            if (target != 0) glDeleteTextures(target);
            if (bones != 0) glDeleteTextures(bones);
            if (vbo != 0) glDeleteBuffers(vbo);
            if (vao != 0) glDeleteVertexArrays(vao);
            if (program != 0) glDeleteProgram(program);
        }
    }

    private static final class State {
        private final int drawFbo = glGetInteger(GL_DRAW_FRAMEBUFFER_BINDING), readFbo = glGetInteger(GL_READ_FRAMEBUFFER_BINDING);
        private final int program = glGetInteger(GL_CURRENT_PROGRAM), vao = glGetInteger(GL_VERTEX_ARRAY_BINDING);
        private final int array = glGetInteger(GL_ARRAY_BUFFER_BINDING), texture = glGetInteger(GL_TEXTURE_BINDING_2D);
        private final int pack = glGetInteger(GL_PIXEL_PACK_BUFFER_BINDING), unpack = glGetInteger(GL_PIXEL_UNPACK_BUFFER_BINDING);
        private final int unit = glGetInteger(GL_ACTIVE_TEXTURE) - GL_TEXTURE0;
        private final boolean blend = glIsEnabledi(GL_BLEND, 0);
        private final int[] stores = {GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH, GL_PACK_SKIP_ROWS, GL_PACK_SKIP_PIXELS,
                GL_UNPACK_ALIGNMENT, GL_UNPACK_ROW_LENGTH, GL_UNPACK_SKIP_ROWS, GL_UNPACK_SKIP_PIXELS, GL_UNPACK_SWAP_BYTES};
        private final int[] previousStores = new int[stores.length], polygon = new int[2];
        private final int[] flags = {GL_CULL_FACE, GL_DEPTH_TEST, GL_STENCIL_TEST, GL_RASTERIZER_DISCARD,
                GL_COLOR_LOGIC_OP, GL_FRAMEBUFFER_SRGB, GL_DITHER, GL_MULTISAMPLE, GL_POLYGON_SMOOTH};
        private final boolean[] enabled = new boolean[flags.length], clip;
        private final ByteBuffer mask;
        private final FloatBuffer viewport;
        private final boolean indexedViewport, scissor, hasSamplers;
        private final int sampler;

        State(GLCapabilities caps, MemoryStack stack) {
            hasSamplers = caps.OpenGL33 || caps.GL_ARB_sampler_objects;
            sampler = hasSamplers ? glGetInteger(GL_SAMPLER_BINDING) : 0;
            indexedViewport = caps.OpenGL41 || caps.GL_ARB_viewport_array;
            scissor = indexedViewport ? glIsEnabledi(GL_SCISSOR_TEST, 0) : glIsEnabled(GL_SCISSOR_TEST);
            viewport = stack.mallocFloat(4);
            if (indexedViewport) glGetFloati_v(GL_VIEWPORT, 0, viewport);
            else glGetFloatv(GL_VIEWPORT, viewport);
            mask = stack.malloc(4);
            glGetBooleani_v(GL_COLOR_WRITEMASK, 0, mask);
            glGetIntegerv(GL_POLYGON_MODE, polygon);
            for (int i = 0; i < stores.length; i++) previousStores[i] = glGetInteger(stores[i]);
            for (int i = 0; i < flags.length; i++) enabled[i] = glIsEnabled(flags[i]);
            clip = new boolean[glGetInteger(GL_MAX_CLIP_DISTANCES)];
            for (int i = 0; i < clip.length; i++) clip[i] = glIsEnabled(GL_CLIP_DISTANCE0 + i);
        }
        void prepare() {
            glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
            if (hasSamplers) glBindSampler(unit, 0);
            for (int key : stores) glPixelStorei(key, key == GL_PACK_ALIGNMENT || key == GL_UNPACK_ALIGNMENT ? 1 : 0);
            for (int i = 0; i < flags.length; i++) if (enabled[i]) glDisable(flags[i]);
            for (int i = 0; i < clip.length; i++) if (clip[i]) glDisable(GL_CLIP_DISTANCE0 + i);
            if (indexedViewport) {
                glDisablei(GL_SCISSOR_TEST, 0);
                glViewportIndexedf(0, 0, 0, WIDTH, HEIGHT);
            } else {
                glDisable(GL_SCISSOR_TEST);
                glViewport(0, 0, WIDTH, HEIGHT);
            }
            glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
            glDisablei(GL_BLEND, 0);
            glColorMaski(0, true, true, true, true);
        }
        void restore() {
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFbo);
            glBindFramebuffer(GL_READ_FRAMEBUFFER, readFbo);
            glBindVertexArray(vao);
            glBindBuffer(GL_ARRAY_BUFFER, array);
            glBindBuffer(GL_PIXEL_PACK_BUFFER, pack);
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack);
            glBindTexture(GL_TEXTURE_2D, texture);
            if (hasSamplers) glBindSampler(unit, sampler);
            glUseProgram(program);
            glColorMaski(0, mask.get(0)!=0, mask.get(1)!=0, mask.get(2)!=0, mask.get(3)!=0);
            if (blend) glEnablei(GL_BLEND, 0);
            if (polygon[0] == polygon[1]) glPolygonMode(GL_FRONT_AND_BACK, polygon[0]);
            else { glPolygonMode(GL_FRONT, polygon[0]); glPolygonMode(GL_BACK, polygon[1]); }
            if (indexedViewport) {
                glViewportIndexedf(0, viewport.get(0), viewport.get(1), viewport.get(2), viewport.get(3));
                if (scissor) glEnablei(GL_SCISSOR_TEST, 0);
            } else {
                glViewport((int)viewport.get(0), (int)viewport.get(1), (int)viewport.get(2), (int)viewport.get(3));
                if (scissor) glEnable(GL_SCISSOR_TEST);
            }
            for (int i = 0; i < flags.length; i++) if (enabled[i]) glEnable(flags[i]);
            for (int i = 0; i < clip.length; i++) if (clip[i]) glEnable(GL_CLIP_DISTANCE0 + i);
            for (int i = 0; i < stores.length; i++) glPixelStorei(stores[i], previousStores[i]);
        }
    }
}
