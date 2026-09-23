# Docking & Magnetism — Options for a Future Feature

**Date:** 2026-09-11
**Status:** Options paper. Nothing here is scheduled or approved.
**Context:** [`superpowers/specs/2026-09-11-ampx-ui-design.md`](superpowers/specs/2026-09-11-ampx-ui-design.md) deliberately ships **no** window magnetism. This document records what that costs, why the old system was retired rather than repaired, and the routes back if AmpX later wants it.
**Companion:** [`WINDOWING_REVIEW.md`](WINDOWING_REVIEW.md) — the 2026-08 review of the retired system.

---

## What AmpX has, and what it gives up

The UI spec makes the **single-window module stack** the primary host. Modules reorder, collapse, tear off into plain windows, and re-dock by being dragged back onto the stack. A detached window is an ordinary macOS window: it does not attract, snap to, or move with any other window.

What that gives up, relative to classic Winamp and the retired implementation:

- **Free-floating magnetic clusters** — arranging the main window, EQ and playlist as a snapped group *anywhere on screen*, in arbitrary topology (side-by-side, L-shaped, stepped), not just as one vertical stack
- **Group drag** — moving one window of a cluster and having the rest follow
- **Edge-of-screen snapping** — the window sticking to display edges

The first is the real loss. A single stack expresses one topology; magnetism expresses many.

## Why the old system was retired, not repaired

From `WINDOWING_REVIEW.md`, the failures were structural rather than incidental:

1. **Manual per-window frame bookkeeping.** The manager moved N windows itself instead of using native grouping, so docked panels trailed the dragged window by roughly a frame. Identified in the review as "the recurring root cause".
2. **Geometry-primary docking.** The parent/child tree was *derived* from where windows happened to sit. Toggling the EQ could corrupt the stack, and dock anchors went stale.
3. **Order had no model.** An ordered stack model with a reorder menu (findings M2/M3) was implemented and then **deleted** when docking went geometry-primary — leaving no order to reorder or persist.

The new architecture inverts (2) and (3): order is an explicit `[AmpXModuleID]` array that *is* the truth, and layout is arithmetic inside one view. Any future magnetism should be built on top of that inversion, never by reintroducing derived state.

## Options

Ordered cheapest first. They are broadly additive — 1 is a precondition for 3, and 4 subsumes 2.

### Option 1 — Snap-on-drop only

When a detached window is released with an edge within a threshold (≈15 pt) of another AmpX window's edge, align it exactly once. No tracking during the drag, no group movement, no persisted relationship.

- **Cost:** small. One pure function (`snappedOrigin(for:against:threshold:)`) plus a hook in `windowDidEndLiveResize` / drag end.
- **Gains:** tidy alignment, which is most of the perceived benefit of magnetism.
- **Limits:** windows do not move together; a snapped pair is only coincidentally adjacent.
- **Risk:** very low. No shared state, nothing to go stale.

### Option 2 — Multiple stacks

Dropping a module onto a detached module's window promotes that window to a second `AmpXModuleStackView`. Users get grouping — say Player+EQ in one window, Playlist+ENTHEA in another — with the same reorder, collapse and insertion-marker code.

- **Cost:** low–moderate. The stack host becomes multi-instance; `AmpXLayoutStore` persists a list of stacks rather than one.
- **Gains:** genuine multi-cluster arrangement **with no magnetism at all**, because grouping is expressed by containment rather than by proximity. Everything already unit-tested keeps working.
- **Limits:** clusters are still vertical stacks; no side-by-side topology.
- **Risk:** low. No new coordination problem — this is the honest way to get most of what magnetism was for.

### Option 3 — Live magnetism via native child windows

Track proximity during a drag, snap live, and express the relationship with `NSWindow.addChildWindow(_:ordered:)` so **AppKit moves the group**, eliminating the frame-lag class of bug by construction. This is the review's own recommendation ("Adopting parent-child windows collapses several findings into one fix").

- **Cost:** moderate. Proximity model, live drag tracking, attach/detach of child relationships, persistence of the cluster graph.
- **Gains:** true Winamp-style clusters with correct group drag.
- **Limits:** child windows inherit level and ordering semantics that must be reconciled with full-screen, Spaces, and the ENTHEA theater mode.
- **Risk:** moderate. The hard requirement: the cluster graph must be **explicit persisted state**, never derived from geometry — otherwise failure mode (2) returns.

### Option 4 — Full Webamp-parity magnetic clustering

Arbitrary topology (side-by-side, L-shaped, stepped), screen-edge snapping, multi-display awareness, and cluster-aware windowshade. Builds on Option 3.

- **Cost:** high. This is the most intricate part of Winamp's window manager and the part the previous attempt did not finish.
- **Gains:** full fidelity to the original UX.
- **Limits:** the interaction is unfamiliar to most macOS users and needs discoverability work to be an asset rather than a curiosity.
- **Risk:** high. Should not be attempted without Option 3 shipped and stable, and without manager-level integration tests (the review's outstanding W9).

## Recommendation, if this is ever revisited

**Option 2 first, then reassess.** Multi-stack windows deliver the practical goal — several groups of modules arranged where the user wants — while adding no coordination problem at all. Only if users specifically ask for *non-vertical* clusters or free-floating magnetic arrangement is Option 3 worth its cost, and Option 1 is a cheap independent improvement that can land at any time.

## Prerequisites for any of them

Whichever route is taken, these hold:

1. **No derived state.** Relationships are explicit, persisted data. Nothing about grouping may be inferred from window frames.
2. **Native grouping for movement.** If windows must move together, `addChildWindow` does it — not manual frame bookkeeping in a drag loop.
3. **Pure geometry core.** Snap and proximity maths live in a pure, unit-tested type with no `NSWindow` dependency, as `AmpXWindowSnap` correctly did.
4. **Manager-level integration tests.** The review's W9 was never finished; the failures that shipped last time were orchestration failures, which unit tests on the pure core cannot catch.
5. **Modules stay host-agnostic.** `AmpXModuleContent` must never learn about windows. Every option above is a change to hosting only.
