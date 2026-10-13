# Quick start (Lite)

## Install

1. Copy `addons/weather/` into your project.
2. Project Settings, Plugins, enable **Weather System (Lite)**.
3. The `WeatherManager` autoload is registered for you.

## Pick the weather

Open **Weather · Setup** on the right of the editor. Pick one of the six states,
choose "This 3D scene" or "This 2D scene", press Apply. Press Apply again any
time. It updates what is there rather than adding a second copy.

From code (optional), to change the weather while the game runs:

```gdscript
WeatherManager.set_state("storm", 2.0)   # blend in over two seconds
WeatherManager.set_intensity(0.8)
WeatherManager.force_clear()
```

## Restyle it

The **Weather** tab below the setup dock is a slider wall. Pick a state, move the
sliders, press Save. It writes a profile to `res://weather/`. States you do not
touch keep the built-in look.

## Show it to the player

Tick **Show the weather to the player** in **Weather · Setup** before you press
Apply. It adds a small readout ("Rain, heavy") in the bottom-right corner, on
its own CanvasLayer drawn above the weather, so the tint never covers it. Apply
again and it stays one readout. With "Whole game" picked, it goes into the scene
you have open. While a Dialogue (Lite or Pro) conversation is on screen the
readout steps aside, so it never sits over the dialogue box, and comes back when
it ends. Untick `hide_during_dialogue` on it to keep it up.

If you place a `WeatherUI` in your own HUD instead, keep that HUD on a
CanvasLayer with a higher `layer` than the `Weather2D`, or the weather tint sits
over it.

## Demos

Press F5, or open `demo/weather_demo_2d.tscn`. Keys 1 to 6 pick a weather.

## What this edition does not do

The weather stays where you put it. It does not roll on by itself, does not
forecast, is not saved with your game, and does not affect gameplay. The full
version adds all four.
