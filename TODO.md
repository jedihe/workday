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
    1. ~~Hardcode 0.5 fps~~
    2. ~~Store recordings in \~/Videos/Workday~~
    2. ~~Store tmp file in the session dir~~
    3. ~~Store recordings in the session dir~~
    4. ~~Store recordings as fragments~~
    5. ~~Auto-split fragments every 5 min~~
    6. ~~Consolidate total recording time from old + current fragment~~
    7. ~~Auto-join fragments when the session is finalized.~~
        * Ref: http://gstreamer-devel.966125.n4.nabble.com/Using-concat-to-join-multiple-mp4-files-into-a-single-mp4-file-td4693799.html
        * Ref: http://gstreamer-devel.966125.n4.nabble.com/How-to-use-Concat-element-td4688916.html
    8. ~~Correct differences between real elapsed time vs. total recorded time~~
    9. ~~Allow selecting the screen area to record: all, monitor 1, monitor 2, etc.~~.
    10. ~~Store current duration in sess-dir/.workday-session, update every X seconds. Delete this file when closing a session.~~
    11. ~~Detect in-progress sessions by scanning all session dirs for .workday-session files.~~
    12. ~~Switch sessions on the fly.~~
    13. ~~Ignore symlinks when discovering fragments~~
    14. ~~Allow setting the session name for new sessions~~.
    15. Sort the list of in-progress sessions, shown in the popover
