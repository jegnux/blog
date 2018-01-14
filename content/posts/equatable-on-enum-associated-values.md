---
title: "Equatable on Enum Associated Values"
date: 2018-01-14T01:40:45+01:00
draft: false
tags: ["swift-lang"]
---

# The problem

While I was reading Twitter, I came across this good question from [@Cocoanetics](https://twitter.com/Cocoanetics):

{{% tweet 800653458365939713 %}}
<img alt="Cocoanetics' Screenshot" src="https://pbs.twimg.com/media/Cxx-EWcXUAEQiBg.jpg" style="height:450px;"/>

---

Most of responses were pure technical (but still valid) answers. In short: 

> you should use a switch instead, but still need to compare all cases.

Maybe. But the code above still feels wrong to me because it tries to make two different cases equatable just because they have the same associated value. That's semantically incorrect. With a such implementation the following code would return `true`
```swift
.afterID(42) == .beforeID(42)
```

No difficulty here to understand that this can become a source of bugs. Especially with indirect uses of Equatable, like a Collection's `contains()` func for example.

How could we make a more elegant implementation of Equatable with this two requirements: 
- 2 different cases can’t be equal
- `.afterID` and `.beforeID` associated identifiers equality must be easy and straightforward to check.

---

# A solution

An easy first attempt could be to perform a strict equality check on cases, and use an `identifier` property to check identifiers equality:

```swift
enum QueryFilter {
  case noFilter
  case afterID(Int)
  case beforeID(Int)
  case offset(Int)

  var identifier: Int? {
    switch self {
    case .afterID(let id), .beforeID(let id):
      return id
    case .noFilter, .offset:
      return nil
  }
}
```

```swift
extension QueryFilter: Equatable {
  static func == (lhs: QueryFilter, rhs: QueryFilter) -> Bool {
    switch (lhs, rhs) {
    case (.noFilter, .noFilter):
      return true
      
    case let (.afterID(_id), .afterID(id)):
      return _id == id
      
    case let (.beforeID(_id), .beforeID(id)):
      return _id == id
      
    case let (.offset(_offset), .offset(offset)):
      return _offset == offset
      
    default:
      return false
    }
  }
}
```

Here how it works:
```swift
QueryFilter.afterID(42) == QueryFilter.afterID(42)
// true

QueryFilter.afterID(42) == QueryFilter.afterID(1337)
// false, identifiers are different

QueryFilter.afterID(42) == QueryFilter.beforeID(42)
// false, cases are different

QueryFilter.afterID(42).identifier == QueryFilter.beforeID(42).identifier 
// true, we don't care about the case, we just compare identifiers
```

But the problem is that it can lead to strange results:
```swift
QueryFilter.noFilter.identifier == QueryFilter.offset(42).identifier
// true, nil == nil is true :unamused:
```

Can we fix this?<br/>
**Yes**. Have you ever heard about indirect enums? :smirk:

---

# An elegant solution

An indirect case allows you to make a "recursive" enum by associating a case to another case of the same enum.

But how this could solve our problem? It’s quite simple: instead of having identifier being an Int?, this var can be itself a `QueryFilter` with an indirect case shadowing the original `QueryFilter` case.

This way, we can make a specific rule for shadowed cases in our `==` implementation.

```swift
enum QueryFilter {
  case noFilter
  case afterID(Int)
  case beforeID(Int)
  case offset(Int)

  // This will shadow one of above cases
  indirect case value(QueryFilter) 

  var value: QueryFilter {
     // Avoid `.value(_)` shadowing
    if case .value(_) = self { return self }
    
    // Shadow original case (self) in an `value(_)` case
    return .value(self)
  }
}
```

```swift
extension QueryFilter: Equatable {
  static func == (lhs: QueryFilter, rhs: QueryFilter) -> Bool {
    switch (lhs, rhs) {
     
    // Nothing change for basic cases. We make a strict equality check
    case (.noFilter, .noFilter):
      return true
      
    case let (.afterID(_id), .afterID(id)):
      return _id == id
      
    case let (.beforeID(_id), .beforeID(id)):
      return _id == id
      
    case let (.offset(_offset), .offset(offset)):
      return _offset == offset

    // But we allow comparison between .beforeID(_) and .afterID(_) values 
    // if they shadowed by a .value(_) case
 
    case let (.value(lhs), .value(rhs)):
    
      switch (lhs.original, rhs.original) {
      
      case let (.beforeID(_id), .afterID(id)):
        return _id == id
        
      case let (.afterID(_id), .beforeID(id)):
        return _id == id
      
      // If it's not a comparison between .beforeID(_) and .afterID(_)
      // we fallback on the classic equality check.
      
      default:
        return lhs == rhs
      }

    default:
      return false
    }
  }

  // This recursively get the original shadowed value even if you do somwthing like :
  // let query = QueryFilter.value(.value(.value(.afterID(42))))
  private var original: QueryFilter {
    if case let .value(queryFilter) = self {
      return queryFilter.original
    }
    return self
  }
}
```

Does it work well? Hell yes! 😈

```swift
QueryFilter.noFilter == QueryFilter.offset(42)
// false

QueryFilter.afterID(42) == QueryFilter.afterID(42)
// true

QueryFilter.afterID(42) == QueryFilter.afterID(1337)
// false

QueryFilter.afterID(42) == QueryFilter.beforeID(42)
// false

QueryFilter.noFilter.value == QueryFilter.offset(42).value
// false

QueryFilter.afterID(42).value == QueryFilter.afterID(42).value
// true

QueryFilter.afterID(42).value == QueryFilter.beforeID(42).value
// true
```