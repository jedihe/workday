/*
 * Copyright (c) 2020 Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
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
 * Authored by: Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
 */

using Gdk;
using Gee;

namespace Workday {

    public class SettingsView : Gtk.Box {

        public ScreenrecorderWindow window { get; construct; }
            private Gtk.Label screen_label;
            private Gtk.ComboBoxText screen_cmb;
            private HashMap<string, Gdk.Rectangle?> monitor_rects;
            private Gtk.Window[] lbl_windows;

            private bool is_multi_monitor = false;

            // Settings Buttons/Switch/ComboBox
                // Mouse pointer and close switch
            public Gtk.Switch pointer_switch;
            public Gtk.Switch close_switch;

                // Audio
            private Gtk.CheckButton record_speakers_btn;
            private Gtk.CheckButton record_mic_btn;
            private Gtk.Image speaker_icon;
            private Gtk.Image speaker_icon_mute;
            private Gtk.Image mic_icon;
            private Gtk.Image mic_icon_mute;
            public bool speakers_record = false;
            public bool mic_record = false;

            public int delay;
            public int framerate;

                // Format
            private enum Column {
                CODEC_GSK,
                CODEC_USER,
                CODEC_EXT
            }
            public const string[] codec_user = {"mp4", "mkv", "webm"};
            public const string[] codec_gsk = {"x264enc-mp4", "x264enc-mkv", "vp8enc"};
            public const string[] codec_ext = {".mp4", ".mkv", ".webm"};

            private Gtk.ComboBox format_cmb;
            public string format;
            public string extension;

            private Gtk.Entry session_name_ent;
            public string new_session_name {
                get { return this.session_name_ent.text; }
                set { this.session_name_ent.text = value; }
            }

            // Settings Grid
            private Gtk.Grid sub_grid;


        public SettingsView (ScreenrecorderWindow window) {

            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 6,
                window: window,
                margin: 0,
                valign: Gtk.Align.CENTER,
                margin_top: 10,
                margin_bottom: 10
            );
        }

        construct {
            monitor_rects = new HashMap<string, Gdk.Rectangle?> ();

            // Load Settings
            GLib.Settings settings = WorkdayApp.settings;

            // Screen capture area
            screen_label = new Gtk.Label (_("Capture Area:"));
            screen_label.halign = Gtk.Align.END;

            screen_cmb = new Gtk.ComboBoxText ();
            screen_cmb.changed.connect (() => {
                stdout.printf ("Screen selected! active_id: %s, active: %i\n", screen_cmb.active_id, screen_cmb.active);
            });

            bool screen_cmb_was_focused = false;
            screen_cmb.set_focus_child.connect(() => {
                bool is_focused = screen_cmb.get_focus_child () != null;
                if (is_focused && !screen_cmb_was_focused) {
                    screen_cmb_was_focused = true;
                    if (!this.monitor_rects.is_empty)  {
                        foreach (var monitor_name in this.monitor_rects.keys) {
                            var monitor_rect = this.monitor_rects.get (monitor_name);
                            stdout.printf ("Building lbl_win for monitor %s\n", monitor_name);
                            var lbl_win = new Workday.MonitorLabelWindow (monitor_rect, monitor_name);
                            this.lbl_windows += lbl_win;
                            lbl_win.attached_to = this;
                            lbl_win.show_all ();
                        }
                    }
                }
                else if (screen_cmb_was_focused) {
                    for (var i = 0; i < this.lbl_windows.length; i++) {
                        this.lbl_windows[i].destroy ();
                    }
                    this.lbl_windows = {};
                    screen_cmb_was_focused = false;
                }
            });

            // Assume we won't show the all-screen capture options.
            this.screen_label.set_no_show_all (true);
            this.screen_cmb.set_no_show_all (true);

            // Grab mouse pointer ? 
            var pointer_label = new Gtk.Label (_("Grab mouse pointer:"));
            pointer_label.halign = Gtk.Align.END;

            pointer_switch = new Gtk.Switch ();
            pointer_switch.halign = Gtk.Align.START;

            // Close after saving ?
            var close_label = new Gtk.Label (_("Close after saving:"));
            close_label.halign = Gtk.Align.END;

            close_switch = new Gtk.Switch ();
            close_switch.halign = Gtk.Align.START;

            // Record Sounds ?
            var audio_label = new Gtk.Label (_("Record sounds:"));
            audio_label.halign = Gtk.Align.END;

                // From Speakers
            record_speakers_btn = new Gtk.CheckButton ();
            record_speakers_btn.tooltip_text = _("Record sound from computer");
            record_speakers_btn.toggled.connect(() => {
                speakers_record = !speakers_record;
                if (speakers_record) {
                    record_speakers_btn.image = speaker_icon;
                    record_speakers_btn.get_style_context ().add_class (Granite.STYLE_CLASS_ACCENT);
                } else {
                    record_speakers_btn.image = speaker_icon_mute;
                    record_speakers_btn.get_style_context ().remove_class (Granite.STYLE_CLASS_ACCENT);
                }
            });
            speaker_icon = new Gtk.Image.from_icon_name ("audio-volume-high-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            speaker_icon_mute = new Gtk.Image.from_icon_name ("audio-volume-muted-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            record_speakers_btn.image = speaker_icon_mute;

                // From Mic
            record_mic_btn = new Gtk.CheckButton ();
            record_mic_btn.tooltip_text = _("Record sound from microphone");
            record_mic_btn.toggled.connect(() => {
                mic_record = !mic_record;
                if (mic_record) {
                    record_mic_btn.image = mic_icon;
                    record_mic_btn.get_style_context ().add_class (Granite.STYLE_CLASS_ACCENT);
                } else {
                    record_mic_btn.image = mic_icon_mute;
                    record_mic_btn.get_style_context ().remove_class (Granite.STYLE_CLASS_ACCENT);
                }
            });
            mic_icon = new Gtk.Image.from_icon_name ("microphone-sensitivity-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            mic_icon_mute = new Gtk.Image.from_icon_name ("microphone-sensitivity-muted-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            record_mic_btn.image = mic_icon_mute;

                // Audio Buttons Grid
            var audio_grid = new Gtk.Grid ();
            audio_grid.halign = Gtk.Align.START;
            audio_grid.column_spacing = 12;
            audio_grid.add (record_speakers_btn);
            audio_grid.add (record_mic_btn);

            // Delay before capture
            var delay_label = new Gtk.Label (_("Delay in seconds:"));
            delay_label.halign = Gtk.Align.END;
            var delay_spin = new Gtk.SpinButton.with_range (0, 15, 1);

            // Frame rate
            var framerate_label = new Gtk.Label (_("Frame rate:"));
            framerate_label.halign = Gtk.Align.END;
            var framerate_spin = new Gtk.SpinButton.with_range (1, 120, 1);

            // Format Combo Box - Start
            var format_label = new Gtk.Label (_("Format:"));
            format_label.halign = Gtk.Align.END;

            Gtk.ListStore list_store = new Gtk.ListStore (3, typeof (string),typeof (string),typeof (string));

            for (int i = 0; i < codec_gsk.length; i++) {

                Gtk.TreeIter iter;
                list_store.append (out iter);
                list_store.set(iter, Column.CODEC_GSK, codec_gsk[i],
                                     Column.CODEC_USER, codec_user[i],
                                     Column.CODEC_EXT, codec_ext[i]);

            }

            format_cmb = new Gtk.ComboBox.with_model (list_store);
            Gtk.CellRendererText cell = new Gtk.CellRendererText ();
            format_cmb.pack_start (cell, false);
            format_cmb.set_attributes (cell, "text", Column.CODEC_USER);
            string saved_format = settings.get_string ("format");
            for (int i = 0; i < codec_gsk.length; i++) {

                if (saved_format == codec_gsk[i]) {

                    this.format_cmb.set_active (i);
                    this.format = codec_gsk[i];
                    this.extension = codec_ext[i];
                    break;
                }
            }
            // Format Combo Box - End

            var new_session_name_lbl = new Gtk.Label(_("Session Name:"));
            new_session_name_lbl.halign = Gtk.Align.END;
            session_name_ent = new Gtk.Entry () {
                placeholder_text = _("(Automatic)"),
                width_chars = 18
            };
            // Filter out unwanted characters from the session name.
            // TODO: try to prevent cursor flashing, probably by doing this: https://stackoverflow.com/a/16567697
            session_name_ent.changed.connect (() => {
                var new_text = session_name_ent.text;
                var regex = new GLib.Regex ("[^a-zA-Z0-9-_]");
                var filtered_text = regex.replace_literal (new_text, -1, 0, "");
                if (filtered_text.length < new_text.length && session_name_ent.cursor_position < filtered_text.length) {
                    Idle.add (() => {
                        session_name_ent.move_cursor (Gtk.MovementStep.LOGICAL_POSITIONS, -1, false);
                        return false;
                    });
                }
                // Set the filtered_text *after* checking if we should move the cursor.
                session_name_ent.text = filtered_text;
            });

            // Sub Grid, all switch/checkbox/combobox/spin
            // except Actions.
            sub_grid = new Gtk.Grid ();
            sub_grid.column_homogeneous = true;
            sub_grid.halign = Gtk.Align.CENTER;
            sub_grid.margin = 0;
            sub_grid.row_spacing = this.is_multi_monitor ? 6 : 12;
            sub_grid.column_spacing = 12;
            sub_grid.attach (screen_label, 0, 1, 1, 1);
            sub_grid.attach (screen_cmb, 1, 1, 1, 1);
            sub_grid.attach (pointer_label     , 0, 2, 1, 1);
            sub_grid.attach (pointer_switch    , 1, 2, 1, 1);
            sub_grid.attach (close_label       , 0, 3, 1, 1);
            sub_grid.attach (close_switch      , 1, 3, 1, 1);
            //sub_grid.attach (audio_label       , 0, 3, 1, 1);
            //sub_grid.attach (audio_grid        , 1, 3, 1, 1);
            sub_grid.attach (delay_label       , 0, 4, 1, 1);
            sub_grid.attach (delay_spin        , 1, 4, 1, 1);
            //sub_grid.attach (framerate_label   , 0, 5, 1, 1);
            //sub_grid.attach (framerate_spin    , 1, 5, 1, 1);
            sub_grid.attach (format_label       , 0, 5, 1, 1);
            sub_grid.attach (format_cmb    , 1, 5, 1, 1);
            sub_grid.attach (new_session_name_lbl, 0, 6, 1, 1);
            sub_grid.attach (session_name_ent, 1, 6, 1, 1);

            add(sub_grid);

            // Bind Settings - Start
            settings.bind ("mouse-pointer", pointer_switch, "active", GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("close-on-save", close_switch, "active", GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("record-computer", record_speakers_btn, "active", GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("record-microphone", record_mic_btn, "active", GLib.SettingsBindFlags.DEFAULT);

            settings.bind ("delay", delay_spin, "value", GLib.SettingsBindFlags.DEFAULT);
            delay_spin.value_changed.connect (() => {
                delay = delay_spin.get_value_as_int ();
            });
            delay = delay_spin.get_value_as_int ();

            settings.bind ("framerate", framerate_spin, "value", GLib.SettingsBindFlags.DEFAULT);
            framerate_spin.value_changed.connect (() => {
                framerate = framerate_spin.get_value_as_int ();
            });
            framerate = framerate_spin.get_value_as_int ();

            format_cmb.changed.connect (() => {
                settings.set_string ("format", codec_gsk[format_cmb.get_active ()]);
                this.format = codec_gsk[format_cmb.get_active ()];
                this.extension = codec_ext[format_cmb.get_active ()];
            });
            // Bind Settings - End

            uint monitors_changed_debounced_timer;
            Gdk.Screen.get_default ().monitors_changed.connect(() => {
                if (monitors_changed_debounced_timer != 0) {
                    GLib.Source.remove (monitors_changed_debounced_timer);
                }
                monitors_changed_debounced_timer = Timeout.add (500, () => {
                    this.detect_monitors ();
                    this.update_widgets_visibility ();
                    monitors_changed_debounced_timer = 0;
                    return false;
                });
            });

            this.detect_monitors ();
            this.update_widgets_visibility ();

        }

        public void update_widgets_visibility () {
            GLib.Settings settings = WorkdayApp.settings;
            bool is_all_capture = settings.get_enum ("last-capture-mode") == ScreenrecorderWindow.CaptureType.SCREEN;
            stdout.printf ("In update_widgets_visibility (), multi_monitor: %s\n", this.is_multi_monitor.to_string ());
            this.screen_label.set_visible (this.is_multi_monitor && is_all_capture);
            this.screen_cmb.set_visible (this.is_multi_monitor && is_all_capture);
            this.sub_grid.row_spacing = this.is_multi_monitor && is_all_capture ? 6 : 12;
            this.set_margin_top (this.is_multi_monitor && is_all_capture ? 6 : 10);
            this.set_margin_bottom (this.is_multi_monitor && is_all_capture ? 5 : 10);
        }

        private void detect_monitors () {
            GLib.Settings settings = WorkdayApp.settings;

            this.screen_cmb.remove_all ();
            this.monitor_rects.clear ();

            // Always populate the 'all' option.
            Gdk.Rectangle capture_rect;
            Gdk.get_default_root_window ().get_frame_extents (out capture_rect);
            // string all_item_id = this.serialize_rectangle (capture_rect);
            this.screen_cmb.append ("all", _("All Monitors"));
            screen_cmb.set_active_id ("all");

            var scr = Gdk.Screen.get_default ();
            var disp = scr.get_display ();
            this.is_multi_monitor = disp.get_n_monitors () > 1;
            Gdk.Monitor monitor;
            var monitor_rect = Gdk.Rectangle ();
            for (var i = 0; this.is_multi_monitor && i < disp.get_n_monitors (); i++) {
                monitor = disp.get_monitor (i);
                if (monitor != null) {
                    monitor_rect = monitor.get_geometry ();
                    string serialized_rect = this.serialize_rectangle (monitor_rect);
                    string monitor_name = _("Monitor") + " %i".printf (i+1);
                    this.monitor_rects.set (monitor_name, monitor_rect);
                    this.screen_cmb.append (serialized_rect, monitor_name);
                }
            }
            stdout.printf ("monitor_rects.size == %i\n", this.monitor_rects.size);

            // Update sub_grid layout.
            this.sub_grid.row_spacing = this.is_multi_monitor ? 6 : 12;
        }

        public string serialize_rectangle (Gdk.Rectangle rect) {
            return "%ix%i@%i,%i".printf (
                rect.width,
                rect.height,
                rect.x,
                rect.y
            );
        }
    }
}
