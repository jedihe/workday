## Goal:

Get a minimally working version of Workday, working in elementary; ensure good stability.

## Steps:

1. Research existing projects:
    1. ~~Identify the pieces from them that may be useful~~
    2. ~~Get them building locally, to ensure the code can be used by me~~.
2. Write down features for MVP
    1. Fixed 0.5 fps
    2. Fragmented recording
    3. Session management:
        1. Multiple sessions
        2. Quick switching between sessions
        3. Timer, accumulating old + current fragment
        4. Joining of final file (ffmpeg)
3. MVP implementation plan:
    1. ~~Hardcode 0.5 fpx~~
    2. ~~Store recordings in \~/Videos/Workday~~
    2. ~~Store tmp file in the session dir~~
    3. ~~Store recordings in the session dir~~
    4. Store recordings as fragments
    5. Consolidate total recording time from old + current fragment
