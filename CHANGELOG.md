# Changelog

Notable changes to Tero, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow the rules in the README's [API stability](README.md#api-stability) section.

## [2.1.0] - 2026-09-24

### Changed

- **Breaking, Objective-C only:** four `Bool` properties follow UIKit's naming in Objective-C. The Swift names are unchanged. ([#3](https://github.com/g761007/Tero/issues/3))

  | Class | Before | After |
  |---|---|---|
  | `TeroNavigationContainer` | `isInteractivePopGestureEnabled`, `setIsInteractivePopGestureEnabled:` | `interactivePopGestureEnabled` (getter `isInteractivePopGestureEnabled`), `setInteractivePopGestureEnabled:` |
  | `TeroNavigationContainer` | `isScrollEdgeEffectEnabled`, `setIsScrollEdgeEffectEnabled:` | `scrollEdgeEffectEnabled` (getter `isScrollEdgeEffectEnabled`), `setScrollEdgeEffectEnabled:` |
  | `TeroTabItem` | `isEnabled`, `setIsEnabled:` | `enabled` (getter `isEnabled`), `setEnabled:` |
  | `TeroTabActionItem` | `isEnabled`, `setIsEnabled:` | `enabled` (getter `isEnabled`), `setEnabled:` |

  Reading through an old name still compiles. An assignment such as `container.isInteractivePopGestureEnabled = NO;` no longer does, and clang names the missing `setIs…:` setter; write `container.interactivePopGestureEnabled = NO;`.
- A root screen never shows a mirrored back button. `TeroNavigationBar.bind(to:backAction:)` synthesises a back button only when the screen has one to go back to; inside a `TeroNavigationContainer` the container decides, and keeps the answer current as the stack changes, so every screen can pass the same `backAction`. A root that passed a `backAction` loses its back button; use `leftBarButtonItem` for a close button, as with UIKit. ([#1](https://github.com/g761007/Tero/issues/1))
- Mirrored `.automatic` images take the bar's tint, as they do in `UINavigationBar`. Use `.alwaysOriginal` to keep an image's own colours. SF Symbols are unaffected, and so are `TeroNavigationButton`s you create yourself. ([#2](https://github.com/g761007/Tero/issues/2))
- The empty-button diagnostic names the three usual sources and how to fix each, including `hidesBackButton` for the old empty-left-item way of hiding the back button. ([#5](https://github.com/g761007/Tero/issues/5))

### Added

- `UIViewController.teroNavigationContainer`: the nearest `TeroNavigationContainer` up the parent chain, the counterpart of `navigationController`, which is `nil` inside a Tero hierarchy. ([#4](https://github.com/g761007/Tero/issues/4))
- The READMEs show a cross-fade and a drop-down menu that work without custom transitions. ([#6](https://github.com/g761007/Tero/issues/6))

## [2.0.0] - 2026-09-23

First release from this repository.

[2.1.0]: https://github.com/g761007/Tero/compare/2.0.0...2.1.0
[2.0.0]: https://github.com/g761007/Tero/tree/2.0.0
