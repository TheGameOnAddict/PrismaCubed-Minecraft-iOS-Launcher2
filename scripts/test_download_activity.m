#import "DownloadTaskItem.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        DownloadTaskItem *task = [[DownloadTaskItem alloc] initWithResourceType:DownloadTaskResourceTypeModpack resourceName:@"test" displayName:@"Test pack" downloadSource:@"CurseForge" rawTask:nil supportsResume:NO iconURL:nil];
        NSMutableArray *stages = [NSMutableArray array];
        for (NSString *title in @[@"parseModpack", @"extractFiles", @"downloadDependencies", @"installLoader", @"downloadGameFiles", @"finalizeConfig"]) {
            [stages addObject:[PLTaskStage stageWithTitle:[@"taskStage.title." stringByAppendingString:title] iconName:@""]];
        }
        task.stages = stages;
        task.currentStageIndex = 3;
        task.state = DownloadTaskStateFailed;
        for (int i=0; i<3; i++) task.stages[i].status = PLTaskStageStatusCompleted;
        task.currentStage.status = PLTaskStageStatusFailed;
        NSError *error = [NSError errorWithDomain:@"Forge" code:7 userInfo:@{NSLocalizedDescriptionKey:@"Missing dependency"}];
        task.errorInfo = error;
        [task appendActivity:@"Installing Forge"];
        [task appendActivity:error.localizedDescription];
        [task appendActivity:error.localizedDescription];
        NSDictionary *history = task.historyDictionary;
        assert([history[@"result"] isEqual:@"failed"]);
        NSData *data = [NSJSONSerialization dataWithJSONObject:history[@"snapshot"] options:0 error:NULL];
        DownloadTaskItem *restored = [[DownloadTaskItem alloc] initWithSnapshotDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]];
        assert(restored.isProfileInstall && restored.installProgress == 0.5);
        assert(restored.currentStage.status == PLTaskStageStatusFailed);
        assert(restored.activityLines.count == 2 && [restored.activityLines.lastObject containsString:error.localizedDescription]);
        assert([restored.errorInfo.domain isEqual:@"Forge"] && restored.errorInfo.code == 7);
        task.state = DownloadTaskStateCompleted;
        assert([task.historyDictionary[@"result"] isEqual:@"success"] && task.installProgress == 1);
    }
}
