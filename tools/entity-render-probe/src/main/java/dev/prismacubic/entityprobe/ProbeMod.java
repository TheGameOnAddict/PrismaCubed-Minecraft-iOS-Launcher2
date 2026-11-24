package dev.prismacubic.entityprobe;

import net.minecraftforge.api.distmarker.Dist;
import net.minecraftforge.client.event.RenderLevelStageEvent;
import net.minecraftforge.eventbus.api.SubscribeEvent;
import net.minecraftforge.fml.common.Mod;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Mod(ProbeMod.ID)
public final class ProbeMod {
    static final String ID = "prisma_entity_draw_probe";

    @Mod.EventBusSubscriber(modid = ID, value = Dist.CLIENT)
    public static final class Client {
        private static final Logger LOG = LoggerFactory.getLogger(ID);
        private static boolean ran;

        @SubscribeEvent
        public static void afterWorldDraw(RenderLevelStageEvent event) {
            if (ran || event.getStage() != RenderLevelStageEvent.Stage.AFTER_LEVEL) {
                return;
            }
            ran = true;
            EntityDrawProbe.run(line -> LOG.info("[Prisma entity probe] {}", line));
        }
    }
}
