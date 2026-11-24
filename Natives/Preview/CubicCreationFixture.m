#import <UIKit/UIKit.h>
#import "PLProfiles.h"
#import "ZL2GameAddonsViewController.h"

static UIView *FindControl(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *match = FindControl(child, identifier);
        if (match) return match;
    }
    return nil;
}

static BOOL HasVisibleName(UIView *root, NSString *name) {
    if (root.hidden || root.alpha == 0) return NO;
    if ([root isKindOfClass:UILabel.class] && [((UILabel *)root).text isEqualToString:name]) return YES;
    for (UIView *child in root.subviews) {
        if (HasVisibleName(child, name)) return YES;
    }
    return NO;
}

static void SetName(UITextField *field, NSString *name) {
    field.text = name;
    [field sendActionsForControlEvents:UIControlEventEditingChanged];
}

void CubicCheckProfileCreation(UIViewController *modal, UIViewController *home, BOOL failWrite, dispatch_block_t finished) {
    NSCAssert([modal isKindOfClass:ZL2GameAddonsViewController.class], @"New Profile opened the wrong form");
    ZL2GameAddonsViewController *form = (id)modal;
    UITextField *name = (id)FindControl(form.view, @"cubic.profile.name");
    UIButton *create = (id)FindControl(form.view, @"cubic.profile.create");
    NSCAssert([name isKindOfClass:UITextField.class] && [create isKindOfClass:UIButton.class], @"Missing profile controls");
    NSString *profileName = @"ZZ Keyboard Test";
    NSString *version = form.gameVersion;
    NSCAssert([version isEqual:@"1.21.4"], @"Expected fixture release as default, got %@", version);
    NSUInteger previousCount = PLProfiles.current.profiles.count;
    NSCAssert(!create.enabled, @"Empty name enabled Create");

    NSCAssert([name becomeFirstResponder], @"Cannot edit profile name");
    SetName(name, @"The Gang");
    NSCAssert(!create.enabled, @"An existing name enabled Create");
    SetName(name, profileName);
    NSCAssert(create.enabled && name.isFirstResponder, @"Valid name did not enable Create while editing");
    NSCAssert(name.returnKeyType == UIReturnKeyDone &&
              [name.delegate respondsToSelector:@selector(textFieldShouldReturn:)], @"Done is not wired to the text field");
    [name.delegate textFieldShouldReturn:name];
    NSCAssert(!name.isFirstResponder && form.presentingViewController && create.enabled &&
              PLProfiles.current.profiles.count == previousCount, @"Done should dismiss only the keyboard and keep Create available");

    NSMutableArray<NSDictionary *> *requests = [NSMutableArray array];
    NSString *previousSelection = PLProfiles.current.selectedProfileName;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"CubicPreviewPrepareVersion" object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [requests addObject:note.userInfo]; }];
    [create sendActionsForControlEvents:UIControlEventTouchUpInside];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        NSDictionary *profile = PLProfiles.current.profiles[profileName];
        if (failWrite) {
            UILabel *status = (id)FindControl(form.view, @"cubic.profile.status");
            NSCAssert(form.presentingViewController && !status.hidden && [status.text isEqual:@"Fixture storage is read-only."] &&
                      [name.text isEqual:profileName] && create.enabled, @"Failed write lost form, its error message, or the retry action");
            NSCAssert(!profile && PLProfiles.current.profiles.count == previousCount &&
                      [PLProfiles.current.selectedProfileName isEqual:previousSelection] && !requests.count,
                      @"Failed write changed the profile list, selection, or queued a download");
            NSLog(@"Profile creation failure kept the form editable and the storage error visible");
            finished();
            return;
        }
        NSDictionary *expectedRequest = @{@"version":version, @"name":profileName};
        NSCAssert(requests.count == 1 && [requests.firstObject isEqual:expectedRequest], @"Unexpected game file preparation %@", requests);
        NSCAssert(PLProfiles.current.profiles.count == previousCount + 1 &&
                  [profile[@"name"] isEqual:profileName] && [profile[@"lastVersionId"] isEqual:version] &&
                  [PLProfiles.current.selectedProfileName isEqual:profileName], @"Create did not register and select exactly one named profile");
        NSCAssert(!form.presentingViewController && home.view.window, @"Create did not return to My Profiles");
        UICollectionView *grid = [home valueForKey:@"gridView"];
        [grid layoutIfNeeded];
        BOOL found = NO;
        for (UICollectionViewCell *cell in grid.visibleCells) {
            if (HasVisibleName(cell, profileName)) { found = YES; break; }
        }
        NSCAssert(found, @"The new profile card is missing on return");
        NSLog(@"Profile creation passed. Empty and duplicate names blocked, Done dismissed keyboard, Create selected and displayed %@", profileName);
        finished();
    });
}
