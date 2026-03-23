# Hexball-Style 2D Football Game in Godot

## V1 Design Documentation, Technical Roadmap, and Production Plan

---

## 1. Project Overview

### Working Title

**Hexball Prototype / V1**

### Genre

* 2D top-down arcade football game
* Real-time multiplayer-inspired control feel, initially implemented as a local prototype / offline gameplay foundation

### Core Goal of V1

Build a **clean, professional, extendable first version** of a Haxball-like 2D football game in Godot, with:

* controllable circular player characters
* two teams (Red and Blue)
* a physics-driven or physics-simulated ball
* visible field and goals
* goal detection and score system
* match timer
* reset-after-goal flow
* strong gameplay feel
* modular code architecture for future features

This V1 should not be a throwaway prototype. It should be built as a **production-ready foundation** for later additions such as:

* abilities / skills
* AI bots
* online multiplayer
* lobby system
* multiple arenas
* game modes
* power-ups
* ranked or custom match systems

---

## 2. Product Vision

The game should feel like:

* easy to start
* hard to master
* responsive
* readable at a glance
* satisfying during collisions, shots, steals, and goals

The main appeal is not realism. The appeal is:

* immediate control
* clean physics interactions
* smart positioning
* momentum-based play
* team coordination
* mechanically expressive movement

So the design direction is:

**Arcade football with competitive clarity.**

---

## 3. V1 Design Pillars

All implementation decisions should support these pillars.

### 3.1 Readability First

The player must instantly understand:

* where the ball is
* which team each player belongs to
* where the goals are
* current score
* remaining time
* when a goal has happened

### 3.2 Tight Controls

Movement must feel:

* responsive
* predictable
* low latency
* easy to tune

### 3.3 Stable Core Simulation

The ball, players, collisions, goals, and resets must behave consistently.

### 3.4 Modular Architecture

Every gameplay system should be separated enough that later additions do not require rewriting the whole project.

### 3.5 Strong V1 Foundation

Even before advanced features, the first version should already feel polished through:

* small juice elements
* proper UI
* clean state transitions
* good parameter tuning
* reusable scene structure

---

## 4. Game Analysis of the Reference Style

From the provided image and the intended Haxball-style direction, the main structural elements are:

### 4.1 Arena Layout

The field is a rectangular top-down football pitch with:

* outer boundary walls
* center line
* center circle
* goals placed on left and right sides
* open goal mouths instead of full closed rectangular posts

### 4.2 Actors

There are three key entity categories:

#### Players

* circular body
* team-colored fill
* border outline
* simple name label
* moves with direct input
* interacts by colliding with the ball

#### Ball

* circular
* neutral white color
* central object of play
* reacts to player collisions and movement direction

#### Goals

* invisible scoring zone plus visible post/wall geometry
* ball crossing goal plane triggers score event

### 4.3 Match Loop

The loop is:

1. match starts
2. players and ball spawn/reset
3. players contest possession
4. ball enters a goal
5. score updates
6. short goal pause / celebration state
7. reset to kickoff positions
8. continue until timer ends
9. winner or draw result shown

This is the minimal complete match loop needed for V1.

---

## 5. V1 Scope Definition

To keep the first version high quality and realistically buildable, V1 should include the following.

### 5.1 In Scope

* 2D top-down pitch
* 1v1 or 2v2 local controllable match setup
* red team and blue team
* player movement
* ball physics / ball motion simulation
* player-ball collision
* wall collision
* goal scoring
* scoreboard
* match timer
* reset system
* win / lose / draw result state
* simple main menu
* pause menu
* basic sound hooks
* debug tools for testing gameplay values

### 5.2 Optional but Recommended for V1.1 or polished V1

* kick / shoot button
* dash button
* possession feel tuning
* gamepad support
* replay-like goal camera pause
* simple bot opponent

### 5.3 Out of Scope for initial V1

These should not be built first unless the core is already stable:

* online multiplayer
* matchmaking
* cosmetics system
* ranked mode
* advanced character stats
* inventory systems
* large-scale UI systems
* overly complex skill trees

---

## 6. High-Level Gameplay Specification

### 6.1 Match Format

Initial recommendation:

* support **1v1 first**
* architect systems so expanding to **2v2 and beyond** is easy

Reason:

* 1v1 is faster to debug
* collision and ball ownership are easier to tune
* goal/reset logic becomes easier to validate
* movement feel can be polished before team complexity grows

### 6.2 Camera

* fixed top-down camera
* centered on pitch, not on player
* no camera rotation
* no zoom changes in V1

Reason:

* competitive readability
* stable UI layout
* simpler implementation

### 6.3 Controls

Each player should have:

* move up
* move down
* move left
* move right
* optional kick / shoot
* optional dash

For the first controlled prototype:

* Player 1: keyboard
* Player 2: alternate keyboard keys or gamepad

### 6.4 Ball Interaction

There are two good approaches.

#### Option A: Pure collision-driven ball

* ball moves due to physical contact only
* simple and elegant
* very Haxball-like
* less control over shot expressiveness

#### Option B: Collision + kick impulse

* player body collision moves ball
* dedicated kick button adds an impulse if ball is in range
* better gameplay depth
* easier to create satisfying shots and passes

**Recommended for V1:**
Use **collision + kick impulse**.
This gives both authentic contact play and more satisfying football interactions.

### 6.5 Goal Logic

A goal is scored when:

* the ball fully enters the scoring area
* or crosses a properly defined goal trigger zone

Best implementation approach:

* visible goal posts/walls for physical structure
* a dedicated invisible `GoalArea` trigger behind the goal mouth
* score only when the **ball** enters this trigger

### 6.6 Win Condition

At minimum:

* fixed match timer, for example 90 seconds or 120 seconds
* when time reaches zero:

  * highest score wins
  * equal score becomes draw

---

## 7. Core Systems Breakdown

This is the most important part of the architecture.

### 7.1 Game State System

The game should not be controlled by random booleans spread across scripts. Use an explicit game state machine.

Suggested states:

* `BOOT`
* `MAIN_MENU`
* `MATCH_INTRO`
* `KICKOFF`
* `PLAYING`
* `GOAL_SCORED`
* `MATCH_ENDED`
* `PAUSED`

#### Responsibilities

* control when player input is accepted
* control when timer runs
* control when reset happens
* control UI visibility
* prevent bugs like scoring during reset or movement during pause

### 7.2 Match Manager

The `MatchManager` is the central coordinator of one active match.

Responsibilities:

* spawn and reset players and ball
* hold match timer
* hold score data
* listen for goals
* transition game states
* notify UI
* notify audio/effects hooks

This should become the most important gameplay orchestrator.

### 7.3 Player Controller

Each player entity should be responsible for:

* reading input from an assigned input profile
* accelerating / decelerating movement
* rotating visuals if needed later
* interacting with ball
* exposing team and player ID
* being reset to spawn position

The controller should **not** manage global score or timer.

### 7.4 Ball Controller

The ball should be its own isolated system.

Responsibilities:

* movement and velocity
* drag/friction
* collision reaction
* receiving kick impulses
* reset to center
* exposing last touch data if needed later

### 7.5 Goal System

Each goal should be a dedicated scene.

Responsibilities:

* know which team it belongs to
* detect when the ball enters
* emit `goal_scored(scoring_team, conceding_team)` event

### 7.6 UI System

UI should be independent from gameplay scene logic.

Responsibilities:

* score display
* timer display
* state text (Goal!, Blue Scores!, Draw!, etc.)
* pause overlay
* end match overlay

UI should respond to signals or match manager events.

### 7.7 Audio Hooks

Even if you do not add full audio now, design for it.

Hooks for:

* kick
* ball hit wall
* goal scored
* countdown end
* menu click

---

## 8. Recommended Technical Approach in Godot

## 8.1 Engine Version

Recommended baseline:

* **Godot 4.4.x**

### 8.2 Node Philosophy

Use small, focused scenes.
Avoid giant all-in-one scenes with deeply coupled scripts.

### 8.3 Physics Recommendation

For this kind of game, you have two main paths:

#### Path A: Use built-in physics bodies heavily

* `CharacterBody2D` for players
* `RigidBody2D` for ball
* static bodies for walls/goals

#### Path B: Controlled custom kinematic-style simulation

* `CharacterBody2D` players
* ball simulated in a custom controller
* more deterministic feel

**Recommended hybrid for V1:**

* Players: `CharacterBody2D`
* Ball: either `RigidBody2D` or a custom velocity-based `CharacterBody2D`

Best practical recommendation for your project:

### Use:

* `CharacterBody2D` for players
* **custom ball controller** using `CharacterBody2D` or `Area2D + manual velocity` logic if you want full control

Reason:

* Haxball-style games need very tunable feel
* pure rigidbody physics can feel slippery, unpredictable, or harder to tune
* custom simulation gives better gameplay control

If you are less experienced, the safest path is:

* start with ball as `CharacterBody2D`
* manage `velocity`, `move_and_slide()`, and manual damping
* add kick impulse and collision response through code

This is usually easier to make game-feel good.

---

## 9. Proposed Scene Architecture

## 9.1 Root Scene Strategy

Use a root app scene that can switch between screens.

### Main root

* `App.tscn`

Children might include:

* current screen container
* global UI layer
* audio manager
* scene loader / transition node

### Main screens

* `MainMenu.tscn`
* `Match.tscn`

---

## 10. Recommended Folder Structure

A clean structure is essential from the beginning.

```text
res://
  Assets/
    Art/
      Field/
      UI/
      Players/
      Ball/
      Icons/
    Audio/
      SFX/
      Music/
    Fonts/
  Autoload/
    GameEvents.gd
    GameSettings.gd
    SceneRouter.gd
  Data/
    Config/
      gameplay_tuning.tres
      team_definitions.tres
    Definitions/
      match_rules.gd
      enums.gd
  Scenes/
    App/
      App.tscn
      App.gd
    Menus/
      MainMenu.tscn
      MainMenu.gd
      PauseMenu.tscn
      PauseMenu.gd
      EndMatchPanel.tscn
      EndMatchPanel.gd
    Match/
      Match.tscn
      Match.gd
      Pitch.tscn
      Pitch.gd
      SpawnSystem.tscn
      SpawnSystem.gd
    Entities/
      Player/
        Player.tscn
        Player.gd
        PlayerInput.gd
        PlayerVisual.gd
      Ball/
        Ball.tscn
        Ball.gd
      Goal/
        Goal.tscn
        Goal.gd
      Arena/
        BoundaryWall.tscn
        GoalPost.tscn
    UI/
      Hud/
        MatchHUD.tscn
        MatchHUD.gd
      Widgets/
        ScoreDisplay.tscn
        TimerDisplay.tscn
        AnnouncementBanner.tscn
    Systems/
      MatchManager/
        MatchManager.gd
      StateMachine/
        MatchStateMachine.gd
      ResetSystem/
        ResetSystem.gd
      ScoringSystem/
        ScoringSystem.gd
      TimeSystem/
        TimeSystem.gd
      Input/
        InputProfiles.gd
      Debug/
        DebugOverlay.tscn
        DebugOverlay.gd
  Scripts/
    Core/
      SignalBus.gd
      Helpers.gd
      MathUtils.gd
    Components/
      VelocityMotor2D.gd
      CooldownComponent.gd
      TeamComponent.gd
  Tests/
    Sandbox/
      BallTuning.tscn
      CollisionTuning.tscn
```

---

## 11. Why This Folder Structure Works

### Assets

Raw content grouped by medium.

### Autoload

For truly global services only.
Do not dump gameplay logic here.

### Data

For tunable values and reusable configuration.

### Scenes

All scene files grouped by feature.

### Systems

Central gameplay systems separate from entity-specific code.

### Scripts/Core

Utility scripts used by multiple systems.

### Tests

Small isolated test scenes to tune gameplay faster without running the full game every time.

---

## 12. Naming Conventions

Use consistent naming from day one.

### Files

* `PascalCase` for scene and script filenames
* examples: `Player.gd`, `MatchHUD.tscn`, `MatchManager.gd`

### Variables

* `snake_case`
* example: `move_speed`, `kick_cooldown`, `red_score`

### Constants

* `UPPER_SNAKE_CASE`
* example: `MAX_PLAYERS`, `DEFAULT_MATCH_TIME`

### Signals

Use descriptive verb-first names.

* `goal_scored`
* `match_started`
* `match_ended`
* `ball_kicked`

### Methods

Use clear action names.

* `reset_match()`
* `spawn_players()`
* `apply_kick_impulse()`

---

## 13. Scene-by-Scene Breakdown

## 13.1 `App.tscn`

### Purpose

Top-level application shell.

### Responsibilities

* load first screen
* transition between menu and match
* hold global overlays if needed

### Should not do

* direct ball logic
* direct player movement logic

---

## 13.2 `MainMenu.tscn`

### Purpose

Start screen.

### V1 Buttons

* Play Match
* Quit

### Later expansion

* Settings
* Team select
* Arena select
* Online / Local mode

---

## 13.3 `Match.tscn`

### Purpose

Main gameplay container.

### Suggested child structure

```text
Match
  World
    Pitch
    BoundaryWalls
    Goals
    PlayersContainer
    BallSpawn
  Managers
    MatchManager
    ResetSystem
    ScoringSystem
    TimeSystem
  CanvasLayer
    MatchHUD
    PauseMenu
    EndMatchPanel
  Debug
    DebugOverlay
```

### Responsibilities

* contain all match-related objects
* wire systems together

---

## 13.4 `Player.tscn`

### Suggested nodes

```text
Player (CharacterBody2D)
  CollisionShape2D
  VisualRoot (Node2D)
    BodySprite or BodyDraw
    NameLabel
```

### Responsibilities

* movement
* input handling
* team color assignment
* kick attempts
* reset position

### Exported tunables

* `player_id`
* `team_id`
* `move_speed`
* `acceleration`
* `deceleration`
* `kick_strength`
* `kick_range`
* `kick_cooldown`

---

## 13.5 `Ball.tscn`

### Suggested nodes

```text
Ball (CharacterBody2D)
  CollisionShape2D
  VisualRoot (Node2D)
    Sprite2D or custom draw
```

### Responsibilities

* maintain velocity
* react to hits
* apply drag
* bounce from walls
* be reset to center

### Exported tunables

* `radius`
* `max_speed`
* `drag`
* `bounce_factor`
* `mass_simulation_factor`

---

## 13.6 `Goal.tscn`

### Suggested nodes

```text
Goal (Node2D)
  LeftPost (StaticBody2D)
  RightPost (StaticBody2D)
  BackWall (optional depending on geometry)
  GoalArea (Area2D)
```

### Responsibilities

* represent physical goal structure
* detect ball entry
* emit score signal

### Exported tunables

* `defending_team`
* `goal_id`

---

## 13.7 `MatchHUD.tscn`

### Elements

* red score
* blue score
* timer
* central announcement text
* pause overlay
* end match panel

---

## 14. Input Design

## 14.1 Input Map

Set up in Godot Project Settings > Input Map.

### Player 1

* `p1_up`
* `p1_down`
* `p1_left`
* `p1_right`
* `p1_kick`
* `p1_dash` (future-ready)

### Player 2

* `p2_up`
* `p2_down`
* `p2_left`
* `p2_right`
* `p2_kick`
* `p2_dash`

### Global

* `pause`
* `accept`
* `cancel`

### Important design rule

Do not hardcode keyboard keys directly in gameplay scripts.
Always read named actions.

---

## 15. Movement Design

Player movement is one of the most important feel systems.

### Requirements

* fast response
* no muddy input
* smooth diagonal movement
* speed consistency in all directions

### Recommended movement model

* read 2D input vector
* normalize it
* accelerate toward target velocity
* decelerate when no input
* move using `move_and_slide()`

### Why not instant velocity only?

Because a small amount of acceleration/deceleration gives a more polished and controllable feel.

### Initial tuning targets

These are placeholders and should be tuned in sandbox scenes.

* move speed: medium-high
* acceleration: high
* deceleration: high
* low drift

The players should feel agile, not floaty.

---

## 16. Ball Design

The ball is the heart of the game.

### V1 Ball Feel Goals

* should move smoothly
* should clearly respond to hits
* should slow down over time
* should not feel too heavy or too chaotic
* should support precise player control

### Ball forces to model

* current velocity
* impact impulse from player body
* kick impulse from kick action
* friction / damping
* wall bounce

### Recommended ball rules

* cap max speed
* apply drag every frame
* preserve momentum enough for satisfying passes/shots
* do not over-bounce excessively

### Last touch tracking

Very useful to store:

* `last_touch_player_id`
* `last_touch_team_id`

This helps later with:

* own goal logic
* assists
* stat tracking
* replays

---

## 17. Collision Philosophy

### 17.1 Player vs Wall

* players must never leave the arena
* response must be stable and not jittery

### 17.2 Ball vs Wall

* ball should bounce or reflect with tunable energy loss

### 17.3 Player vs Ball

There are two interaction layers:

1. passive body collision
2. active kick input

### 17.4 Player vs Player

For V1, keep it simple:

* enable physical separation
* avoid extreme knockback first
* later add bump / shoulder mechanics

This keeps the first version stable.

---

## 18. Goal Detection Design

### Safe implementation

Each goal should have:

* visible physical posts
* a `GoalArea` trigger placed behind the mouth of the goal

When the ball enters `GoalArea`:

* verify match state is `PLAYING`
* verify body is ball
* emit score event once
* lock duplicate triggering

### Anti-bug rule

After a goal is detected:

* immediately switch state away from `PLAYING`
* disable repeated scoring until reset completes

---

## 19. Match Flow Design

## 19.1 Start of Match

Sequence:

1. load arena
2. spawn players
3. spawn ball at center
4. show countdown: `3, 2, 1, GO!`
5. enable input
6. enter `PLAYING`

## 19.2 During Play

* timer decreases
* score visible
* all actors active
* pause allowed

## 19.3 On Goal

Sequence:

1. scoring signal received
2. freeze gameplay input
3. show announcement
4. update score
5. short delay
6. reset players to spawn points
7. reset ball to center
8. kickoff countdown
9. return to `PLAYING`

## 19.4 Match End

Sequence:

1. timer reaches zero
2. set state to `MATCH_ENDED`
3. freeze gameplay
4. show result panel
5. allow restart or return to menu

---

## 20. State Machine Design Details

Suggested enum:

```gdscript
enum MatchState {
    BOOT,
    MATCH_INTRO,
    KICKOFF,
    PLAYING,
    GOAL_SCORED,
    PAUSED,
    MATCH_ENDED
}
```

### Transition Rules

* `BOOT -> MATCH_INTRO`
* `MATCH_INTRO -> KICKOFF`
* `KICKOFF -> PLAYING`
* `PLAYING -> GOAL_SCORED`
* `GOAL_SCORED -> KICKOFF`
* `PLAYING -> PAUSED`
* `PAUSED -> PLAYING`
* `PLAYING -> MATCH_ENDED`

### Why this matters

A formal state machine prevents common problems such as:

* timer running during pause
* players moving during countdown
* double scoring
* goals after match end

---

## 21. Data Model

Use clean, minimal structured data.

### Match data

* red score
* blue score
* remaining time
* current state
* winner team or draw

### Player runtime data

* player id
* team id
* display name
* spawn position
* current velocity
* input enabled

### Ball runtime data

* current velocity
* last touch player id
* last touch team id

---

## 22. Recommended Autoloads

Use autoloads sparingly.

### `GameEvents.gd`

A signal bus for global events if needed.
Possible signals:

* `match_started`
* `goal_scored`
* `match_ended`
* `pause_toggled`

### `GameSettings.gd`

Global configuration such as:

* default match time
* audio volume
* debug flags

### `SceneRouter.gd`

Optional helper for changing scenes cleanly.

Avoid storing active match logic globally if it only belongs inside a single match.

---

## 23. System Responsibilities in Detail

## 23.1 `MatchManager.gd`

Should manage:

* state transitions
* references to players, ball, goals, UI
* score changes
* time updates
* reset calls

Should not directly read raw keyboard keys.

## 23.2 `ScoringSystem.gd`

Can be separate or merged into `MatchManager` in early V1.

Responsibilities:

* receive goal events
* increment correct team score
* request UI update
* request reset

## 23.3 `TimeSystem.gd`

Responsibilities:

* countdown timer
* pause-safe ticking
* end match at zero

## 23.4 `ResetSystem.gd`

Responsibilities:

* reset players to spawn points
* reset ball to center
* clear motion
* restore kickoff layout

This is worth isolating because reset bugs are common in sports games.

---

## 24. Visual Design Direction for V1

Keep the visual style simple and clean.

### Players

* colored circular bodies
* black outline
* optional initials or icon in center
* name label below

### Ball

* white circle with subtle outline

### Field

* green base
* alternating grass stripes
* bright white boundary lines
* center line
* center circle

### Goals

* clean black post lines or wall-like outlines similar to the reference

### UI

* dark rounded top scoreboard bar
* team color accents
* timer centered

### Effects

Minimal but effective:

* goal flash text
* tiny hit spark or scale pulse on strong kick
* countdown text animation

---

## 25. Audio Direction for V1

Even simple sound greatly improves game feel.

### Minimum sound list

* menu click
* kickoff beep
* kick hit
* wall bounce
* goal stinger
* end whistle

### Audio implementation note

Do not tightly couple audio inside entity logic.
Prefer event-based triggering or dedicated audio calls.

---

## 26. Debugging and Tuning Strategy

A professional build process requires debug tools.

### Add a debug overlay with:

* current match state
* ball velocity
* player velocity
* remaining time
* last touch team

### Add debug shortcuts for:

* reset ball
* reset match
* add red score
* add blue score
* toggle collision visuals

### Why this matters

Without debug tools, balancing movement and collisions becomes slow and frustrating.

---

## 27. Recommended Coding Principles

### 27.1 Keep scripts small

If one script starts doing too many unrelated jobs, split it.

### 27.2 Prefer signals over hard references where reasonable

Example:

* goal emits `goal_scored`
* match manager listens

### 27.3 Avoid magic numbers

Expose gameplay values as exported variables or config resources.

### 27.4 Separate gameplay rules from presentation

Score logic should not be embedded in the HUD.

### 27.5 Build for iteration

You will tune values a lot. Make that easy.

---

## 28. Suggested Exported Tuning Variables

## Player

* `move_speed`
* `acceleration`
* `deceleration`
* `kick_strength`
* `kick_range`
* `kick_cooldown`
* `body_push_strength`

## Ball

* `drag`
* `max_speed`
* `wall_bounce`
* `player_hit_multiplier`
* `kick_impulse_multiplier`

## Match

* `match_duration_seconds`
* `goal_pause_duration`
* `kickoff_countdown_duration`

These should all be easy to tweak in the editor.

---

## 29. V1 Milestone Roadmap

This roadmap is designed to be actually buildable.

## Milestone 0 — Pre-Production Setup

### Goal

Prepare a clean project structure before writing gameplay code.

### Tasks

* create Godot project
* define folder structure
* create naming conventions doc
* create main app scene
* create placeholder art style guide
* set input actions
* create base enums/constants script

### Deliverable

Project opens cleanly with menu scene and empty match scene.

---

## Milestone 1 — Arena Foundation

### Goal

Build the playable field and arena boundaries.

### Tasks

* create pitch scene
* draw field lines
* add center circle
* create boundary walls
* create visible goals with correct geometry
* test collision boundaries

### Deliverable

A static arena where test bodies cannot leave the play area.

---

## Milestone 2 — Player Controller

### Goal

Create responsive player movement.

### Tasks

* create `Player.tscn`
* add input profiles
* implement movement
* assign team color
* add name label
* support at least two local players

### Deliverable

Two controllable players can move smoothly in the arena.

---

## Milestone 3 — Ball Controller

### Goal

Implement a tunable ball.

### Tasks

* create `Ball.tscn`
* implement velocity system
* add drag
* add wall bounce
* add player contact reaction
* clamp max speed

### Deliverable

Ball moves naturally, bounces, and can be pushed around.

---

## Milestone 4 — Kick System

### Goal

Make football interactions satisfying.

### Tasks

* add kick input
* detect kick range
* apply kick impulse
* add cooldown
* add direction logic based on player input and ball position

### Deliverable

Players can intentionally pass and shoot.

---

## Milestone 5 — Goal and Score System

### Goal

Complete the basic loop.

### Tasks

* implement goal trigger
* prevent duplicate scoring
* update score data
* update UI score display
* add reset after goal

### Deliverable

Match can be played and goals properly update score.

---

## Milestone 6 — Match State and Timer

### Goal

Turn the sandbox into a real match.

### Tasks

* add state machine
* add kickoff countdown
* add match timer
* implement pause
* implement match end state

### Deliverable

A full start-to-finish match flow works.

---

## Milestone 7 — UI and Feedback Polish

### Goal

Make the game feel presentable.

### Tasks

* style scoreboard
* style timer
* goal banner animation
* result panel
* menu polish
* optional simple sounds

### Deliverable

V1 looks and feels like a complete polished prototype.

---

## Milestone 8 — QA and Tuning Pass

### Goal

Stabilize and improve feel.

### Tasks

* tune movement
* tune kick strength
* tune ball drag/bounce
* test edge-case goals
* test pause/resume bugs
* test reset consistency
* add debug tools

### Deliverable

Stable V1 ready for feature expansion.

---

## 30. Development Order Recommendation

The safest build order is:

1. project skeleton
2. arena and walls
3. one controllable player
4. second player
5. ball movement
6. player-ball interaction
7. kick mechanic
8. goals
9. score UI
10. timer and state machine
11. pause/end flow
12. polish and tuning

Do not start with menus, networking, or cosmetic features first.

---

## 31. Implementation Risks and Solutions

## Risk 1: Ball feels bad

### Cause

Using untuned physics or too much bounce/drift.

### Solution

Use a controlled custom ball implementation and sandbox tuning scenes.

## Risk 2: Reset bugs after scoring

### Cause

Poor state transitions and actors not fully zeroed.

### Solution

Dedicated reset system and explicit match states.

## Risk 3: Player controls feel slippery

### Cause

Too much acceleration smoothing or low deceleration.

### Solution

Prioritize responsiveness over realism.

## Risk 4: Code becomes messy too early

### Cause

Putting all logic into one `Match.gd` or `Player.gd`.

### Solution

Split by responsibility from the start.

## Risk 5: Feature creep

### Cause

Adding skills, bots, and online too soon.

### Solution

Lock V1 scope and finish the full gameplay loop first.

---

## 32. Future-Ready Extension Points

The architecture should anticipate future systems.

### 32.1 Skills System

Later you may add:

* sprint
* dash
* power shot
* shoulder charge

To support this cleanly later:

* keep input modular
* use cooldown components
* separate base movement from special ability logic

### 32.2 AI Bots

To support bots later:

* player controller should accept input from either human or AI source
* do not tightly bind player logic to keyboard input only

### 32.3 Online Multiplayer

For future networking:

* keep simulation rules deterministic where possible
* separate input from simulation
* minimize UI/gameplay coupling

### 32.4 Multiple Arenas

Make pitch dimensions and goal positions configurable instead of hardcoded.

---

## 33. Practical Documentation Standard for the Project

Each important script should begin with:

* purpose
* owned responsibilities
* dependencies
* what it should not control

Example:

```gdscript
## Player.gd
## Purpose: Controls local player movement, kick actions, and team identity.
## Owns: Movement, local input reading, kick requests, reset behavior.
## Does NOT own: Match score, timer, UI, global state transitions.
```

This habit keeps the codebase understandable.

---

## 34. Acceptance Criteria for V1

The first version is successful if all of these are true:

* the game launches into a working menu
* a match can start without errors
* two teams are visually distinct
* players move responsively
* the ball interacts consistently
* goals correctly update score
* resets work every time
* timer ends the match correctly
* result state is shown
* project structure remains clean and scalable

If these are met, V1 is a strong foundation.

---

## 35. Recommended First Coding Pass After This Document

After documentation approval, the implementation should begin in this exact order:

### Step 1

Create project structure and input map.

### Step 2

Create the pitch scene and collision boundaries.

### Step 3

Create a minimal player scene with movement.

### Step 4

Create the ball scene and basic collision response.

### Step 5

Connect goals, scoring, and reset.

### Step 6

Add state machine, timer, and polished UI.

This order minimizes rework.

---

## 36. Final Recommendation

Do not rush into advanced systems yet.

The best possible first version is not the one with the most features.
It is the one with:

* clean architecture
* strong feel
* stable gameplay loop
* room to grow

For this game, movement feel, ball behavior, goal flow, and match structure are the foundation. If those are excellent, every future feature becomes easier and better.

---

## 37. Next Production Document to Create

After this document, the next best document should be:

**“Hexball V1 Technical Implementation Spec”**

That document should define:

* exact node trees
* exact class responsibilities
* exact signal flow
* exact exported variables
* exact coding order scene by scene
* first production-ready GDScript files

---

## 38. Summary

This project should be built as a **modular 2D arcade football foundation**.

V1 should focus on:

* field
* players
* ball
* goals
* score
* timer
* reset flow
* polish

The architecture should be:

* readable
* maintainable
* tunable
* expansion-ready

If built according to this roadmap, the result will be much more than a rough prototype. It will be a real gameplay foundation ready for future systems.
