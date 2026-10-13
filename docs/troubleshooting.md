# Troubleshooting (Lite)

## I pressed Apply and nothing happens in game

Check the plugin is enabled in Project Settings, Plugins. The `WeatherManager`
autoload only appears once it is.

## The rain moves with the camera instead of falling past it

The shipped drivers use world-space particles so this cannot happen. If you built
your own emitter, turn `local_coords` off.

## My day and night cycle stopped working when I added weather

Something in your scene is a second CanvasModulate. A canvas honours one, and the
last one added wins. `Weather2D` is a CanvasLayer for exactly this reason, so
check for another CanvasModulate you added by hand.

## My HUD is tinted by the weather

Put the HUD on a CanvasLayer with a higher `layer` number than the `Weather2D`.
The readout that **Show the weather to the player** adds is already above it.
In 3D the tint sits on layer -1, so only a HUD on a CanvasLayer below 0 picks it up.

## Fog looks like nothing in 2D

Check `drive_haze` is on. A tint can only darken, so 2D fog needs the haze layer
to wash the scene out. Raise `haze_scale` for more.

## The weather never changes on its own

That is the full version. This edition draws the weather you pick.
