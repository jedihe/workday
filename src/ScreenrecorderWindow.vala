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
        private Gtk.Grid capture_type_grid;

        private Gtk.RadioButton all;
        private Gtk.RadioButton curr_window;
        private Gtk.RadioButton selection;
        private Gtk.MenuButton prev_sessions;

        //Actons Buttons
        public Gtk.Button right_button;
        public Gtk.Button left_button;
        private Gtk.Box actions;

        // Global Grid
        private SettingsView settings_views;
        private RecordView record_view;
        private Gtk.Stack stack;
        private Gtk.Grid grid;
  
        // Others
        public Gdk.Window win;
        private SessionRecorder session_recorder;
        public Countdown countdown;
        private string tmpfilepath;
        private bool save_dialog_present = false;
        public SendNotification send_notification;

        private const GLib.ActionEntry[] prev_sess_action_entries = {
            {"session_resume",    on_session_resume, "s"}
        };

        public ScreenrecorderWindow (Gtk.Application app){
            Object (
                application: app,
                border_width: 6,
                resizable: false
            );
        }

        construct {
            this.sessions_info = new HashMap<string, SessionInfo?> ();

            set_keep_above (true);
            // Load Settings
            GLib.Settings settings = WorkdayApp.settings;

            // Init recorder and countdown objects for boolean test 
            send_notification = new SendNotification(this);
            session_recorder = new SessionRecorder();
            countdown = new Countdown (this, this.send_notification);

            // Select Screen/Area
            all = new Gtk.RadioButton (null);
            all.image = new Gtk.Image.from_icon_name ("grab-screen-symbolic", Gtk.IconSize.DND);
            all.tooltip_text = _("Grab the whole screen");

            curr_window = new Gtk.RadioButton.from_widget (all);
            curr_window.image = new Gtk.Image.from_icon_name ("grab-window-symbolic", Gtk.IconSize.DND);
            curr_window.tooltip_text = _("Grab the current window");

            selection = new Gtk.RadioButton.from_widget (curr_window);
            selection.image = new Gtk.Image.from_icon_name ("grab-area-symbolic", Gtk.IconSize.DND);
            selection.tooltip_text = _("Select area to grab");

            this.prev_sessions = new Gtk.MenuButton();
            prev_sessions.set_image (new Gtk.Image.from_icon_name ("folder-open-symbolic", Gtk.IconSize.DND));
            prev_sessions.tooltip_text = _("Resume a previous session");

            this.populate_sessions_popover (prev_sessions);

            var session_actions = new GLib.SimpleActionGroup ();
            session_actions.add_action_entries (this.prev_sess_action_entries, this);
            this.insert_action_group ("win", session_actions);

            capture_type_grid = new Gtk.Grid ();
            capture_type_grid.halign = Gtk.Align.CENTER;
            capture_type_grid.column_spacing = 24;
            capture_type_grid.margin_top = capture_type_grid.margin_bottom = 24;
            capture_type_grid.margin_start = capture_type_grid.margin_end = 18;
            capture_type_grid.add (all);
            capture_type_grid.add (curr_window);
            capture_type_grid.add (selection);
            capture_type_grid.add (prev_sessions);

            // Views
            settings_views = new SettingsView (this);
            record_view = new RecordView ();
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
            right_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
            right_button.can_default = true;
            this.set_default (right_button);

            // Left Button
            left_button = new Gtk.Button.with_label (_("Close"));

            // Actions : [Close][Record]
            actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            actions.margin_top = 24;
            actions.set_hexpand(true);
            actions.set_homogeneous(true);
            actions.add (left_button);
            actions.add (right_button);

            // Main Grid
            grid = new Gtk.Grid ();
            grid.margin = 6;
            grid.margin_top = 0;
            grid.row_spacing = 6;
            grid.set_hexpand(true);
            grid.attach (stack   , 0, 1, 2, 7);
            grid.attach (actions    , 0, 8, 2, 1);

            // TitleBar (HeaderBar) with capture_type_grid (Screen/Area selection) attach.
            var titlebar = new Gtk.HeaderBar ();
            titlebar.has_subtitle = false;
            titlebar.set_custom_title (capture_type_grid);

            var titlebar_style_context = titlebar.get_style_context ();
            titlebar_style_context.add_class (Gtk.STYLE_CLASS_FLAT);
            titlebar_style_context.add_class ("default-decoration");

            set_titlebar (titlebar);
            add (grid);


            // Bind Settings - Start
            if (settings.get_enum ("last-capture-mode") == CaptureType.AREA){
                capture_mode = CaptureType.AREA;
                selection.active = true;
            } else if (settings.get_enum ("last-capture-mode") == CaptureType.CURRENT_WINDOW){
                capture_mode = CaptureType.CURRENT_WINDOW;
                curr_window.active = true;
            }

            all.toggled.connect (() => {
                capture_mode = CaptureType.SCREEN;
                settings.set_enum ("last-capture-mode", capture_mode);
                settings_views.update_widgets_visibility ();
            });

            curr_window.toggled.connect (() => {
                capture_mode = CaptureType.CURRENT_WINDOW;
                settings.set_enum ("last-capture-mode", capture_mode);
                settings_views.update_widgets_visibility ();
            });

            selection.toggled.connect (() => {
                capture_mode = CaptureType.AREA;
                settings.set_enum ("last-capture-mode", capture_mode);
                settings_views.update_widgets_visibility ();
            });
            // Bind Settings - End

            // Connect Buttons
            right_button.clicked.connect (() => { 

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

                } else if (session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {

                    var confirm_dlg = new Gtk.MessageDialog (this, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.QUESTION, Gtk.ButtonsType.OK_CANCEL, "Are you sure?");
                    var resp = confirm_dlg.run ();
                    confirm_dlg.destroy ();
                    if (resp == Gtk.ResponseType.OK) {
                        stop_recording ();
                        send_notification.stop();
                    }

                } else if (!session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {

                    var confirm_dlg = new Gtk.MessageDialog (this, Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.QUESTION, Gtk.ButtonsType.OK_CANCEL, "Are you sure?");
                    var resp = confirm_dlg.run ();
                    confirm_dlg.destroy ();
                    if (resp == Gtk.ResponseType.OK) {
                        stop_recording ();
                        send_notification.stop();
                    }

                } else if (!session_recorder.is_recording && countdown.is_active_cd && !session_recorder.is_session_in_progress) {

                    countdown.cancel ();
                    set_button_label(ButtonsLabelMode.SETTINGS);
                    set_button_tooltip(ButtonsTooltipMode.SETTINGS);
                    settings_views.set_sensitive (true);
                    capture_type_grid.set_sensitive (true);
                    send_notification.cancel_countdown();
                }
            });

            left_button.clicked.connect (() => {

                if (session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {

                    session_recorder.pause_session();
                    record_view.pause_count ();
                    set_button_label (ButtonsLabelMode.RECORDING_PAUSED);
                    send_notification.pause();

                } else if (!session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {

                    session_recorder.resume_session ();
                    record_view.resume_count ();
                    set_button_label (ButtonsLabelMode.RECORDING);
                    send_notification.resume();

                } else if (!session_recorder.is_recording && countdown.is_active_cd && !session_recorder.is_session_in_progress) {

                    iconify ();

                } else if (!session_recorder.is_recording && !countdown.is_active_cd && !session_recorder.is_session_in_progress) {

                    close ();
                }
            });

            // Prevent delete event if record 
            delete_event.connect (() => {
                if (can_quit()) {

                    return false;

                } else {

                    iconify ();
                    return true;
                }
            });

            KeybindingManager manager = new KeybindingManager();
            manager.bind("<Alt>P", () => {

                if (session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {

                    left_button.clicked ();

                } else if (!session_recorder.is_recording && !countdown.is_active_cd && session_recorder.is_session_in_progress) {

                    left_button.clicked ();

                }
            });

            manager.bind("<Alt>S", () => {

                if (countdown.is_active_cd || session_recorder.is_session_in_progress) {

                    right_button.clicked ();
                }
            });

            var gtk_settings = Gtk.Settings.get_default ();
            gtk_settings.notify["gtk-application-prefer-dark-theme"].connect (() => {
                update_icons (gtk_settings.gtk_application_prefer_dark_theme);
            });

            update_icons (gtk_settings.gtk_application_prefer_dark_theme);

            settings_views.update_widgets_visibility ();
        }

        private void update_icons (bool prefers_dark) {
            if (prefers_dark) {
                all.image = new Gtk.Image.from_icon_name ("grab-screen-symbolic-dark", Gtk.IconSize.DND);
            } else {
                all.image = new Gtk.Image.from_icon_name ("grab-screen-symbolic", Gtk.IconSize.DND);
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
                    right_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                    right_button.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                    left_button.set_label (_("Minimise"));
                    break;

                case ButtonsLabelMode.RECORDING:
                    right_button.set_label (_("End Session"));
                    right_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                    right_button.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                    left_button.set_label (_("Pause"));
                    break;

                case ButtonsLabelMode.RECORDING_PAUSED:
                    right_button.set_label (_("End Session"));
                    right_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                    right_button.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                    left_button.set_label (_("Resume"));
                    break;

                case ButtonsLabelMode.SETTINGS:
                    right_button.set_label (_("Start Session"));
                    right_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                    right_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                    left_button.set_label (_("Close"));
                    break;
            }
        } 

        void capture_screen (string? forced_session_name = null) {
            Gdk.Rectangle screen_rect = this.settings_views.get_screen_capture_rectangle ();
            start_recording (null, screen_rect, forced_session_name);
        }

        void capture_window (string? forced_session_name = null) {

            Gdk.Screen screen = null;
            GLib.List<Gdk.Window> list = null;
            screen = Gdk.Screen.get_default ();
            this.iconify ();

            Timeout.add (300, () => { // Wait iconify

                list = screen.get_window_stack ();

                foreach (Gdk.Window item in list) {
                    if (screen.get_active_window () == item) {
                        this.win = item;
                    }
                }

                if (this.win != null) {
                    start_recording (win, null, forced_session_name);
                }
                return false;
            });
        }

        void capture_area (string? forced_session_name = null) {

            var selection_area = new Screenshot.Widgets.SelectionArea ();
            selection_area.show_all ();

            selection_area.cancelled.connect (() => {

                selection_area.close ();
            });

            this.win = selection_area.get_window ();

            selection_area.captured.connect (() => {

                selection_area.close ();
                this.iconify ();
                start_recording (this.win, null, forced_session_name);
            });
        }

        void start_recording (Gdk.Window? win, Gdk.Rectangle? capture_rect, string? forced_session_name = null) {
            DateTime now = new DateTime.now ();
            var new_session_name = now.format ("%Y-%m-%d-%H-%M-%S");

            // Init Recorder
            session_recorder = new SessionRecorder();
            session_recorder.config(capture_mode,
                            forced_session_name != null ? forced_session_name : new_session_name,
                            settings_views.framerate,
                            settings_views.speakers_record,
                            settings_views.mic_record,
                            settings_views.pointer_switch.get_state(),
                            settings_views.format,
                            settings_views.extension,
                            WorkdayApp.settings.get_int ("fragment-length"),
                            win,
                            capture_rect);

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
            Cancellable cancellable = new Cancellable ();

            // Update Buttons
            set_button_label (ButtonsLabelMode.SETTINGS);
            set_button_tooltip(ButtonsTooltipMode.SETTINGS);

            // Stop Recording
            session_recorder.stop_session (finish);
            record_view.stop_count ();
            stack.visible_child_name = "settings";
            present ();

            // File tmp_file = File.new_for_path (tmpfilepath);
            // string file_name = Path.build_filename (session_recorder.get_session_dir (), "Full-%s%s".printf (session_recorder.session_name, settings_views.extension));
            // File save_file = File.new_for_path (file_name);

            // try {
            //     tmp_file.move (save_file, 0, cancellable, null);
            // } catch (Error e) {
            //     print ("Error: %s\n", e.message);
            // }

            settings_views.set_sensitive (false);
            Timeout.add (500, () => {
                if (!session_recorder.is_recording) {
                    if (settings_views.close_switch.get_state ()) {
                        close();
                    }
                    this.populate_sessions_popover (this.prev_sessions);
                    settings_views.set_sensitive (true);
                    capture_type_grid.set_sensitive (true);
                    return false;
                }
                return true;
            });

            // Open Sav Dialog
            //var save_dialog = new SaveDialog (this, tmpfilepath, recorder.width, recorder.height, settings_views.extension);
            //save_dialog_present = true;
            //save_dialog.set_keep_above (true);
            //debug("Sav Dialog Open");
            //save_dialog.show_all ();
            //debug("Sav Dialog Close");
            //save_dialog.set_keep_above (false);

            // save_dialog.close.connect (() => {

            //     debug("Sav Dialog Close Connect");

            //     save_dialog_present = false;
            //     settings_views.set_sensitive (true);
            //     capture_type_grid.set_sensitive (true);

            //     //if close after saving
            //     if(settings_views.close_switch.get_state()) { 

            //         close();
            //     }
            // });
        }

        public void set_capture_type(int capture_type) {

            switch (capture_type) {
                case 1:
                    all.activate();
                    break;
                case 2:
                    curr_window.activate();
                    break;
                case 3:
                    selection.activate();
                    break;
            }

        }

        public void autostart () {

            right_button.activate();
        }

        public bool can_quit () {

            if (session_recorder.is_session_in_progress || countdown.is_active_cd) {

                return false;

            } else {

                return true;
            }
        }

        private void on_session_resume (GLib.SimpleAction action, GLib.Variant? param) {
            stdout.printf ("Triggered action: %s, with param: %s\n", action.get_name (), param.get_string ());

            var session_name = param.get_string ();
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

        private void populate_sessions_popover (Gtk.MenuButton prev_sessions_button) {
            this.sessions_info.clear ();

            // Find session-dirs.
            // Find .workday-session files in each session-dir, read content as integer (seconds).
            var sessions_dir = File.new_for_path (Path.build_filename (
                Environment.get_user_special_dir (UserDirectory.VIDEOS),
                WorkdayApp.SAVE_FOLDER));
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

            var popover_grid = new Gtk.Grid ();
            popover_grid.margin_top = popover_grid.margin_bottom = 3;
            popover_grid.orientation = Gtk.Orientation.VERTICAL;

            if (sessions_info.size == 0) {
                var empty_btn = new Gtk.ModelButton () {
                    hexpand = true,
                    text = _("- No Pending Sessions -")
                };
                empty_btn.set_sensitive (false);
                popover_grid.add (empty_btn);
            }
            else {
                foreach (string sess_name in sessions_info.keys) {
                    var sess_duration = sessions_info.get (sess_name).duration;
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
                    var sess_btn = new Gtk.ModelButton () {
                        hexpand = true,
                        text = ""
                    };
                    sess_btn.get_child ().destroy ();
                    sess_btn.add (sess_lbl);
                    sess_btn.set_detailed_action_name ("win.session_resume::" + sess_name);

                    popover_grid.add (sess_btn);
                }
            }

            popover_grid.show_all ();

            var scrolled_box = new Gtk.ScrolledWindow (null, null) {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                max_content_height = 268,
                propagate_natural_height = true
            };
            scrolled_box.add (popover_grid);
            scrolled_box.show_all ();

            var prev_sessions_popover = new Gtk.Popover (null);
            prev_sessions_popover.modal = true;
            prev_sessions_popover.add (scrolled_box);

            prev_sessions_button.popover = prev_sessions_popover;
        }
    }
}
