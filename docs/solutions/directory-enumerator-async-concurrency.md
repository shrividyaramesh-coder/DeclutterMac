---
module: StorageScanner & Swift Concurrency
tags: [swift6, concurrency, filemanager, directory-enumerator, async]
problem_type: compilation_error
---

# Handling DirectoryEnumerator in Swift 6 Asynchronous Contexts

## Problem Encountered
When iterating over directory contents using `FileManager.default.enumerator(...)` within an `actor` or `Task` block:
```swift
for case let fileURL as URL in enumerator { ... }
```
The Swift 6 compiler emits:
`error: instance method 'makeIterator' is unavailable from asynchronous contexts`.

## Root Cause
`FileManager.DirectoryEnumerator` inherits from `NSEnumerator`, which conforms to `Sequence`. However, in Swift 6, `NSEnumerator.makeIterator()` is not marked Sendable and is marked unavailable in asynchronous contexts to prevent concurrent iterator modification.

## Solution & Architecture
Directly advance the enumerator using the synchronous `nextObject()` method within a `while` loop:
```swift
while let fileURL = enumerator.nextObject() as? URL {
    if Task.isCancelled { break }
    // Process fileURL
}
```
This avoids calling `makeIterator()`, satisfies Swift 6 strict concurrency checks, and maintains optimal performance.

## Prevention Rule
Never use `for item in enumerator` on `FileManager.DirectoryEnumerator` within async functions or actors; always use `while let item = enumerator.nextObject() as? URL`.
