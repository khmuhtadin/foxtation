# Fox mascot

The white fox in the dictation pill. The app only uses the face; the other
poses are kept here as source art.

| Path | What |
|---|---|
| `source/*.png` | Original poses, 1254 px, transparent. Edit or replace these. |
| `tools/clean_poses.py` | Removes stray speckles, trims, and writes 512 px copies to `Resources/Fox/`. |
| `../../Resources/Fox/face.png` | The cleaned face the app bundles. Generated — don't edit by hand. |

Regenerate after changing the face:

```sh
cd assets/mascot
uv run --with pillow tools/clean_poses.py face=source/face.png
```
