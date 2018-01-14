---
title: "Safe Collection Subscripting"
date: 2018-01-14T00:34:59+01:00
draft: false
tags: ["stdlib"]
---

As many Swift developers before me, I wanted to find a way to easily fetch an Element from a Collection with its Index, without having to manually check if the Index I give is in the Collection’s bounds.

On internet, we can find [here](http://ericasadun.com/2015/06/01/swift-safe-array-indexing-my-favorite-thing-of-the-new-week/), [here](http://ericasadun.com/2015/06/24/dear-erica-extend-safe-index/), [here](http://stackoverflow.com/questions/25329186/safe-bounds-checked-array-lookup-in-swift-through-optional-bindings) and somewhere [here](https://medium.com/swift-programming/swift-sequences-ce22d76f120c#.hyyhrxp6i) this solution, which consists to add a label to the subscript parameter.

```swift
public extension Collection {
  private func distance(from startIndex: Index) -> IndexDistance {
    return distance(from: startIndex, to: self.endIndex)
  }

  private func distance(to endIndex: Index) -> IndexDistance {
    return distance(from: self.startIndex, to: endIndex)
  }

  public subscript(safe index: Index) -> Iterator.Element? {
    if distance(to: index) >= 0 && distance(from: index) > 0 {
      return self[index]
    }
    return nil
  }

  public subscript(safe bounds: Range<Index>) -> SubSequence? {
    if distance(to: bounds.lowerBound) >= 0 && distance(from: bounds.upperBound) >= 0 {
      return self[bounds]
    }
    return nil
  }

  public subscript(safe bounds: ClosedRange<Index>) -> SubSequence? {
    if distance(to: bounds.lowerBound) >= 0 && distance(from: bounds.upperBound) > 0 {
      return self[bounds]
    }
    return nil
  }
}
```

With this extension, if you add the `safe:` label to your subscript it will return an Optional of your Element instead of the Element itself. Then, if the Index is in bounds, the Optional will embed your value, but if not, instead of a runtime error, you will get an `Optional<Element>.none`, aka `nil`.

```swift
let numbers = [1,3,3,7]
if let n = numbers[safe: 2] {
    print(n) // Prints "3"
}
if let n = numbers[safe: 20] {
    print(n) // Never get here
}
if let n = numbers[safe: 1...3] {
    print(n) // Prints "[3, 3, 7]"
}
if let n = numbers[safe: 2...8] {
    print(n) // Never get here
}
```

It does the job, but I really don’t like this label. It doesn’t feel natural at all to me. A labelled is supposed to describe the given argument. Or its semantic. But here it describes the behavior of the subscript.

How can we improve this to have a more elegant syntax ? Do we have something similar in the standard library? Maybe Lazy Collections? If Lazy Collections were impletemented like this labelled subscript feature above, we would have something like this:

```swift
numbers.filter(lazy: { %0 ==2 })
```

But instead, we use a much clearer proxy `LazyCollection` type like this:

```swift
numbers.lazy.filter { $0 == 2 }
```

So let’s build a `SafeCollection` type.

```swift
public struct SafeCollection<Base : Collection> {

  private var base: Base
  public init(_ base: Base) {
    self.base = base
  }

  private func distance(from startIndex: Base.Index) -> Base.IndexDistance {
    return base.distance(from: startIndex, to: _base.endIndex)
  }

  private func distance(to endIndex: Base.Index) -> Base.IndexDistance {
    return base.distance(from: _base.startIndex, to: endIndex)
  }

  public subscript(index: Base.Index) -> Base.Iterator.Element? {
    if distance(to: index) >= 0 && distance(from: index) > 0 {
      return base[index]
    }
    return nil
  }

  public subscript(bounds: Range<Base.Index>) -> Base.SubSequence? {
    if distance(to: bounds.lowerBound) >= 0 && distance(from: bounds.upperBound) >= 0 {
      return base[bounds]
    }
    return nil
  }

  public subscript(bounds: ClosedRange<Base.Index>) -> Base.SubSequence? {
    if distance(to: bounds.lowerBound) >= 0 && distance(from: bounds.upperBound) > 0 {
      return base[bounds]
    }
    return nil
  }

}
```

As you can see, it’s just a wrapper around your original collection that forwards subscript calls to its base only if given `Index` is in the collection bounds. Simple.

To use this collection like the `lazy` feature, we just need to extend `Collection`.

```swift
public extension Collection {
  var safe: SafeCollection<Self> {
    return SafeCollection(self)
  }
}
```

We can now use this new beautiful safe syntax like this:

```swift
let numbers = [1,3,3,7]
if let n = numbers.safe[2] {
    print(n) // Prints "3"
}
if let n = numbers.safe[20] {
    print(n) // Never get here
}
if let n = numbers.safe[1...3] {
    print(n) // Prints "[3, 3, 7]"
}
if let n = numbers.safe[2...8] {
    print(n) // Never get here
}
```

Semantically, it's way better. `numbers.safe` is a _safe version of `numbers`_. We can use its subscripts without worrying about being out of bounds.


_This post was initially [posted on medium](https://medium.com/@jegnux/safe-collection-subsripting-in-swift-3771f16f883)_