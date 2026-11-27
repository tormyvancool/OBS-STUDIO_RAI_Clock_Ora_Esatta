# RAI Clock Ora Esatta (OBS Studio Lua Script)

An OBS Studio Lua script that adds a custom video source rendering the iconic late-1970s RAI analog clock (*"Ora Esatta"*), with an optional spoken time announcement.

## Features

- **Custom OBS video source:** composites four PNG layers (dial, hour hand, minute hand, second hand) on a native `1920x1440` (4:3) canvas.
- **Real-time synchronization:** reads your local system clock and rotates the hands around the center pivot.
- **Continuous seconds hand:** the second hand sweeps smoothly instead of ticking once per second; the minute and hour hands move smoothly too.
- **Vocal announcement (optional):** at a time you choose, a countdown beep plays, followed by the spoken hour and minutes (for example *"13"* then *"12"* for 13:12).
- **Simple setup:** choose the announcement hour and minute from drop-down menus in the source's properties, and try it immediately with a **Test now** button.
- **Self-contained:** uses OBS Studio's built-in LuaJIT engine (`obslua`), with no external dependencies.

## Folder Structure

The script lives inside the `RAI-Clock-Ora-Esatta/` package folder, next to a second `RAI-Clock-Ora-Esatta/` folder that holds the assets. Keep this layout exactly:

```text
your-obs-scripts-folder/
    └── RAI-Clock-Ora-Esatta/              <- assets folder
        ├── RAI-Clock-Ora-Esatta.lua
        ├── LICENSE.txt
        ├── README.md
        ├── Audio/
        │   ├── Beep.wav
        │   ├── h00.wav ... h23.wav
        │   └── m01.wav ... m59.wav
        └── Images/
            ├── RAI-Clock-Dial.png
            ├── RAI-Clock-Hours.png
            ├── RAI-Clock-Minutes.png
            └── RAI-Clock-Seconds.png
```

## Installation & Setup

1. Copy the whole `RAI-Clock-Ora-Esatta/` package folder into your preferred OBS scripts folder.
2. Open **OBS Studio** and go to **Tools > Scripts**.
3. Click the **`+`** button at the bottom left, select `RAI-Clock-Ora-Esatta.lua` from inside the package folder, and click **Open**.
4. Close the Scripts window.
5. In your **Sources** dock, click **`+`** and select **RAI Clock Ora Esatta with Audio Announcement**.
6. Resize or position the `1920x1440` clock source in your scene as needed.

## Vocal Announcement

Double-click the clock source in your scene to open its properties:

| Setting | Description |
| --- | --- |
| **Enable vocal announcement** | Turns the announcement on or off. |
| **Announcement hour** | Hour of the announcement, `00`–`23`. |
| **Announcement minute** | Minute of the announcement, `00`–`59`. |
| **Test now** | Runs a full announcement starting in 8 seconds, so you can check levels and timing without waiting. |

### How it plays

1. **6 seconds before** the chosen time, `Beep.wav` is played once. It is a single pre-mixed 7-second file that already contains the whole beep pattern and ends exactly at the announcement time.
2. **At the chosen time**, `hXX.wav` is played, where `XX` is the hour in 24-hour format (13:00 plays `h13.wav`).
3. If the minute is not `00`, `mXX.wav` follows immediately (13:12 plays `h13.wav`, then `m12.wav`).
4. The announcement **repeats every day** at the same time.

### Audio files

- `Beep.wav`: exactly 6 seconds long, with the beep pattern prepared in your audio editor (for example, beeps at 0, 1, 2, 3, 4 and 6 seconds and silence at 5 seconds, so the last beep lands one second before the announcement).
- `h00.wav` … `h23.wav`: the spoken hours.
- `m01.wav` … `m59.wav`: the spoken minutes.

A missing file is skipped and reported in the script log (**Tools > Scripts > Script Log**).

### Audio routing

The announcement is sent to audio tracks 1–6, so it is heard on your stream and in your recordings. It is not played on your local monitoring device by default. To hear it locally as well, open the `.lua` file and set `MONITOR_LOCALLY = true`.

> **Note:** if you add several clock sources, the one whose properties you changed last decides the announcement time.

## Troubleshooting

- **Clock is blank:** check that the four PNG files are in `RAI-Clock-Ora-Esatta/Images/` and read the Script Log for "failed to load texture" messages.
- **No sound:** check that the files are in `RAI-Clock-Ora-Esatta/Audio/`, that **Enable vocal announcement** is ticked, and use **Test now** to confirm. Then check the Script Log for "missing audio file" messages.
- **Announcement is not heard on stream:** make sure your stream or recording uses one of audio tracks 1–6.

## Requirements

- **OBS Studio** with Lua scripting support enabled
- The `.lua` script, plus all PNG and WAV files inside the inner `RAI-Clock-Ora-Esatta/` assets folder (`Images/` and `Audio/`)

## How It Was Made

### The beep

Made in **Reaper**: a tone generator set to 1 kHz, with volume automation to create the beeps, then exported as a `.wav` file.

### The voice

The hour and minute announcements are **not** the original announcer's voice. I chose not to use AI to clone a voice: the original announcer is probably no longer with us, and cloning it would not feel morally right to me. There could also be legal issues I prefer to avoid. I used a free text-to-speech (TTS) service instead, although I couldn't find a voice similar to the original. I used Elevenlabs service.

### The graphics

All the graphics, the dial and the hands, were redrawn in **Affinity** in Vector mode, the same way I made them for my reconstruction videos on my second channel, [@RicordiDellaRAI](https://www.youtube.com/@RicordiDellaRAI).

### The code:

It was written within VSC

### The help of AI: where it came into the game

AI was used to help me to quickly solve some issue with the audio-announcment that wasn't starting at the moment I wanted, and to make the seconds-hand movement to be smoother.

## Author & License

- **Author:** Tormy Van Cool
- **License:** Creative Commons Attribution-NoDerivatives 4.0 International (**CC BY-ND 4.0**)

You are free to use and share this script and its artwork for any purpose with proper credit to **Tormy Van Cool**, provided you do not distribute modified versions. See `LICENSE.txt` for full details.

## Video

[![Watch the demo video](https://img.youtube.com/vi/Pk2-QNNwvgM/0.jpg)](https://www.youtube.com/watch?v=Pk2-QNNwvgM)

How it is once installed and recorded or streamed with OBS
[![Watch the demo video](https://img.youtube.com/vi/-UtbRHy-nDg/0.jpg)](https://www.youtube.com/watch?v=-UtbRHy-nDg)
