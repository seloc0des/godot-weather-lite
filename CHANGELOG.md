# Changelog

## 1.2.4 (2026-10-12)

The tabs show their names on Godot 4.5.

- **The Weather · Setup and Weather tabs were blank on Godot 4.5.** Their tabs beside the Inspector
  had no title, so "open the Weather · Setup tab" pointed at nothing. They are named when the pack
  switches on now. Godot 4.7 was not affected.

## 1.2.3 (2026-09-28)

No warning after saving a look.

- **No "invalid UID" warning on the first Play after saving a look in the Weather tab.** Godot
  hadn't registered the new file yet, which put a yellow Debugger badge on screen.

## 1.2.2 (2026-09-27)

Installs without errors.

- **No red errors when you install it.** Installing it filled the Output panel with "Failed to
  load script" errors for its demo and self-test before you'd even switched it on. They named a
  part of the pack that only exists once the pack is on.
- **Both tabs fit and scroll.** On smaller screens or at a bigger editor scale the bottom of the
  Setup and Weather tabs could fall off the screen with no way to scroll to it. Both now scroll, and
  long tick box labels wrap instead of widening the panel.

## 1.2.1 (2026-09-27)

A storm that looks like a storm.

- **Storm was a pale haze in 3D.** Its fog used the same light grey as the other states, so
  over a sunny scene a storm looked like light fog with rain in it. Storm now has its own dark
  slate fog. A Storm look you saved yourself in the Weather tab keeps its own colour.
- **You couldn't see the lightning.** A strike lit the ground, but in a storm the fog is most
  of the picture, so the flash hardly showed. It now lights the fog as well, and the whole
  view flashes.
- **A storm didn't darken a sunny 3D scene.** Each state's tint only worked in 2D. Weather3D
  now lays it over the view the same way, so a storm turns a sunlit scene grey-blue, and a
  strike lifts it for a moment. It never touches your lights, so it works alongside Day/Night.
  Untick **Drive Tint** on the Weather3D node to turn it off.

## 1.2.0 (2026-09-26)

Pressing Play right after the Setup tab now runs what it added.

- **Apply added weather you couldn't see in the game.** The Setup tab put the Weather3D or
  Weather2D node straight into your scene without going through Godot's undo system, so the
  editor never marked the scene as changed. Press Play and Godot saved nothing and ran the
  scene as it was on disk, with no weather in it. It only worked if you happened to press
  Ctrl+S first. The Setup tab, and "Apply to scene" in the tuner, now mark the scene as
  changed, so Play includes what they did.
- **The weather node stays put in the editor, and has a name.** The Setup tab built it in a
  way that ran its game code inside the editor, so it followed the camera there, and that
  position, plus a default profile it made for itself, were saved into your scene. It showed
  in the Scene tree as something like `@Node3D@19885`. It's now added the way a node you
  add by hand is (quiet until you press Play) and it's called Weather3D or Weather2D.
- **The Weather tuner works every time you open the project.** Once the profile file existed, the
  tuner failed in each new editor session: its sliders didn't load and edits didn't land.
- **Moving a slider changes only that setting**, so a look you changed in the Inspector survives the
  next slider move, and a new profile links to its file after Save.
- **A new look starts from the built-in one**, so rain, storm and snow keep their particle texture
  and sounds. Authoring a look on an empty profile no longer fails with a read-only error.
- **Nodes the Setup tab adds get readable names.** A second one under the same parent is
  called something like `UILayer2`, instead of a generated name full of `@` signs.
- **"Show the weather to the player"** on Weather · Setup adds a small readout in the
  bottom-right corner, drawn above the weather. No layer to set by hand, and it hides during a
  conversation.
- **A re-Apply says it updated the existing weather node** instead of "Added".
- **Switching the plugin off only removes the autoload if the plugin added it**, and closing
  the editor no longer removes it at all. A project that declares it itself, like the starter
  kits, keeps it.

## 1.1.0 (2026-09-09)

Lightning now has its own light, so a storm actually flashes.

- **The flash used to be invisible in any project with a day/night cycle.** Weather added
  energy to the scene's sun for an eighth of a second and put it back afterwards. That
  works on its own and fails the moment anything else drives that same light. A day/night
  system rewrites the sun every tick, so the flash survived one frame at most and a storm
  looked like it simply had no lightning. Nobody reports that, because there is nothing to
  see.
- **Weather owns the light it flashes now** and never touches yours. It is created on the
  first strike, aimed the same way as your sun so the flash lights the world from a
  direction that makes sense, and it fades rather than cutting out. Shadows are off on it:
  Godot really only does one directional shadow well, and a second one popping in for an
  eighth of a second costs more than it adds.
- **Three new settings**, `lightning_energy`, `lightning_color` and `lightning_flash_time`,
  on the Weather3D node. `sun_path` still does what it did, and is now only used to point
  the flash the same way.

## 1.0.0 (2026-09-01)

First release of the free edition.

- Six states: clear, cloudy, rain, storm, snow, fog, with wind on every state
- 2D and 3D drivers, both camera-aware, with wind and fog
- Per-state look profile and a slider-wall dock to author it
- No-code setup dock
- A weather readout for your HUD
- Two demos
- No third-party art. Both particle textures are generated
