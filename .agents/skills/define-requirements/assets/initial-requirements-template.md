# Initial Requirements

Use this document as the starting point for a new project before durable `docs/` files are created.

`define-requirements` should create or update this file only when the project-wide bootstrap spec is needed, after clarifying and agreeing on the requirements with the user.

Do not use this file as input to `prepare-steering`. Run `setup-project` first, then create later feature specs under `docs/ideas/YYYYMMDD-[feature-name].md`.

## Project Overview

- Project name:
- One-sentence summary:
- Problem to solve:

## Users

- Primary users:
- Usage context:
- Accessibility or age considerations:

## Product Goals

- Goal 1:
- Goal 2:
- Goal 3:

## In Scope

- Core feature 1:
- Core feature 2:
- Core feature 3:

## Out of Scope

- Non-goal 1:
- Non-goal 2:
- Non-goal 3:

## Screens

- Screen 1:
- Screen 2:
- Screen 3:

## Key Behaviors / Exceptions

- Main user flow and expected outcomes:
- Relevant data and user-visible state changes:
- Important errors, permission denial, and recovery behavior:

## Technical Constraints

- Language: Swift
- UI: SwiftUI
- Platform: native iOS
- IDE / build system: Xcode
- Xcode version, Swift language mode, minimum iOS version, and supported devices: follow the agreed values in `PROJECT_CONTEXT.md`; record unresolved values as open questions

## Development Rules

- The AI template repository does not need an app or Xcode project
- In an app repository without a project/workspace, guide the user to create an iOS App with SwiftUI and Swift in Xcode, then stop until it is available
- Codex must not generate the initial project or introduce a project generator
- Inspect the existing project/workspace, scheme, targets, available destinations, and test configuration before deciding build/test commands
- Do not hardcode project, scheme, or Simulator names
- Use the existing Xcode build/test setup; do not add external tools or dependencies without a task requirement and authorization
- Do not change agreed Xcode, Swift language mode, or minimum iOS settings automatically

## Device or Platform Features

- Sound:
- Haptics:
- Camera:
- Notifications:
- Offline support:

## Acceptance Criteria

- Describe observable results for agreed behaviors and important exceptions; do not leave example labels in confirmed requirements.
- Criterion 1:
- Criterion 2:
- Criterion 3:

## Open Questions

- Question 1:
- Question 2:
- Question 3:
