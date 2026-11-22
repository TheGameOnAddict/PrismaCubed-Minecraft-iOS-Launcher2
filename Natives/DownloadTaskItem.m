#import "DownloadTaskItem.h"

NSString * const DownloadTaskResourceTypeMinecraft    = @"minecraft";
NSString * const DownloadTaskResourceTypeModloader    = @"modloader";
NSString * const DownloadTaskResourceTypeMod          = @"mod";
NSString * const DownloadTaskResourceTypeShader       = @"shader";
NSString * const DownloadTaskResourceTypeResourcePack = @"resourcepack";
NSString * const DownloadTaskResourceTypeDataPack     = @"datapack";
NSString * const DownloadTaskResourceTypeModpack      = @"modpack";
NSString * const DownloadTaskResourceTypeWorld        = @"world";
// Task223：数据备份导出（设置·数据导出，借用版本下载任务体系显示进度）
NSString * const DownloadTaskResourceTypeBackup = @"backup";
NSString * const DownloadTaskResourceTypeJavaRuntime  = @"javaruntime";

/// 快照取值辅助：仅接受非空 NSString，否则返回兜底值（快照内容不可信，需类型清洗）
static NSString *PLSnapshotString(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    return fallback;
}

@interface DownloadTaskItem ()
@property(nonatomic, strong) NSMutableArray<NSString *> *events;
@property(nonatomic, copy) NSString *lastEvent;
@end

@implementation DownloadTaskItem

- (BOOL)isProfileInstall {
    return [self.resourceType isEqual:DownloadTaskResourceTypeModpack] &&
        [self.stages.firstObject.title isEqual:@"taskStage.title.parseModpack"];
}

- (double)installProgress {
    if (self.state == DownloadTaskStateCompleted) return 1;
    if (!self.stages.count) return MAX(0, MIN(1, self.progress));
    double done = 0;
    for (PLTaskStage *stage in self.stages) {
        done += (stage.status == PLTaskStageStatusCompleted || stage.status == PLTaskStageStatusSkipped)
            ? 1 : MAX(0, MIN(1, stage.progress));
    }
    return done / self.stages.count;
}

- (NSString *)stateLabel {
    switch (self.state) {
        case DownloadTaskStatePending: return @"Queued";
        case DownloadTaskStateDownloading: return self.isProfileInstall ? @"Installing" : @"Downloading";
        case DownloadTaskStateCompleted: return @"Completed";
        case DownloadTaskStateCancelled: return @"Cancelled";
        case DownloadTaskStatePaused: return @"Paused";
        case DownloadTaskStateFailed: return @"Failed";
    }
    return @"Unknown";
}

- (void)appendActivity:(NSString *)message {
    if (!message.length) return;
    @synchronized (self) {
        if ([message isEqual:self.lastEvent]) return;
        self.lastEvent = message;
        NSString *time = [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        if (!self.events) self.events = [NSMutableArray array];
        [self.events addObject:[NSString stringWithFormat:@"%@  %@", time, message]];
        if (self.events.count > 2048) [self.events removeObjectAtIndex:0];
    }
}
- (NSArray<NSString *> *)activityLines {
    @synchronized (self) { return self.events.copy ?: @[]; }
}

- (instancetype)initWithResourceType:(NSString *)resourceType
                        resourceName:(NSString *)resourceName
                         displayName:(NSString *)displayName
                      downloadSource:(NSString *)downloadSource
                             rawTask:(id)rawTask
                      supportsResume:(BOOL)supportsResume
                             iconURL:(NSString *)iconURL {
    self = [super init];
    if (self) {
        _taskId = [[NSUUID UUID] UUIDString];
        _resourceType = [resourceType copy] ?: @"";
        _resourceName = [resourceName copy] ?: @"";
        _displayName = [displayName copy] ?: _resourceName;
        _downloadSource = [downloadSource copy] ?: @"official";
        _state = DownloadTaskStatePending;
        _progress = -1.0;
        _totalSize = -1;
        _downloadedSize = 0;
        _speed = 0.0;
        _estimatedTimeRemaining = 0.0;
        _completedFileCount = 0;
        _totalFileCount = 0;
        _iconURL = [iconURL copy];
        _supportsResume = supportsResume;
        _createdDate = [NSDate date];
        _rawTask = rawTask;
        _errorInfo = nil;
        _userInfo = [NSMutableDictionary dictionary];
        _retryCount = 0;
        _maxRetryCount = 3;
        _needsRecreate = NO;
        _stages = @[];
        _currentStageIndex = -1;
    }
    return self;
}

#pragma mark - 阶段化进度

- (PLTaskStage *)currentStage {
    if (self.currentStageIndex < 0) return nil;
    NSUInteger index = (NSUInteger)self.currentStageIndex;
    if (index >= self.stages.count) return nil;
    PLTaskStage *stage = self.stages[index];
    return [stage isKindOfClass:[PLTaskStage class]] ? stage : nil;
}

#pragma mark - 快照序列化

- (NSDictionary *)snapshotDictionary {
    // 阶段快照逐项导出（stages 为空数组时序列化为空列表）
    NSMutableArray<NSDictionary *> *stageSnapshots = [NSMutableArray array];
    for (PLTaskStage *stage in self.stages) {
        if ([stage isKindOfClass:[PLTaskStage class]]) {
            [stageSnapshots addObject:[stage snapshotDictionary]];
        }
    }
    return @{
        @"taskId": self.taskId ?: @"",
        @"activity": self.activityLines,
        @"parentTaskId": self.parentTaskId ?: @"",
        @"errorText": self.errorInfo.localizedDescription ?: @"",
        @"errorDomain": self.errorInfo.domain ?: @"",
        @"errorCode": @(self.errorInfo.code),
        @"resourceType": self.resourceType ?: @"",
        @"resourceName": self.resourceName ?: @"",
        @"displayName": self.displayName ?: @"",
        @"downloadSource": self.downloadSource ?: @"",
        @"state": @(self.state),
        @"progress": @(self.progress),
        @"totalBytes": @(self.totalSize),
        @"receivedBytes": @(self.downloadedSize),
        @"iconURL": self.iconURL ?: @"",
        @"downloadURL": self.downloadURL ?: @"",
        @"resumeDataPath": self.resumeDataPath ?: @"",
        @"supportsResume": @(self.supportsResume),
        @"retryCount": @(self.retryCount),
        @"completedFileCount": @(self.completedFileCount),
        @"totalFileCount": @(self.totalFileCount),
        @"stages": [stageSnapshots copy],
        @"currentStageIndex": @(self.currentStageIndex),
        @"timestamp": @([self.createdDate timeIntervalSince1970]),
    };
}

- (instancetype)initWithSnapshotDictionary:(NSDictionary *)snapshot {
    if (![snapshot isKindOfClass:[NSDictionary class]]) return nil;
    NSString *taskId = snapshot[@"taskId"];
    if (![taskId isKindOfClass:[NSString class]] || taskId.length == 0) return nil;

    NSString *iconURL = snapshot[@"iconURL"];
    self = [self initWithResourceType:PLSnapshotString(snapshot[@"resourceType"], @"")
                          resourceName:PLSnapshotString(snapshot[@"resourceName"], @"")
                           displayName:PLSnapshotString(snapshot[@"displayName"], @"")
                        downloadSource:PLSnapshotString(snapshot[@"downloadSource"], @"official")
                               rawTask:nil
                        supportsResume:[snapshot[@"supportsResume"] boolValue]
                               iconURL:PLSnapshotString(iconURL, nil)];
    if (!self) return nil;

    // 沿用原 taskId（保持与持久化快照/断点数据文件的对应关系）
    _taskId = [taskId copy];
    _parentTaskId = PLSnapshotString(snapshot[@"parentTaskId"], nil);
    if ([snapshot[@"activity"] isKindOfClass:NSArray.class]) {
        _events = [NSMutableArray array];
        for (id line in snapshot[@"activity"]) if ([line isKindOfClass:NSString.class]) [_events addObject:line];
    }
    NSString *description = PLSnapshotString(snapshot[@"errorText"], nil);
    if (description) _errorInfo = [NSError errorWithDomain:PLSnapshotString(snapshot[@"errorDomain"], @"Download") code:[snapshot[@"errorCode"] integerValue] userInfo:@{NSLocalizedDescriptionKey:description}];
    _state = [snapshot[@"state"] integerValue];
    _progress = [snapshot[@"progress"] doubleValue];
    _totalSize = [snapshot[@"totalBytes"] longLongValue];
    _downloadedSize = [snapshot[@"receivedBytes"] longLongValue];
    _retryCount = [snapshot[@"retryCount"] integerValue];
    _completedFileCount = [snapshot[@"completedFileCount"] integerValue];
    _totalFileCount = [snapshot[@"totalFileCount"] integerValue];

    NSString *downloadURL = snapshot[@"downloadURL"];
    if ([downloadURL isKindOfClass:[NSString class]] && downloadURL.length > 0) {
        _downloadURL = [downloadURL copy];
    }
    NSString *resumeDataPath = snapshot[@"resumeDataPath"];
    if ([resumeDataPath isKindOfClass:[NSString class]] && resumeDataPath.length > 0) {
        _resumeDataPath = [resumeDataPath copy];
    }

    NSNumber *timestamp = snapshot[@"timestamp"];
    if ([timestamp isKindOfClass:[NSNumber class]]) {
        _createdDate = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
    }

    // 阶段列表（旧版快照无 stages 字段：保持空数组，回退纯进度展示，不崩溃）
    NSArray *stageSnapshots = snapshot[@"stages"];
    if ([stageSnapshots isKindOfClass:[NSArray class]]) {
        NSMutableArray *stages = [NSMutableArray array];
        for (id entry in stageSnapshots) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            PLTaskStage *stage = [[PLTaskStage alloc] initWithSnapshotDictionary:entry];
            if (stage) [stages addObject:stage];
        }
        _stages = [stages copy];
    } else {
        _stages = @[];
    }
    // currentStageIndex 越界（含空阶段列表）一律回退 -1，避免 UI 数组越界访问
    NSInteger stageIndex = [snapshot[@"currentStageIndex"] integerValue];
    _currentStageIndex = (stageIndex >= 0 && (NSUInteger)stageIndex < _stages.count) ? stageIndex : -1;
    return self;
}

- (NSDictionary *)historyDictionary {
    NSString *name = self.displayName.length > 0 ? self.displayName : self.resourceName;
    return @{
        @"taskId": self.taskId ?: @"",
        @"name": name ?: @"",
        @"type": self.resourceType ?: @"",
        @"size": @(self.totalSize),
        @"received": @(self.downloadedSize),
        @"result": self.state == DownloadTaskStateCompleted ? @"success" : self.stateLabel.lowercaseString,
        @"snapshot": self.snapshotDictionary,
        @"source": self.downloadSource ?: @"",
        @"time": @([[NSDate date] timeIntervalSince1970]),
    };
}

@end
