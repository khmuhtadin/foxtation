# Fox mascot

The white fox that flies in and sits in the dictation pill.

| Path | What |
|---|---|
| `source/*.png` | Original poses, 1254 px, transparent. Edit or replace these. |
| `tools/clean_poses.py` | Removes stray speckles, trims, and writes 512 px copies to `Resources/Fox/`. |
| `../../Resources/Fox/*.png` | The cleaned poses the app bundles. Generated — don't edit by hand. |
| `../../docs/hud/storyboard.png` | The motion storyboard the HUD animation follows. |

| Pose | Storyboard scene |
|---|---|
| `face` | 1 · face, and 8–10 · seated in the pill |
| `emerge-wave` | 4 · emerges and waves |
| `fly-out` | 5 · flies out toward the viewer |
| `fly-back` | 6 · loops back |
| `swing-in` | 7 · swings back into the pill |
| `dash` | spare in-between, unused |

Regenerate after changing a source pose:

```sh
cd assets/mascot
uv run --with pillow tools/clean_poses.py emerge-wave=source/emerge-wave.png fly-out=source/fly-out.png \
    fly-back=source/fly-back.png swing-in=source/swing-in.png dash=source/dash.png face=source/face.png
```
