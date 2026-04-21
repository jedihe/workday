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
        private Gdk.Rectangle all_monitors_rect;
        private uint monitors_changed_debounced_timer;

        private bool is_multi_monitor = false;
        private bool use_portal_capture = false;

        // Settings Buttons/Switch/ComboBox
        public Gtk.Switch pointer_switch;
        public Gtk.Switch close_switch;

        // Audio
        private Gtk.ToggleButton record_speakers_btn;
        private Gtk.ToggleButton record_mic_btn;
        private Gtk.Image speaker_icon;
        private Gtk.Image mic_icon;
        public bool speakers_record = false;
        public bool mic_record = false;

        public int delay;
        public int framerate;

        // Format
        public const string[] codec_user = {"mp4", "mkv", "webm"};
        public const string[] codec_gsk = {"x264enc-mp4", "x264enc-mkv", "vp8enc"};
        public const string[] codec_ext = {".mp4", ".mkv", ".webm"};

        private Gtk.ComboBoxText format_cmb;
        public string format;
        public string extension;
        private GLib.Regex? session_name_filter;

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
                valign: Gtk.Align.CENTER,
                margin_top: 10,
                margin_bottom: 10
            );
        }

        construct {
            monitor_rects = new HashMap<string, Gdk.Rectangle?> ();
            this.use_portal_capture = WorkdayApp.is_wayland_session ();
            try {
                this.session_name_filter = new GLib.Regex ("[^a-zA-Z0-9-_]");
            } catch (GLib.RegexError e) {
                warning ("Failed to create session name filter: %s", e.message);
            }

            // Load Settings
            GLib.Settings settings = WorkdayApp.settings;

            // Screen capture area
            screen_label = new Gtk.Label (_("Capture Area:"));
            screen_label.halign = Gtk.Align.END;

            screen_cmb = new Gtk.ComboBoxText ();

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
            record_speakers_btn = new Gtk.ToggleButton ();
            record_speakers_btn.tooltip_text = _("Record sound from computer");
            speaker_icon = create_icon ("audio-volume-muted-symbolic");
            record_speakers_btn.set_child (speaker_icon);
            record_speakers_btn.toggled.connect(() => {
                speakers_record = record_speakers_btn.active;
                update_audio_button (
                    record_speakers_btn,
                    speaker_icon,
                    speakers_record,
                    "audio-volume-high-symbolic",
                    "audio-volume-muted-symbolic"
                );
            });

                // From Mic
            record_mic_btn = new Gtk.ToggleButton ();
            record_mic_btn.tooltip_text = _("Record sound from microphone");
            mic_icon = create_icon ("microphone-sensitivity-muted-symbolic");
            record_mic_btn.set_child (mic_icon);
            record_mic_btn.toggled.connect(() => {
                mic_record = record_mic_btn.active;
                update_audio_button (
                    record_mic_btn,
                    mic_icon,
                    mic_record,
                    "microphone-sensitivity-symbolic",
                    "microphone-sensitivity-muted-symbolic"
                );
            });

                // Audio Buttons Grid
            var audio_grid = new Gtk.Grid ();
            audio_grid.halign = Gtk.Align.START;
            audio_grid.column_spacing = 12;
            audio_grid.attach (record_speakers_btn, 0, 0, 1, 1);
            audio_grid.attach (record_mic_btn, 1, 0, 1, 1);

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

            format_cmb = new Gtk.ComboBoxText ();
            for (int i = 0; i < codec_gsk.length; i++) {
                format_cmb.append (codec_gsk[i], codec_user[i]);
            }
            string saved_format = settings.get_string ("format");
            if (!this.format_cmb.set_active_id (saved_format)) {
                this.format_cmb.set_active_id (codec_gsk[0]);
            }
            update_format_selection (this.format_cmb.get_active_id ());
            // Format Combo Box - End

            var new_session_name_lbl = new Gtk.Label(_("Session Name:"));
            new_session_name_lbl.halign = Gtk.Align.END;
            session_name_ent = new Gtk.Entry () {
                placeholder_text = _("(Automatic)"),
                width_chars = 18
            };
            session_name_ent.changed.connect (() => {
                GLib.Regex? session_name_filter = this.session_name_filter;
                if (session_name_filter == null) {
                    return;
                }

                var new_text = session_name_ent.text;
                string filtered_text;
                try {
                    filtered_text = session_name_filter.replace_literal (new_text, -1, 0, "");
                } catch (GLib.RegexError e) {
                    warning ("Failed to sanitize session name: %s", e.message);
                    return;
                }

                if (filtered_text == new_text) {
                    return;
                }

                int cursor_position = session_name_ent.get_position ();
                session_name_ent.text = filtered_text;
                session_name_ent.set_position (int.max (0, cursor_position - (new_text.length - filtered_text.length)));
            });

            // Sub Grid, all switch/checkbox/combobox/spin
            // except Actions.
            sub_grid = new Gtk.Grid ();
            sub_grid.column_homogeneous = true;
            sub_grid.halign = Gtk.Align.CENTER;
            sub_grid.margin_top = 0;
            sub_grid.margin_bottom = 0;
            sub_grid.margin_start = 0;
            sub_grid.margin_end = 0;
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

            append (sub_grid);

            // Bind Settings - Start
            settings.bind ("screen-capture-area", screen_cmb, "active-id", GLib.SettingsBindFlags.DEFAULT);
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
                update_format_selection (format_cmb.get_active_id ());
                settings.set_string ("format", this.format);
            });
            // Bind Settings - End

            speakers_record = record_speakers_btn.active;
            mic_record = record_mic_btn.active;
            update_audio_button (
                record_speakers_btn,
                speaker_icon,
                speakers_record,
                "audio-volume-high-symbolic",
                "audio-volume-muted-symbolic"
            );
            update_audio_button (
                record_mic_btn,
                mic_icon,
                mic_record,
                "microphone-sensitivity-symbolic",
                "microphone-sensitivity-muted-symbolic"
            );

            if (!this.use_portal_capture) {
                var display = Gdk.Display.get_default ();
                if (display != null) {
                    var monitors = display.get_monitors ();
                    monitors.items_changed.connect ((position, removed, added) => {
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
                }
            }

            this.detect_monitors ();
            this.update_widgets_visibility ();

        }

        private Gtk.Image create_icon (string icon_name) {
            var image = new Gtk.Image.from_icon_name (icon_name);
            image.set_icon_size (Gtk.IconSize.LARGE);
            return image;
        }

        private void update_audio_button (Gtk.ToggleButton button,
                                          Gtk.Image icon,
                                          bool is_active,
                                          string active_icon,
                                          string inactive_icon) {
            icon.set_from_icon_name (is_active ? active_icon : inactive_icon);
            if (is_active) {
                button.add_css_class (Granite.STYLE_CLASS_ACCENT);
            } else {
                button.remove_css_class (Granite.STYLE_CLASS_ACCENT);
            }
        }

        private void update_format_selection (string? active_id) {
            int codec_idx = get_codec_index (active_id);
            if (codec_idx < 0) {
                codec_idx = 0;
            }

            this.format = codec_gsk[codec_idx];
            this.extension = codec_ext[codec_idx];
        }

        private int get_codec_index (string? codec_id) {
            if (codec_id == null) {
                return -1;
            }

            for (int i = 0; i < codec_gsk.length; i++) {
                if (codec_gsk[i] == codec_id) {
                    return i;
                    }
            }

            return -1;
        }

        private Gdk.Rectangle union_rectangles (Gdk.Rectangle lhs, Gdk.Rectangle rhs) {
            if (lhs.width <= 0 || lhs.height <= 0) {
                return rhs;
            }

            int left = int.min (lhs.x, rhs.x);
            int top = int.min (lhs.y, rhs.y);
            int right = int.max (lhs.x + lhs.width, rhs.x + rhs.width);
            int bottom = int.max (lhs.y + lhs.height, rhs.y + rhs.height);

            Gdk.Rectangle rect = Gdk.Rectangle ();
            rect.x = left;
            rect.y = top;
            rect.width = right - left;
            rect.height = bottom - top;
            return rect;
        }

        public void update_widgets_visibility () {
            GLib.Settings settings = WorkdayApp.settings;
            var last_capture_mode = (ScreenrecorderWindow.CaptureType) settings.get_enum ("last-capture-mode");
            bool is_all_capture = last_capture_mode == ScreenrecorderWindow.CaptureType.SCREEN;
            bool show_monitor_picker = !this.use_portal_capture && this.is_multi_monitor && is_all_capture;
            this.screen_label.set_visible (show_monitor_picker);
            this.screen_cmb.set_visible (show_monitor_picker);
            this.sub_grid.row_spacing = show_monitor_picker ? 6 : 12;
            this.set_margin_top (show_monitor_picker ? 6 : 10);
            this.set_margin_bottom (show_monitor_picker ? 5 : 10);
        }

        private void detect_monitors () {
            if (this.use_portal_capture) {
                this.is_multi_monitor = false;
                this.screen_cmb.remove_all ();
                this.monitor_rects.clear ();
                return;
            }

            GLib.Settings settings = WorkdayApp.settings;

            this.screen_cmb.remove_all ();
            this.monitor_rects.clear ();
            this.all_monitors_rect = Gdk.Rectangle ();

            // Always populate the 'all' option.
            this.screen_cmb.append ("all", _("All Monitors"));

            var display = Gdk.Display.get_default ();
            if (display == null) {
                this.is_multi_monitor = false;
                return;
            }

            var monitors = display.get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = monitors.get_item (i) as Gdk.Monitor;
                if (monitor == null) {
                    continue;
                }

                var monitor_rect = monitor.get_geometry ();
                this.all_monitors_rect = union_rectangles (this.all_monitors_rect, monitor_rect);
                string monitor_id = "monitor-%u".printf (i);
                string monitor_name = _("Monitor") + " %u".printf (i + 1);
                this.monitor_rects.set (monitor_id, monitor_rect);
                this.screen_cmb.append (monitor_id, monitor_name);
            }

            this.is_multi_monitor = this.monitor_rects.size > 1;

            string last_screen_selected = settings.get_string ("screen-capture-area");
            if (!this.screen_cmb.set_active_id (last_screen_selected)) {
                this.screen_cmb.set_active_id ("all");
            }

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

        public Gdk.Rectangle get_screen_capture_rectangle () {
            Gdk.Rectangle rect = Gdk.Rectangle ();
            if (this.use_portal_capture) {
                return rect;
            }

            string? active_id = this.screen_cmb.get_active_id ();
            if (active_id == null) {
                return rect;
            }

            if (active_id == "all") {
                return this.all_monitors_rect;
            }

            Gdk.Rectangle? selected_rect = this.monitor_rects.get (active_id);
            if (selected_rect != null) {
                return selected_rect;
            }

            return rect;
        }
    }
}
