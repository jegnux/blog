---
title: "Scroll to Top with Undo in RxSwift"
date: 2018-01-28T09:23:08+01:00
draft: false
tags: ["rxswift"]
---

In this post I'll write about how to implement a custom **scroll to top** feature with the ability to restore the old `contentOffset`. The first app I saw implementing this feature was [TweetBot](https://tapbots.com/tweetbot/) in its [4.8 update](https://itunes.apple.com/fr/app/tweetbot-4-for-twitter/id1018355599?mt=8) and it became instantly a must have for me.

While working on side-project application (stay tuned 😉), I implemented this feature as well. Let's see how it can be done entirely using **RxSwift** :metal:

## :sparkles: RxSwift

My *love* for **RxSwift** began mid 2016 when I joined <span style="color: #f80059; font-weight:bold;">Heetch</span>. Since then, it helps me to write complex features in such a simple, expressive, and readable way. I think I will speak about **RxSwift** often on this blog, because IMHO <span class="green">it definitely helps to write elegant code</span>.

The **scroll to top** is usually triggered by a tap on the status bar, but as it will be implemented here it will also be possible to add new sources to trigger. For instance a tap on tab bar item, or on `viewWillAppear()`, or on everything else as soon as it's an `Observable`.

<div style="background-color:#eeeeee; text-align: center; padding: 20px;">The beauty of <b>RxSwift</b> is to offer <span class="green">a uniform interface for many Cocoa's design patterns</span> (delegate, target/action, notifications, callback closures, etc.).</div>

## Implementation

### The recipe

1. Implement an `Observable<Void>` that emits whenever the user taps on the `UIApplication.shared.keyWindow` in status bar's frame
2. Associate 1. to a `UIViewController` and filter its events to emit them if and only if the `UIViewController` instance is visible (ie. between `viewDidAppear` and `viewWillDisappear` lifecycle events)
3. Implement a `ScrollTarget` enum to let switch over different target (either `.top` or `.offset(CGFloat)`
4. Implement an `Observable` that emits whenever the user has finished to scroll an `UIScrollView` in order to save the current `contentOffset` into `ScrollTarget.offset(contentOffset.y)`
5. Implement the final subscription that combine 2. and 4. to scroll the `UIScrollView` to the desired target.

### Prerequisites

For the implementation I used **RxSwift**, **RxCocoa** and **RxSwiftExt**.
There are also two little Rx extensions I use.

The first one transforms any `Observable<E>` into `Observable<Void>`. It's quite convenient when we don't need the value. Typically when you use the `Observable` as a sampler.

```swift
extension ObservableType {
  func void() -> Observable<Void> {
    return map { _ in }
  }
}
```

The second is a `startWith` operator that takes a closure instead of a value. It avoids a strong reference on the initial value.

```swift
extension ObservableType {
  func startWith(_ factory: @escaping () -> Observable<E>) -> Observable<E> {
    let start = Observable<E>.deferred {
      factory()
    }
    return start.concat(self)
  }
}
```

### 1. Detect tap on status bar

To do this without any subclassing, **RxCocoa** will be a precious help.

First let's make an `Observable<UIWindow?>` that emits the `keyWindow` of `UIApplication.shared`.

```swift
extension Reactive where Base: UIApplication {
  var keyWindow: Observable<UIWindow?> {
    return NotificationCenter.default.rx
      .notification(.UIWindowDidBecomeKey, object: nil)
      .map { notification -> UIWindow? in
        notification.object as? UIWindow
      }
      .startWith { [weak base] in
        guard let base = base else { return .empty() }
        return .just(base.keyWindow)
      }
  }
}
```
- On **lines 3 to 6** we listen for `UIWindowDidBecomeKey` notification and get the associated object (the window) once a notification is posted
- On **lines 8 to 11** we use the current `base.keyWindow` as a start value

Now that we always have the latest `keyWindow` we can `flatMap` over it to detect when user taps in it. The best way to do this is to attach an `UITapGestureRecognizer` to the window. It would be really easy to do with [**RxGesture**](https://github.com/RxSwiftCommunity/RxGesture) for example.

Unfortunately, on iOS <span class="red">the view system won't deliver the touch event</span> to any gesture recognizer if the touch location is in status bar's frame.
The only way I found to bypass this limitation is to intercept the invocation of:
```swift
func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
```

And **RxCocoa** has a powerful built-in `.methodInvoked()` operator to do this.

```swift
extension ObservableType {
  var statusBarTap: Observable<Void> {
    return keyWindow
      .flatMapLatest { window -> Observable<CGPoint> in
        guard let window = window else { return .empty() }
        return window.rx
          .methodInvoked(#selector(UIView.hitTest(_:with:)))
          .map { args -> CGPoint? in
            guard args.count == 2,
              let point = args[0] as? CGPoint,
              let _ = args[1] as? UIEvent
              else { return nil}
            return point
          }
          .unwrap()
      }
      .filter { [unowned app = self.base] point in
        point.y < app.statusBarFrame.maxY + 20
      }
      .void()
      .debounce(0, scheduler: MainScheduler.asyncInstance)
  }
}
```
- On **line 3** we use the `keyWindow: Observable<UIWindow?>` defined earlier
- On **line 7** we use the `.methodInvoked()` operator to intercept the invocation of `UIView.hitTest(_:with:)`,
- On **lines 8 to 14** we `map` the previous result to get the point location of the touch event. In practice, it would be safe to return directly a forced unwrapped `arg.first as! CGPoint` because we *know* the exact method signature, but I still prefer to keep an optional
- On **line 11**, we make sure that there's really an event given in order to avoid false positives
- On **line 15** we unwrap the point with [`.unwrap()`](https://github.com/RxSwiftCommunity/RxSwiftExt#unwrap) operator of **RxSwiftExt**.
- On **line 18** you can notice that I add an extra `20pt` to the `statusBarFrame`. It makes the tappable target a little bit higher. [M. Fitts](https://lawsofux.com/fittss-law.html) approves it :+1:.
- On **line 21**, we use the `.debounce()` operator with a delay of `0` and an async instance of the `MainScheduler`. It's important because `UIView.hitTest(_:with:)` will be called many times during the same run loop, so we need to filter repetitive events. You can see this as similar to an other UIKit pattern like `setNeedsDisplay()` / `displayIfNeeded()`

:muscle: Awesome, we're done with the first step.

### 2. Detect status bar tap on a visible ViewController

As you will likely use this feature on a `UIScrollView` included in a specific `UIViewController`, you better make sure that this `UIViewController` is actually **visible** before reacting to this event.

Otherwise, imagine you have several `UIViewController` implementing this gesture in a `UITabBarController`. If you don't emit the event only for the visible `UIViewController`, a tap on the status bar will scroll to top all `UIScrollView` of all view controllers. We obviously don't want this.

```swift
extension Reactive where Base: UIViewController {
  var statusBarTap: Observable<Void> {
    let isVisible: Observable<Bool> = Observable
    .merge(
      methodInvoked(#selector(
      	UIViewController.viewWillAppear(_:)
      )).map(to: false),

      methodInvoked(#selector(
      	UIViewController.viewDidAppear(_:)
      )).map(to: true),

      methodInvoked(#selector(
      	UIViewController.viewWillDisappear(_:)
      )).map(to: false),

      methodInvoked(#selector(
      	UIViewController.viewDidDisappear(_:)
     	)).map(to: false)
    )
    return UIApplication.shared.rx
      .statusBarTap
      .pausable(isVisible)
  }
}

```

Once again, **RxCocoa**'s `.methodInvoked()` operator is a great help as it allows us to intercept appearance lifecycle methods and map them to a boolean indicating if the view controller is visible or not. Here, `viewDidAppear` is mapped to `true` (line 11) and other methods are mapped to `false`.

To finish, we reuse `UIApplication.shared.rx.statusBarTap` we created earlier and use the [`.pausable()`](https://github.com/RxSwiftCommunity/RxSwiftExt#pausable) operator of **RxSwiftExt** in order to emit values only if latest value from `isVisible` is `true`.


### 3. ScrollTarget

```swift
enum ScrollTarget {
  case top
  case offset(CGFloat)
}
```

:white_check_mark: Done

### 4. Save contentOffset after scroll

Starting from here, I will simplify and write all the code we need in our `UIViewController`'s `viewDidLoad()`. I will also assume there are a `scrollView` and a `disposeBag` around there.

Let's start with the code.

```swift
func viewDidLoad() {
  super.viewDidLoad()

  let target = BehaviorSubject(value: ScrollTarget.top)

  let source = self.rx.statusBarTap.withLatestFrom(target).share()

  // Save
  source
    .map { [unowned scrollView] target -> ScrollTarget in
      switch target {
      case .top:
        return .offset(scrollView.contentOffset.y)
      case .offset:
        return .top
      }
    }
    .bind(to: target)
    .disposed(by: disposeBag)

  // Reset
  scrollView.rx
    .willBeginDragging
    .map(to: .top)
    .bind(to: target)
    .disposed(by: disposeBag)

  // To be continued...

}
```

- On **line 4** we create a `BehaviorSubject` that will hold our next `ScrollTarget`. The initial target will obviously be `.top`.
- On **line 6** we prepare our source. It's just the `UIViewController.rx.statusBarTap` we created earlier, combined with the next target, and we finish with a `share()`. It's important to share here because as on **line 27** we update the target, we want to be sure that the subscription to actually _scrolls_ the scroll view, use the correct target.
- On **lines 8 to 19** we save the next target. If current target was `.top`, then the next target will be `.offset` with the current `scrollView` offset. Otherwise, the next target will be `.top`. This allows us to alternatively use one target or the other.
- On **lines 22 to 28** we add a mechanism that reset the next target to `.top` as soon as the user interacts with the `scrollView`, because it wouldn't make sense to restore the old offset.

### 5. The final piece

Now we can implement the actual scrolling.

```swift
func viewDidLoad() {
  // ...

  let source = ...

  // Save
  // ...

  // Reset
  // ...

  source
    .map { target -> CGFloat in
      switch target {
      case .top:
        return -scrollView.adjustedContentInset.top
      case .offset(let offset):
        return offset
      }
    }
    .subscribe(onNext: { [unowned scrollView] offset in
        var contentOffset = scrollView.contentOffset
        contentOffset.y = offset
        scrollView.setContentOffset(contentOffset, animated: true)
    })
    .disposed(by: disposeBag)
}
```

No big deal here, we just get the good offset for each `ScrollTarget` cases and we animate the `scrollView.contentOffset` update.

<center><big>**That's all :tada:**</big></center>

---

To conclude, we've seen some interesting techniques offered by **RxSwift** and **RxCocoa** that allowed us to <span class="green">compose</span> an interesting feature without <span class="red">subclassing</span>, or using a <span class="red">mutable shared state</span>.

As an exercise, you can factorize the code we added in the `viewDidLoad()` in order to make it easily reusable on any `UIViewController` / `UIScrollView`.


:warning: Despite how elegant and clean the final code looks like, there are still some trade-offs because we use some **RxCocoa** features that depends on **Objective-C runtime** and, event if we don't use any private methods, you still should be careful when you use such techniques.

<div style="background-color:#eeeeee; padding: 20px;">I hope you enjoyed reading this blog post / tutorial. Please do not hesitate to add a comment to tell me what you thought about it, to ask me some questions, or even to suggest me an idea for a future post where I could try to make an obscure solution more elegant :wink:</div>
