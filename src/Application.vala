/*
 * Copyright (c) 2020 Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
 *                         (https://github.com/dr-Styki/ScreenRec)
 *
 * Copyright (c) 2018 mohelm97 (https://github.com/mohelm97/ScreenRecorder)
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
 */

namespace Workday {

    public class WorkdayApp : Gtk.Application {
        
        public static GLib.Settings settings;
        private ScreenrecorderWindow window = null;

        private new OptionEntry[] options;

        private bool screen = false;
        private bool win = false;
        private bool area = false;

        public const string SAVE_FOLDER = _("Screen Records");

        public WorkdayApp () {
            Object (
                application_id: "com.github.jedihe.workday",
                flags: ApplicationFlags.FLAGS_NONE
            );
        }
        
        construct {

            flags |= ApplicationFlags.HANDLES_COMMAND_LINE;

            options = new OptionEntry[3];
            options[0] = { "window", 'w', 0, OptionArg.NONE, ref win, _("Capture active window"), null };
            options[1] = { "area", 'r', 0, OptionArg.NONE, ref area, _("Capture area"), null };
            options[2] = { "screen", 's', 0, OptionArg.NONE, ref screen, _("Capture the whole screen"), null };

            add_main_option_entries (options);

            settings = new GLib.Settings ("com.github.jedihe.workday");
            weak Gtk.IconTheme default_theme = Gtk.IconTheme.get_default ();
            default_theme.add_resource_path ("/com/github/jedihe/workday");

            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => {
                if (window != null) {
                    if (window.can_quit()) {

                        window.close();

                    } else {

                        window.iconify ();
                    }
                }
            });

            add_action (quit_action);
            set_accels_for_action ("app.quit", {"<Control>q", "Escape"});

            var open_records_folder_action = new SimpleAction ("open-records-folder", VariantType.STRING);
            open_records_folder_action.activate.connect ((parameter) => {
                if (parameter == null) {
                    return;
                }
                try {
                    File records_folder = File.new_for_path (settings.get_string ("folder-dir"));
                    AppInfo.launch_default_for_uri (records_folder.get_uri (), null);
                    debug("launch_default_for_uri %s".printf (parameter.get_string ()));
                } catch (Error e) {
                    GLib.warning (e.message);
                }
            });
            add_action (open_records_folder_action);

            var granite_settings = Granite.Settings.get_default ();
            var gtk_settings = Gtk.Settings.get_default ();

            gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;

            granite_settings.notify["prefers-color-scheme"].connect (() => {
                gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            });
        }

        protected override void activate () {

            if (window != null) {

                window.present ();
                return;

            } else {

                var provider = new Gtk.CssProvider ();
                provider.load_from_resource ("/com/github/jedihe/workday/stylesheet.css");
                Gtk.StyleContext.add_provider_for_screen (
                Gdk.Screen.get_default (),
                provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );

                window = new ScreenrecorderWindow (this);
                window.get_style_context ().add_class ("rounded");
                window.show_all ();
                if (screen || area || win) {
                    
                    window.iconify ();
                    set_capture_type(window);
                    window.autostart();
                }
            }
        }

        public static int main (string[] args) {

            Gtk.init (ref args);
            Gst.init (ref args);
            Gst.Debug.set_active(true);
            var err = GtkClutter.init (ref args);
            if (err != Clutter.InitError.SUCCESS) {
                error ("Could not initalize clutter! " + err.to_string ());
            }

            var app = new WorkdayApp ();
            return app.run (args);
        }

        public static void create_dir_if_missing (string path) {
            if (!File.new_for_path (path).query_exists ()) {
                try {
                    File file = File.new_for_path (path);
                    file.make_directory ();
                } catch (Error e) {
                    debug (e.message);
                }
            }
        }

        private void reset_cmd_line_options () {
            screen = false;
            win = false;
            area = false;
        }

        private void set_capture_type(ScreenrecorderWindow winapp) {

            if (screen){
                window.set_capture_type(1);
            }
            else if (win) {
                window.set_capture_type(2);
            }
            else if (area) {
                window.set_capture_type(3);
            }
            reset_cmd_line_options ();
        }
    }
}
