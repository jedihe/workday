/*
 * Copyright (c) 2018 Mohammed ALMadhoun <mohelm97@gmail.com>
 *               2020 Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
 *               2021 John Herreño <jedihe@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 *
 * Authored by: Mohammed ALMadhoun <mohelm97@gmail.com>
 *              Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
 */

using Gee;

namespace Workday {

    public class ScreenrecorderWindow : Gtk.ApplicationWindow  {

        private const string CSS_CLASS_SUGGESTED_ACTION = "suggested-action";
        private const string CSS_CLASS_DESTRUCTIVE_ACTION = "destructive-action";

        // Capture Type Buttons
        public enum CaptureType {
            SCREEN,
            CURRENT_WINDOW,
            AREA
        }

        public enum ButtonsTooltipMode {
            COUNTDOWN,
            RECORDING,
            SETTINGS
        }

        public enum ButtonsLabelMode {
            COUNTDOWN,
            RECORDING,
            RECORDING_PAUSED,
            SETTINGS
        }

        struct SessionInfo {
            public string name;
            public int duration; // msec.
        }
        private HashMap<string, SessionInfo?> sessions_info;

        public CaptureType capture_mode = CaptureType.SCREEN;
        private Gtk.Box capture_type_grid;

        private Gtk.ToggleButton all;
        private Gtk.ToggleButton curr_window;
        private Gtk.ToggleButton selection;
        private Gtk.Image all_icon;
        private Gtk.MenuButton prev_sessions;

        //Actons Buttons
        public Gtk.Button right_button;
        public Gtk.Button left_button;
        private Gtk.Box actions;

        // Global Grid
        private SettingsView settings_views;
        private RecordView record_view;
        private Gtk.Stack stack;
        private Gtk.Box content;
  
        // Others
        private SessionRecorder session_recorder;
        public Countdown countdown;
        public SendNotification send_notification;
        private bool use_portal_capture;

        private const GLib.ActionEntry[] action_entries = {
            {"session_resume", on_session_resume, "s"},
            {"toggle_pause_resume", on_toggle_pause_resume},
            {"stop_or_cancel", on_stop_or_cancel}
        };

        public ScreenrecorderWindow (Gtk.Application app){
            Object (
                application: app,
                resizable: false
            );
        }

        construct {
            this.sessions_info = new HashMap<string, SessionInfo?> ();
            this.use_portal_capture = WorkdayApp.is_wayland_session ();

            // Load Settings
            GLib.Settings settings = WorkdayApp.settings;

            // Init recorder and countdown objects for boolean test 
            send_notification = new SendNotification(this);
            session_recorder = new SessionRecorder();

            // Try to properly close the current fragment on SIGINT/SIGTERM.
            GLib.Unix.signal_add (Posix.Signal.INT, () => {
                stdout.printf ("Got SIGINT!\n");
                session_recorder.emergency_stop ();
                this.destroy ();
                return Source.REMOVE;
            }, Priority.DEFAULT);
            GLib.Unix.signal_add (Posix.Signal.TERM, () => {
                stdout.printf ("Got SIGTERM!\n");
                session_recorder.emergency_stop ();
                this.destroy ();
                return Source.REMOVE;
            }, Priority.DEFAULT);

            countdown = new Countdown (this, this.send_notification);

            // Select Screen/Area
            all = new Gtk.ToggleButton ();
            all_icon = create_icon ("grab-screen-symbolic");
            all.set_child (all_icon);
            all.tooltip_text = this.use_portal_capture ?
                _("Select a monitor to share") :
                _("Grab the whole screen");

            curr_window = new Gtk.ToggleButton ();
            curr_window.set_group (all);
            curr_window.set_child (create_icon ("grab-window-symbolic"));
            curr_window.tooltip_text = this.use_portal_capture ?
                _("Select a window to share") :
                _("Window capture requires the portal backend");
            curr_window.set_sensitive (this.use_portal_capture);

            selection = new Gtk.ToggleButton ();
            selection.set_group (all);
            selection.set_child (create_icon ("grab-area-symbolic"));
            selection.tooltip_text = _("Area capture is not available in the GTK4 build yet");
            selection.set_sensitive (false);

            this.prev_sessions = new Gtk.MenuButton();
            prev_sessions.set_child (create_icon ("folder-open-symbolic"));
            prev_sessions.tooltip_text = _("Resume a previous session");

            this.populate_sessions_popover (prev_sessions);

            var session_actions = new GLib.SimpleActionGroup ();
            session_actions.add_action_entries (this.action_entries, this);
            this.insert_action_group ("win", session_actions);
            ((Gtk.Application) this.application).set_accels_for_action ("win.toggle_pause_resume", {"<Alt>p"});
            ((Gtk.Application) this.application).set_accels_for_action ("win.stop_or_cancel", {"<Alt>s"});

            capture_type_grid = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            capture_type_grid.halign = Gtk.Align.CENTER;
            capture_type_grid.margin_top = capture_type_grid.margin_bottom = 24;
            capture_type_grid.margin_start = capture_type_grid.margin_end = 18;
            capture_type_grid.append (all);
            capture_type_grid.append (curr_window);
            capture_type_grid.append (selection);
            capture_type_grid.append (prev_sessions);

            // Views
            settings_views = new SettingsView (this);
            record_view = new RecordView (send_notification);
            stack = new Gtk.Stack ();
            stack.add_named (settings_views, "settings");
            stack.add_named (record_view, "record");
            stack.visible_child_name = "settings";
            record_view.request_new_session.connect (() => {
                this.stop_recording (false);
                this.populate_sessions_popover (this.prev_sessions);
            });

            // Right Button
            right_button = new Gtk.Button.with_label (_("Start Session"));
            right_button.add_css_class (CSS_CLASS_SUGGESTED_ACTION);
            this.set_default_widget (right_button);

            // Left Button
            left_button = new Gtk.Button.with_label (_("Close"));

            // Actions : [Close][Record]
            actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            actions.margin_top = 24;
            actions.set_hexpand(true);
            actions.set_homogeneous(true);
            actions.append (left_button);
            actions.append (right_button);

            // Main content
            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            content.margin_top = 0;
            content.margin_bottom = 6;
            content.margin_start = 6;
            content.margin_end = 6;
            content.set_hexpand (true);
            content.append (stack);
            content.append (actions);

            // TitleBar (HeaderBar) with capture_type_grid (Screen/Area selection) attach.
            var titlebar = new Gtk.HeaderBar ();
            titlebar.set_title_widget (capture_type_grid);
            titlebar.add_css_class (Granite.STYLE_CLASS_FLAT);
            titlebar.add_css_class ("default-decoration");

            set_titlebar (titlebar);
            set_child (content);


            // Bind Settings - Start
            var last_capture_mode = (CaptureType) settings.get_enum ("last-capture-mode");
            if ((last_capture_mode == CaptureType.AREA && !selection.get_sensitive ()) ||
                (last_capture_mode == CaptureType.CURRENT_WINDOW && !curr_window.get_sensitive ())) {
                capture_mode = CaptureType.SCREEN;
                settings.set_enum ("last-capture-mode", capture_mode);
                all.set_active (true);
            } else if (last_capture_mode == CaptureType.AREA) {
                capture_mode = CaptureType.AREA;
                selection.set_active (true);
            } else if (last_capture_mode == CaptureType.CURRENT_WINDOW){
                capture_mode = CaptureType.CURRENT_WINDOW;
                curr_window.set_active (true);
            } else {
                all.set_active (true);
            }

            all.toggled.connect (() => {
                if (all.active) {
                    capture_mode = CaptureType.SCREEN;
                    settings.set_enum ("last-capture-mode", capture_mode);
                    settings_views.update_widgets_visibility ();
                }
            });

            curr_window.toggled.connect (() => {
                if (curr_window.active) {
                    capture_mode = CaptureType.CURRENT_WINDOW;
                    settings.set_enum ("last-capture-mode", capture_mode);
                    settings_views.update_widgets_visibility ();
                }
            });

            selection.toggled.connect (() => {
                if (selection.active) {
                    capture_mode = CaptureType.AREA;
                    settings.set_enum ("last-capture-mode", capture_mode);
                    settings_views.update_widgets_visibility ();
                }
            });
            // Bind Settings - End

            // Connect Buttons
            right_button.clicked.connect (() => {
                handle_right_button_action ();
            });

            left_button.clicked.connect (() => {
                handle_left_button_action ();
            });

            // Prevent delete event if record 
            close_request.connect (() => {
                if (can_quit()) {

                    return false;

                } else {

                    minimize ();
                    return true;
                }
            });

            var gtk_settings = Gtk.Settings.get_default ();
            gtk_settings.notify["gtk-application-prefer-dark-theme"].connect (() => {
                update_icons (gtk_settings.gtk_application_prefer_dark_theme);
            });

            update_icons (gtk_settings.gtk_application_prefer_dark_theme);

            settings_views.update_widgets_visibility ();
        }

        private Gtk.Image create_icon (string icon_name) {
            var image = new Gtk.Image.from_icon_name (icon_name);
            image.set_icon_size (Gtk.IconSize.LARGE);
            return image;
        }

        private void update_icons (bool prefers_dark) {
            if (prefers_dark) {
                all_icon.set_from_icon_name ("grab-screen-symbolic-dark");
            } else {
                all_icon.set_from_icon_name ("grab-screen-symbolic");
            }
        }

        public void set_button_tooltip (int mode) {

            switch (mode) {

                        case ButtonsTooltipMode.SETTINGS:
                            right_button.tooltip_text = "";
                            left_button.tooltip_text = "";
                            break;

                        case ButtonsTooltipMode.COUNTDOWN:
                            right_button.tooltip_markup = Granite.markup_accel_tooltip(
                                {"<Alt>s"}, _("To cancel the recording")
                            );
                            left_button.tooltip_text = "";
                            break;

                        case ButtonsTooltipMode.RECORDING:
                            right_button.tooltip_markup = Granite.markup_accel_tooltip(
                                {"<Alt>s"}, _("To stop the recording")
                            );
                            left_button.tooltip_markup = Granite.markup_accel_tooltip(
                                {"<Alt>p"}, _("To pause or resume the recording")
                            );
                            break;
            }
        }

        public void set_button_label (int mode) {

            switch (mode) {

                case ButtonsLabelMode.COUNTDOWN:
                    right_button.set_label (_("Cancel"));
                    right_button.remove_css_class (CSS_CLASS_SUGGESTED_ACTION);
                    right_button.add_css_class (CSS_CLASS_DESTRUCTIVE_ACTION);
                    left_button.set_label (_("Minimise"));
                    break;

                case ButtonsLabelMode.RECORDING:
                    right_button.set_label (_("End Session"));
                    right_button.remove_css_class (CSS_CLASS_SUGGESTED_ACTION);
                    right_button.add_css_class (CSS_CLASS_DESTRUCTIVE_ACTION);
                    left_button.set_label (_("Pause"));
                    break;

                case ButtonsLabelMode.RECORDING_PAUSED:
                    right_button.set_label (_("End Session"));
                    right_button.remove_css_class (CSS_CLASS_SUGGESTED_ACTION);
                    right_button.add_css_class (CSS_CLASS_DESTRUCTIVE_ACTION);
                    left_button.set_label (_("Resume"));
                    break;

                case ButtonsLabelMode.SETTINGS:
                    right_button.set_label (_("Start Session"));
                    right_button.remove_css_class (CSS_CLASS_DESTRUCTIVE_ACTION);
                    right_button.add_css_class (CSS_CLASS_SUGGESTED_ACTION);
                    left_button.set_label (_("Close"));
                    break;
            }
        }

        private void handle_right_button_action () {
            if (!session_recorder.is_recording && !countdown.is_active_cd && !session_recorder.is_session_in_progress) {
                string? new_sess_name = settings_views.new_session_name.length > 0 ?
                    settings_views.new_session_name :
                    null;

                switch (capture_mode) {
                    case CaptureType.SCREEN:
                        capture_screen (new_sess_name);
                        break;
                    case CaptureType.CURRENT_WINDOW:
                        capture_window (new_sess_name);
                        break;
                    case CaptureType.AREA:
                        capture_area (new_sess_name);
                        break;
                }

                settings_views.new_session_name = "";
                return;
            }

            if (!countdown.is_active_cd && session_recorder.is_session_in_progress) {
                present_stop_confirmation ();
                return;
            }

            if (!session_recorder.is_recording && countdown.is_active_cd && !session_recorder.is_session_in_progress) {
                countdown.cancel ();
                session_recorder.release_capture_source ();
                set_button_label (ButtonsLabelMode.SETTINGS);
                set_button_tooltip (ButtonsTooltipMode.SETTINGS);
                settings_views.set_sensitive (true);
                capture_type_grid.set_sensitive (true);
                send_notification.cancel_countdown ();
            }
        }

        private void handle_left_button_action () {
            if (session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {
                session_recorder.pause_session ();
                record_view.pause_count ();
                set_button_label (ButtonsLabelMode.RECORDING_PAUSED);
                send_notification.pause ();
                return;
            }

            if (!session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {
                session_recorder.resume_session ();
                record_view.resume_count ();
                set_button_label (ButtonsLabelMode.RECORDING);
                send_notification.resume ();
                return;
            }

            if (!session_recorder.is_recording && countdown.is_active_cd && !session_recorder.is_session_in_progress) {
                minimize ();
                return;
            }

            if (!session_recorder.is_recording && !countdown.is_active_cd && !session_recorder.is_session_in_progress) {
                close ();
            }
        }

        private void on_toggle_pause_resume (GLib.SimpleAction action, GLib.Variant? param) {
            if (session_recorder.is_session_in_progress && !countdown.is_active_cd) {
                handle_left_button_action ();
            }
        }

        private void on_stop_or_cancel (GLib.SimpleAction action, GLib.Variant? param) {
            if (countdown.is_active_cd || session_recorder.is_session_in_progress) {
                handle_right_button_action ();
            }
        }

        private void show_capture_error (string message) {
            var error_dlg = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.DESTROY_WITH_PARENT | Gtk.DialogFlags.MODAL,
                Gtk.MessageType.ERROR,
                Gtk.ButtonsType.NONE,
                "%s".printf (message)
            );
            error_dlg.add_button (_("Close"), Gtk.ResponseType.CLOSE);
            error_dlg.response.connect ((response_id) => {
                error_dlg.destroy ();
                present ();
            });
            error_dlg.present ();
        }

        private void present_stop_confirmation () {
            var confirm_dlg = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.DESTROY_WITH_PARENT | Gtk.DialogFlags.MODAL,
                Gtk.MessageType.QUESTION,
                Gtk.ButtonsType.NONE,
                _("Are you sure?")
            );
            confirm_dlg.add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
            confirm_dlg.add_button (_("End Session"), Gtk.ResponseType.OK);
            confirm_dlg.response.connect ((response_id) => {
                confirm_dlg.destroy ();
                if (response_id == Gtk.ResponseType.OK) {
                    stop_recording ();
                    send_notification.stop ();
                }
            });
            confirm_dlg.present ();
        }

        private CaptureSource? request_portal_capture_source (CaptureType requested_mode) {
            try {
                return PortalScreenCastSession.request_capture_source (
                    requested_mode,
                    settings_views.pointer_switch.active
                );
            } catch (Error e) {
                if (e.matches (IOError.quark (), IOError.CANCELLED)) {
                    present ();
                    return null;
                }
                show_capture_error (e.message);
                return null;
            }
        }

        void capture_screen (string? forced_session_name = null) {
            if (this.use_portal_capture) {
                CaptureSource? capture_source = request_portal_capture_source (CaptureType.SCREEN);
                if (capture_source != null) {
                    start_recording (capture_source, forced_session_name);
                }
                return;
            }

            Gdk.Rectangle screen_rect = this.settings_views.get_screen_capture_rectangle ();
            if (screen_rect.width <= 0 || screen_rect.height <= 0) {
                show_capture_error (_("Failed to determine the selected monitor geometry."));
                return;
            }

            start_recording (new CaptureSource.for_x11_rectangle (CaptureType.SCREEN, screen_rect), forced_session_name);
        }

        void capture_window (string? forced_session_name = null) {
            if (this.use_portal_capture) {
                CaptureSource? capture_source = request_portal_capture_source (CaptureType.CURRENT_WINDOW);
                if (capture_source != null) {
                    start_recording (capture_source, forced_session_name);
                }
                return;
            }

            show_capture_error (_("Window capture requires the portal backend in the GTK4 build."));
        }

        void capture_area (string? forced_session_name = null) {
            show_capture_error (_("Area capture is not available in the GTK4 build yet."));
        }

        void start_recording (CaptureSource capture_source, string? forced_session_name = null) {
            DateTime now = new DateTime.now ();
            var new_session_name = now.format ("%Y-%m-%d-%H-%M-%S");

            // Init Recorder
            session_recorder = new SessionRecorder();
            session_recorder.config(capture_mode,
                            forced_session_name != null ? forced_session_name : new_session_name,
                            settings_views.framerate,
                            settings_views.speakers_record,
                            settings_views.mic_record,
                            settings_views.pointer_switch.active,
                            settings_views.format,
                            settings_views.extension,
                            WorkdayApp.settings.get_int ("fragment-length"),
                            capture_source);

            // @TODO: remove support for countdown.
            if (settings_views.delay > 0) {

                countdown = new Countdown (this, this.send_notification);
                countdown.set_delay(settings_views.delay);
                countdown.start(session_recorder, this, stack, record_view);
                set_button_label (ButtonsLabelMode.COUNTDOWN);
                set_button_tooltip (ButtonsTooltipMode.COUNTDOWN);

            } else {

                session_recorder.start_session ();
                record_view.set_recorder(session_recorder);
                record_view.init_count ();
                stack.visible_child_name = "record";
                send_notification.start();
                set_button_label (ButtonsLabelMode.RECORDING);
                set_button_tooltip (ButtonsTooltipMode.RECORDING);
            }

            settings_views.set_sensitive (false);
            capture_type_grid.set_sensitive (false);
        }

        void stop_recording (bool finish = true) {
            // Update Buttons
            set_button_label (ButtonsLabelMode.SETTINGS);
            set_button_tooltip(ButtonsTooltipMode.SETTINGS);

            // Stop Recording
            session_recorder.stop_session (finish);
            record_view.stop_count ();
            stack.visible_child_name = "settings";
            present ();

            settings_views.set_sensitive (false);
            Timeout.add (500, () => {
                if (!session_recorder.is_recording) {
                    if (settings_views.close_switch.active) {
                        close();
                    }
                    this.populate_sessions_popover (this.prev_sessions);
                    settings_views.set_sensitive (true);
                    capture_type_grid.set_sensitive (true);
                    return false;
                }
                return true;
            });
        }

        public void set_capture_type(int capture_type) {

            switch (capture_type) {
                case 1:
                    all.set_active (true);
                    break;
                case 2:
                    if (curr_window.get_sensitive ()) {
                        curr_window.set_active (true);
                    } else {
                        all.set_active (true);
                    }
                    break;
                case 3:
                    if (selection.get_sensitive ()) {
                        selection.set_active (true);
                    } else {
                        all.set_active (true);
                    }
                    break;
            }

        }

        public void autostart () {

            right_button.activate ();
        }

        public bool can_quit () {

            if (session_recorder.is_session_in_progress || countdown.is_active_cd) {

                return false;

            } else {

                return true;
            }
        }

        private void on_session_resume (GLib.SimpleAction action, GLib.Variant? param) {
            if (param == null) {
                return;
            }

            var session_name = param.get_string ();
            stdout.printf ("Triggered action: %s, with param: %s\n", action.get_name (), session_name);
            resume_session_named (session_name);
        }

        private void populate_sessions_popover (Gtk.MenuButton prev_sessions_button) {
            this.sessions_info.clear ();

            // Find session-dirs.
            // Find .workday-session files in each session-dir, read content as integer (seconds).
            var sessions_dir = File.new_for_path (Path.build_filename (
                Environment.get_user_special_dir (UserDirectory.VIDEOS),
                WorkdayApp.SAVE_FOLDER));
            if (sessions_dir.query_exists ()) {
                try {
                    FileEnumerator enumerator = sessions_dir.enumerate_children (
                        "standard::*",
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

                    FileInfo info = null;
                    while (((info = enumerator.next_file ()) != null)) {
                        string session_name_pattern = "^[a-zA-Z0-9-_]+$";
                        if (info.get_file_type () == FileType.DIRECTORY && Regex.match_simple (session_name_pattern, info.get_name ())) {
                            File session_file = sessions_dir.resolve_relative_path (Path.build_filename (info.get_name (), ".workday-session"));
                            if (session_file.query_exists ()) {
                                try {
                                    var dis = new DataInputStream (session_file.read ());
                                    string line;
                                    // Read lines until end of file (null) is reached
                                    if ((line = dis.read_line (null)) != null) {
                                        var session_info = SessionInfo () {
                                            name = info.get_name (),
                                            duration = int.parse (line)
                                        };
                                        sessions_info.set (info.get_name(), session_info);
                                    }
                                } catch (Error e) {
                                    error ("%s", e.message);
                                }
                            }
                        }
                    }
                } catch (Error e) {
                    warning ("Failed to enumerate pending sessions: %s", e.message);
                }
            }

            var popover_grid = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            popover_grid.margin_top = popover_grid.margin_bottom = 3;

            if (sessions_info.size == 0) {
                var empty_btn = new Gtk.Button.with_label (_("- No Pending Sessions -")) {
                    hexpand = true,
                    sensitive = false,
                    has_frame = false
                };
                popover_grid.append (empty_btn);
            }
            else {
                var sorted_sessions = new Gee.ArrayList<string> ();
                sorted_sessions.add_all_array (sessions_info.keys.to_array ());
                sorted_sessions.sort ();
                foreach (string sess_name in sorted_sessions) {
                    SessionInfo? session_info = sessions_info.get (sess_name);
                    if (session_info == null) {
                        continue;
                    }

                    var sess_duration = session_info.duration;
                    int hours = sess_duration / 3600;
                    int minutes = (sess_duration % 3600) / 60;
                    string duration_label = "%s%s".printf (
                        hours > 0 ? hours.to_string () + "h " : "",
                        minutes.to_string () + "m"
                    );
                    var sess_lbl = new Gtk.Label ("<span size='12000' weight='normal'>%s</span>\n%s".printf (sess_name, duration_label)) {
                        use_markup = true,
                        halign = Gtk.Align.START
                    };
                    var sess_btn = new Gtk.Button () {
                        hexpand = true,
                        has_frame = false
                    };
                    string target_session = sess_name;
                    sess_btn.set_child (sess_lbl);
                    sess_btn.clicked.connect (() => {
                        var popover = prev_sessions_button.get_popover ();
                        if (popover != null) {
                            popover.popdown ();
                        }
                        this.resume_session_named (target_session);
                    });

                    popover_grid.append (sess_btn);
                }
            }

            var scrolled_box = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                max_content_height = 268,
                propagate_natural_height = true
            };
            scrolled_box.set_child (popover_grid);

            var prev_sessions_popover = new Gtk.Popover ();
            prev_sessions_popover.set_child (scrolled_box);

            prev_sessions_button.popover = prev_sessions_popover;
        }

        private void resume_session_named (string session_name) {
            switch (capture_mode) {
                case CaptureType.SCREEN:
                    capture_screen (session_name);
                    break;
                case CaptureType.CURRENT_WINDOW:
                    capture_window (session_name);
                    break;
                case CaptureType.AREA:
                    capture_area (session_name);
                    break;
            }
        }
    }
}
