# Technical Analysis: GTK3/X11 Implementation and GTK4/Wayland Migration

## Executive Summary

This application is not only "a GTK3 app". Its capture model is built around X11 concepts:

- X11 root window access
- X11 window IDs (`XID`)
- X11 passive key grabs
- X11 window stack / active-window discovery
- globally positioned overlay windows for selection and monitor labels

That means the Wayland port is not a straight toolkit upgrade. There are two distinct migrations:

1. Replace X11-dependent capture and control flows with compositor-mediated Wayland flows, primarily via XDG Desktop Portal + PipeWire.
2. Replace GTK3 and GTK3-era APIs/libraries with GTK4 equivalents.

The cleanest path is to treat these as separate concerns:

- First, redesign capture around portal-selected sources.
- Then do the mostly mechanical GTK3 to GTK4 widget/event/dialog migration.

If X11 compatibility can be dropped, the codebase becomes significantly simpler. In particular, `KeybindingManager`, `SelectionArea`, `MonitorLabelWindow`, and likely the monitor picker behavior can all be removed or heavily simplified.

## Part 1. How the current app is implemented

### 1. High-level architecture

The current app is organized around a small GTK UI layer plus a GStreamer recording backend:

1. `src/Application.vala`
   - Creates the `Gtk.Application`
   - Loads CSS
   - Initializes Clutter via `GtkClutter.init`
   - Creates the main window

2. `src/ScreenrecorderWindow.vala`
   - Owns the main UI
   - Tracks the selected capture mode: full screen, current window, area
   - Starts/stops sessions
   - Binds global Alt+P / Alt+S shortcuts through `KeybindingManager`

3. `src/Views/SettingsView.vala`
   - Collects capture settings
   - Detects monitors
   - Stores a monitor-selection rectangle

4. `src/Widgets/SelectionArea.vala`
   - Implements the area-selection overlay

5. `src/Widgets/MonitorLabelWindow.vala`
   - Shows numbered floating labels on top of monitors

6. `src/Tools/SessionRecorder.vala`
   - Manages long-running sessions split into fragments
   - Recreates `Recorder` instances per fragment
   - Joins fragments at the end

7. `src/Tools/Recorder.vala`
   - Builds the actual GStreamer pipeline
   - Captures video with `ximagesrc`
   - Encodes and muxes the output
   - Captures audio with `pulsesrc`

8. `src/Dialogs/SaveDialog.vala` and `src/Widgets/VideoPlayer.vala`
   - Implement a save-and-preview dialog using Clutter/GStreamer embedding
   - This path is effectively dead today: `ScreenrecorderWindow.stop_recording()` has the save dialog code commented out (`src/ScreenrecorderWindow.vala:565-587`)

### 2. Build-time dependencies that pin the app to GTK3/X11

`meson.build:36-46` hard-codes the relevant platform stack:

- `dependency ('gtk+-3.0')`
- `dependency ('x11')`
- `dependency ('gdk-x11-3.0')`
- `dependency ('clutter-gst-3.0')`
- `dependency ('clutter-gtk-1.0')`
- `dependency ('granite', version: '>=5.4.0')`

This immediately tells us:

- The app is built for GTK3, not GTK4.
- It explicitly consumes GDK's X11 backend API.
- It depends on GtkClutter/ClutterGst, which are GTK3-era libraries and not part of a normal GTK4 stack.

### 3. X11-specific implementation details

#### 3.1 Global keyboard shortcuts use raw X11 passive grabs

`src/Tools/KeybindingManager.vala:63-157` is fully X11-specific:

- Reads the X11 root window via `Gdk.get_default_root_window()`
- Casts the display to `Gdk.X11.Display`
- Casts the window to `Gdk.X11.Window`
- Calls raw Xlib `grab_key()` / `ungrab_key()`
- Interprets raw `X.Event` structs in an event filter

This code is not portable to Wayland. On Wayland, arbitrary global key grabs are intentionally not available to ordinary applications.

#### 3.2 Screen and window recording are built on `ximagesrc`

`src/Tools/Recorder.vala:123-205` builds the capture source like this:

- `videosrc = Gst.ElementFactory.make("ximagesrc", "video_src")`
- Full-screen and area capture pass root-window coordinates (`startx`, `starty`, `endx`, `endy`)
- Current-window capture passes an X11 window ID:
  - `videosrc.set ("xid", ((Gdk.X11.Window) this.window).get_xid());` at `src/Tools/Recorder.vala:163-166`

This is the core reason the app cannot work on Wayland as-is:

- `ximagesrc` is an X11 source
- `xid` only exists on X11
- screen-space coordinates are derived from the X11 desktop model

#### 3.3 "Current window" capture relies on the X11 window stack

`src/ScreenrecorderWindow.vala:442-463`:

- Minimizes the app window
- Reads `Gdk.Screen.get_default()`
- Calls `screen.get_window_stack()`
- Calls `screen.get_active_window()`
- Picks the active `Gdk.Window` and hands it to the recorder

This is an X11-style "introspect the desktop" flow. Wayland does not let clients enumerate all top-level windows or ask which other app's window is active.

#### 3.4 Multi-monitor "all monitors" geometry relies on the X11 root window

`src/Views/SettingsView.vala:348-353` and `403-409` use:

- `Gdk.get_default_root_window ().get_frame_extents (...)`

`src/Dialogs/SaveDialog.vala:61-64` does the same to size the preview.

The root window is an X11 concept. GTK4 explicitly removes backend-neutral root-window access.

#### 3.5 Area selection is implemented as a desktop overlay window

`src/Widgets/SelectionArea.vala:21-145` depends on behavior that fits X11 much better than Wayland:

- Subclasses `Granite.Widgets.CompositedWindow`
- Uses `Gtk.WindowType.POPUP`
- Calls `move()` and `resize()` on a top-level while dragging
- Uses global pointer coordinates `e.x_root` / `e.y_root`
- Uses `Gdk.Seat.grab(...)` to capture input

This is effectively a shaped desktop overlay. Under Wayland, an application cannot freely position and resize a top-level over arbitrary other clients and watch global pointer movement in the same way.

#### 3.6 Monitor number overlays rely on absolute toplevel placement

`src/Widgets/MonitorLabelWindow.vala:24-47`:

- Creates extra top-level windows
- Positions them with `move (monitor_rect.x, monitor_rect.y)`
- Makes them undecorated / input-transparent via `input_shape_combine_region (null)`
- Uses tooltip window hints and keep-above hints

This is fundamentally tied to X11 window-management semantics. On Wayland, clients do not control absolute top-level placement.

#### 3.7 Several window-manager hints are only hints, and become weaker on Wayland

Examples:

- `set_keep_above (true)` in `src/ScreenrecorderWindow.vala:99`
- `iconify()` in `src/ScreenrecorderWindow.vala:315`, `331`, `447`, `481`
- `stick()` and skip-taskbar/pager hints in `src/Widgets/SelectionArea.vala:34-39`
- `type_hint = Gdk.WindowTypeHint.TOOLTIP` in `src/Widgets/MonitorLabelWindow.vala:44`

These are not the main blockers, but they are further signs that the current UX assumes a traditional X11 window manager.

### 4. GTK3-specific and GTK3-era implementation details

#### 4.1 Startup is tied to GtkClutter / ClutterGst

`src/Application.vala:132-140`:

- Calls `Gtk.init (ref args)`
- Calls `GtkClutter.init (ref args)`

`src/Widgets/VideoPlayer.vala:23-147`:

- Uses `GtkClutter.Embed`
- Uses `ClutterGst.Playback`
- Uses `ClutterGst.Aspectratio`

This is a GTK3-era embedding stack. Even more importantly, the app initializes GtkClutter unconditionally at startup, so if the target environment no longer provides it, startup fails before recording even begins.

#### 4.2 `Gdk.Screen` is used throughout

Examples:

- `src/Application.vala:115-118`
- `src/ScreenrecorderWindow.vala:444-446`
- `src/Views/SettingsView.vala:314`
- `src/Views/SettingsView.vala:355-357`

GTK4 removes `GdkScreen` from the backend-neutral API.

#### 4.3 GTK3 container and visibility APIs are used throughout

Patterns seen across the codebase:

- `show_all()` in multiple files
- `set_no_show_all(true)` in `src/Views/SettingsView.vala:132-134`
- `add(...)` on containers and windows
- `pack_start(...)` in `src/Views/RecordView.vala:70`, `src/Dialogs/Countdown.vala:58-59`, `src/Widgets/VideoPlayer.vala:102`

In GTK4:

- `show_all()` is gone
- `GtkWidget:no-show-all` is gone
- container APIs are different (`set_child`, `append`, `prepend`, etc.)

#### 4.4 Old event signals / drawing virtuals are used directly

Examples:

- `delete_event.connect (...)` in `src/ScreenrecorderWindow.vala:324-334`, `src/Dialogs/Countdown.vala:64-67`
- `key_press_event.connect (...)` in `src/Dialogs/SaveDialog.vala:132-137`
- `button_press_event`, `button_release_event`, `motion_notify_event`, `key_press_event` overrides in `src/Widgets/SelectionArea.vala:47-99`
- `draw (Cairo.Context)` override in `src/Widgets/SelectionArea.vala:125-143`

GTK4 replaces this style of event handling with event controllers and gestures, and replaces `draw()` with `snapshot()`.

#### 4.5 Blocking dialogs are used

`src/ScreenrecorderWindow.vala:258-280` creates `Gtk.MessageDialog` and calls `run()`.

GTK4 removes the blocking `gtk_dialog_run()` API. Dialogs must become signal-driven or move to newer async dialog APIs.

#### 4.6 `Gtk.FileChooserButton` is used

`src/Dialogs/SaveDialog.vala:99`

GTK4 removes `GtkFileChooserButton`.

#### 4.7 The settings format selector uses GTK3 model/cell-renderer patterns

`src/Views/SettingsView.vala:209-235` uses:

- `Gtk.ListStore`
- `Gtk.ComboBox`
- `Gtk.CellRendererText`

This can still be made to work on GTK4, but it is legacy API and is deprecated in modern GTK4. A `Gtk.DropDown`-based replacement is cleaner.

### 5. What is not actually central to the port

Some code is not the real problem:

- `SessionRecorder` fragment splitting and file joining are mostly backend-agnostic (`src/Tools/SessionRecorder.vala`)
- The audio path uses `pulsesrc`, which is not X11-specific
- Notifications are independent of X11/GTK3 concerns (`src/Tools/SendNotification.vala`)

These parts can likely survive with only light changes.

## Part 2. How to convert the X11 parts to Wayland, and GTK3 parts to GTK4

## A. Recommended migration order

The lowest-risk sequence is:

1. Remove dead preview/save-path code if it is not needed.
2. Introduce a backend-neutral capture-source abstraction.
3. Replace X11 capture with portal-selected Wayland capture.
4. Drop or redesign features that have no good Wayland equivalent.
5. Port the remaining UI from GTK3 to GTK4.

This order matters because the X11 to Wayland redesign is the hard part. The GTK3 to GTK4 work is large, but much more mechanical once capture semantics are fixed.

## B. X11 to Wayland conversion breakdown

### B.1 Replace `ximagesrc` and XIDs with ScreenCast portal + PipeWire

The current recorder assumes the capture source is either:

- a rectangle on the root window, or
- an X11 window ID

On Wayland, the correct model is:

1. Create an XDG Desktop Portal ScreenCast session.
2. Call `SelectSources` with the source types you allow.
3. Call `Start`, which lets the compositor present a trusted picker UI.
4. Call `OpenPipeWireRemote`.
5. Feed the returned PipeWire stream into the GStreamer pipeline.

Implementation notes that matter in practice:

- Portal requests can take a `parent_window` identifier. On Wayland this is a surface handle, not an XID.
- If you cannot provide a proper handle immediately, you can still pass an empty string, but transient/modal behavior will be worse.
- The ScreenCast portal can also return a `restore_token`. That is the closest Wayland-side equivalent to the app's current "resume against the same target again" behavior.

What changes in the code:

- `Recorder.config(...)` should stop accepting `Gdk.Window? window` as the primary source handle.
- Introduce a `CaptureSource` object instead, e.g. monitor/window/portal-stream metadata.
- `Recorder.setup_video_source()` should no longer choose between coordinates and XID. It should instead choose a source backend:
  - temporary transition: `setup_x11_source()` and `setup_portal_source()`
  - final state: only `setup_portal_source()`

What can stay almost unchanged:

- most of the encoding path after the source element
- muxing
- fragment splitting
- file output logic

### B.2 Screen mode should become portal monitor selection

Current behavior:

- `SettingsView` computes a monitor rectangle itself
- full-screen mode can mean either "all monitors" or one selected monitor

Wayland-compatible replacement:

- Let the ScreenCast portal choose the monitor
- Treat "screen" as "select a monitor to share"
- Use the portal's returned stream metadata for dimensions/position if you need it later

Recommendation:

- For the first Wayland version, drop "All Monitors" as a precomputed union rectangle.
- Keep only single-source recording with `multiple=false`.
- If "all monitors" is important later, re-add it by requesting multiple monitor streams and compositing them with GStreamer. That is possible in principle, but it is a separate feature, not a porting detail.

### B.3 Current-window capture cannot remain automatic

Current behavior:

- Minimize own window
- Inspect the X11 window stack
- Pick whichever window is active

Wayland-compatible replacement:

- Ask the ScreenCast portal for a `WINDOW` source
- Let the compositor ask the user which window to share

Practical consequence:

- "Grab current window" should become "Select window" in the UI, or at least its behavior will change to user-mediated selection
- there is no generic Wayland equivalent of "give me the active foreign top-level window right now"
- if session resume should try to target the same window again, store and reuse a portal restore token when the backend supports it; otherwise prompt again

### B.4 Area capture should be dropped initially

Current behavior:

- Draw an always-on-top overlay
- Track global pointer coordinates
- Resize a desktop overlay window to the selected rectangle

There is no good compositor-agnostic Wayland equivalent for this workflow.

Realistic options:

1. Drop the feature entirely.
2. Reinterpret it as "share a monitor, then crop inside the app" after capture begins.
3. Write compositor-specific code for wlroots/GNOME/KDE families, which defeats the point of a generic port.

Recommendation:

- Drop `AREA` mode for the first Wayland port.
- If it must return later, implement it as an explicit crop step on top of a portal-selected monitor stream.

### B.5 Global shortcuts need a new model

Current behavior:

- `KeybindingManager` uses X11 passive grabs for Alt+P / Alt+S

Wayland-compatible options:

1. Focused-window shortcuts only
   - Replace them with `GAction` + GTK shortcuts inside the app
   - Lowest complexity

2. Global shortcuts portal
   - Use XDG Desktop Portal GlobalShortcuts
   - Lets the user approve and configure global bindings
   - Higher complexity, but conceptually correct on Wayland

Recommendation:

- If global bindings are optional, remove `KeybindingManager` and keep only in-app shortcuts.
- If they are required, reimplement them using the GlobalShortcuts portal rather than compositor-specific private APIs.

### B.6 Monitor label overlays should be removed

Current behavior:

- The app creates transparent top-level windows and moves them to exact monitor coordinates

Wayland-compatible replacement:

- No direct equivalent
- Use the portal picker to identify the chosen monitor/window
- If you still want monitor numbering, show it inside your own app UI only

Recommendation:

- Remove `MonitorLabelWindow` and the focus-triggered overlay behavior in `SettingsView`

### B.7 Root-window geometry assumptions should be deleted

Current uses:

- selecting the full desktop geometry
- sizing the unused save preview dialog

Wayland-compatible replacement:

- use portal stream metadata for capture dimensions
- use `Gdk.Display` / `Gdk.Monitor` only for informational UI inside the app, not for authoritative capture geometry

## C. GTK3 to GTK4 conversion breakdown

### C.1 Replace the build stack

`meson.build` should move roughly in this direction:

- `gtk+-3.0` -> `gtk4`
- remove `x11`
- remove `gdk-x11-3.0`
- remove `clutter-gst-3.0`
- remove `clutter-gtk-1.0`
- move from GTK3-era Granite to a GTK4-compatible Granite release, or remove the Granite pieces that are no longer needed

If X11 support is intentionally dropped, there is no reason to keep the X11 dependencies at all.

### C.2 Remove GtkClutter/ClutterGst entirely

Because the save preview path is currently dead, the cheapest port is:

- delete `VideoPlayer.vala`
- delete `SaveDialog.vala` if you do not plan to revive it immediately
- remove `GtkClutter.init` from `Application.main`
- remove `clutter-*` dependencies from Meson

If a preview is still wanted later, replace it with GTK4 media APIs such as `GtkMediaFile` / `GtkVideo`, or a dedicated GTK4-friendly GStreamer widget strategy.

### C.3 Replace `Gdk.Screen` / root-window APIs

Examples to change:

- `Gtk.StyleContext.add_provider_for_screen(...)` -> display-based CSS provider registration
- `Gdk.Screen.get_default()` monitor and window-stack logic -> `Gdk.Display` / `Gdk.Monitor` logic where applicable
- `Gdk.get_default_root_window()` usage -> remove entirely from backend-neutral code

This is partly a GTK4 migration and partly a conceptual cleanup away from X11 desktop assumptions.

### C.4 Replace old container APIs

Typical changes:

- `add(...)` -> `set_child(...)` for single-child containers/windows, or `append(...)` / `prepend(...)` for boxes
- `pack_start(...)` / `pack_end(...)` -> `append(...)` / `prepend(...)`
- remove most `show_all()` calls
- replace `set_no_show_all(true)` with explicit `set_visible(false)` / `set_visible(true)` logic

This will touch nearly every widget-building file:

- `Application.vala`
- `ScreenrecorderWindow.vala`
- `SettingsView.vala`
- `RecordView.vala`
- `Countdown.vala`
- `SaveDialog.vala` if kept

### C.5 Replace event signals with GTK4 event controllers and gestures

Key cases:

- `delete_event` -> `close-request`
- `key_press_event` -> `GtkEventControllerKey`
- `button_press_event` / `button_release_event` -> `GtkGestureClick`
- `motion_notify_event` -> `GtkEventControllerMotion`
- `draw()` -> `snapshot()`

This mostly affects:

- `SelectionArea.vala`
- `SaveDialog.vala`
- `Countdown.vala`
- `ScreenrecorderWindow.vala`

If `SelectionArea` is removed for Wayland, that eliminates the largest custom-event rewrite.

### C.6 Replace blocking dialogs

Current code uses `Gtk.MessageDialog.run()`.

GTK4-compatible choices:

- keep `GtkDialog`-style response handling without `run()`
- use `GtkAlertDialog` if your GTK4 baseline is new enough
- replace some dialogs with simple transient windows or inline confirmation UIs

Recommendation:

- For simple confirmation prompts, move to async response handling immediately.
- Avoid carrying `run()`-style control flow forward into the port.

### C.7 Replace `Gtk.FileChooserButton`

Current usage:

- `src/Dialogs/SaveDialog.vala:99`

GTK4 replacement:

- a normal button plus a file/folder dialog
- `GtkFileChooserNative` is a straightforward bridge if you want broad GTK4 compatibility
- `GtkFileDialog` is the cleaner long-term choice on newer GTK4

Given that the whole save preview flow is unused today, the better question is whether this dialog should exist at all.

### C.8 Replace legacy combo-box/model widgets where practical

Current code:

- `Gtk.ListStore`
- `Gtk.ComboBox`
- `Gtk.CellRendererText`

GTK4 can still compile some of this, but it is legacy API.

Recommendation:

- Use `GtkDropDown` with a string/list model for:
  - codec format selection
  - monitor selection, if any monitor selection remains in-app

### C.9 Revisit Granite usage, not just GTK usage

Granite usages in this tree include:

- `Granite.Widgets.CompositedWindow`
- `Granite.SeekBar`
- `Granite.Services.Application`
- Granite style classes and tooltip helpers

Porting implications:

- `CompositedWindow` is tied to the overlay-selection feature that should probably be removed anyway
- `SeekBar` becomes irrelevant if `VideoPlayer` is removed
- `Granite.Services.Application` may remain usable depending on the GTK4 Granite version you target, but it should be verified explicitly during the port

The practical takeaway is that dropping unused preview/overlay features also removes most of the risky Granite surface area.

## D. What should be kept, changed, or dropped

### Keep with minor changes

- `SessionRecorder` fragment/session management
- GStreamer encoding/muxing chain after the video source
- notifications
- settings persistence
- session list popover concept

### Keep, but redesign

- full-screen capture -> portal monitor selection
- current-window capture -> portal window selection
- keyboard shortcuts -> focused shortcuts or GlobalShortcuts portal

### Drop for the first Wayland/GTK4 port

- `AREA` capture mode
- monitor-label overlay windows
- X11 passive key grab implementation
- "all monitors as one giant root-window rectangle"
- Clutter-based preview/save dialog path, unless you explicitly want to revive it

## E. Suggested concrete target state

If X11 compatibility is allowed to go away, the simplest credible target is:

- GTK4 UI
- ScreenCast portal for screen/window capture
- PipeWire-fed GStreamer source
- Screen mode and window mode only
- no area mode
- no floating monitor overlays
- no raw X11 key grabs
- no Clutter

That target keeps the core value of the application:

- record ongoing work sessions
- fragment and join recordings
- record optional audio
- send notifications

while removing the parts that are most incompatible with Wayland.

## F. References

Official documentation used to validate the migration guidance:

- GTK 3 to GTK 4 migration guide: https://docs.gtk.org/gtk4/migrating-3to4.html
- GTK dialogs overview: https://docs.gtk.org/gtk4/section-dialogs.html
- GTK `GtkMediaFile`: https://docs.gtk.org/gtk4/class.MediaFile.html
- XDG Desktop Portal ScreenCast: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html
- XDG Desktop Portal GlobalShortcuts: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
- XDG Desktop Portal Window Identifiers: https://flatpak.github.io/xdg-desktop-portal/docs/window-identifiers.html
- XDG Desktop Portal rationale for Wayland capture: https://flatpak.github.io/xdg-desktop-portal/docs/reasons-to-use-portals.html
- GStreamer `ximagesrc`: https://gstreamer.freedesktop.org/documentation/ximagesrc/index.html
