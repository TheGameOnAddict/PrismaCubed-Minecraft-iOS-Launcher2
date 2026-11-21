#pragma once
#import "ZL2Theme.h"

static inline UILabel *CubicLabel(NSString *text, CGFloat size) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont boldSystemFontOfSize:size];
    label.textColor = ZL2Theme.onSurface;
    label.numberOfLines = 0;
    return label;
}

static inline UIButton *CubicButton(NSString *text, BOOL primary) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:text forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    button.tintColor = primary ? ZL2Theme.onPrimary : ZL2Theme.onSurface;
    button.backgroundColor = primary ? ZL2Theme.primary : ZL2Theme.surfaceContainerHigh;
    button.layer.cornerRadius = 8;
    button.contentEdgeInsets = UIEdgeInsetsMake(10,12,10,12);
    return button;
}

static inline UIStackView *CubicForm(UIViewController *owner, NSString *title) {
    owner.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    UIScrollView *panel = [UIScrollView new];
    panel.backgroundColor = ZL2Theme.surfaceContainer;
    panel.layer.cornerRadius = 14;
    panel.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [owner.view addSubview:panel];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    UILayoutGuide *safe = owner.view.safeAreaLayoutGuide;
    NSLayoutConstraint *width = [panel.widthAnchor constraintEqualToAnchor:safe.widthAnchor constant:-32];
    width.priority = 999;
    NSLayoutConstraint *height = [panel.heightAnchor constraintEqualToAnchor:stack.heightAnchor constant:36];
    height.priority = 998;
    [NSLayoutConstraint activateConstraints:@[width,height,[panel.widthAnchor constraintLessThanOrEqualToConstant:480],
        [panel.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor constant:-20],
        [panel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],[panel.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [stack.widthAnchor constraintEqualToAnchor:panel.frameLayoutGuide.widthAnchor constant:-36],
        [stack.leadingAnchor constraintEqualToAnchor:panel.contentLayoutGuide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:panel.contentLayoutGuide.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:panel.contentLayoutGuide.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:panel.contentLayoutGuide.bottomAnchor constant:-18]]];
    UIButton *close = CubicButton(@"×", NO);
    [close.widthAnchor constraintEqualToConstant:36].active = YES;
    close.accessibilityLabel = @"Close";
    __weak UIViewController *weakOwner = owner;
    [close addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [weakOwner dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:[[UIStackView alloc] initWithArrangedSubviews:@[CubicLabel(title,22),close]]];
    return stack;
}

static inline void CubicUnderline(UIButton *button, BOOL selected) {
    UIView *line = [button viewWithTag:37175];
    if (!line) {
        line = [UIView new];
        line.tag = 37175;
        line.userInteractionEnabled = NO;
        line.backgroundColor = ZL2Theme.primary;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [button addSubview:line];
        [NSLayoutConstraint activateConstraints:@[[line.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
            [line.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],[line.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
            [line.heightAnchor constraintEqualToConstant:2]]];
    }
    line.hidden = !selected;
}
