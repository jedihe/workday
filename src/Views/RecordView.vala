/*
 * Copyright 2018-2020 Ryo Nakano
 *           2020 Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

namespace Workday {

    public class RecordView : Gtk.Box {

        private Gtk.Label time_label;
        private Gtk.Button back_button;
        private uint count;
        private bool pause = false;
        private int seconds;
        private SessionRecorder session_recorder;

        public signal void request_new_session ();


        public RecordView () {

            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 12,
                margin: 0
            );
        }

        construct {

            time_label = new Gtk.Label (null) {
                hexpand = true
            };
            time_label.get_style_context ().add_class (Granite.STYLE_CLASS_H2_LABEL);
            back_button = new Gtk.Button.with_label ("New Session") {
                halign = Gtk.Align.START
            };
            back_button.get_style_context ().add_class (Granite.STYLE_CLASS_BACK_BUTTON);
            back_button.set_sensitive (false);
            back_button.clicked.connect (() => request_new_session ());

            var label_grid = new Gtk.Grid ();
            label_grid.column_spacing = 6;
            label_grid.attach (back_button, 0, 1, 1, 1);
            label_grid.attach (time_label, 0, 2, 1, 1);

            pack_start (label_grid, false, false);
        }

        public void set_recorder(SessionRecorder session_recorder) {
            this.session_recorder = session_recorder;
        }

        public async void trigger_stop_recording () {

            stop_count ();
        }

        public void init_count () {
            seconds = 0;
            pause = false;
            show_timer_label (time_label, 0, 0, 0, 0);
            start_count ();
        }

        private void show_timer_label (Gtk.Label label, int minutes_10, int minutes_1, int seconds_10, int seconds_1) {

            label.label = "<span size='64000' weight='normal'>%i%i</span><span size='24000' weight='normal'>:%i%i</span>".printf (minutes_10, minutes_1, seconds_10, seconds_1);
            label.use_markup = true;
            label.margin_top = 20;
        }

        private void start_count () {
            back_button.set_sensitive (false);
            count = Timeout.add (1000, () => {
                stdout.printf ("On RecordView.start_count () - Timeout.add ()\n");
                int display_minutes;
                int display_seconds;

                // If the user pressed "pause", do not count this second.
                if (pause) {
                    return false;
                }

                seconds = session_recorder.query_position();

                display_minutes = seconds / 60;
                display_seconds = seconds % 60;

                show_timer_label (time_label, display_minutes / 10, display_minutes % 10, display_seconds / 10, display_seconds % 10);
                return session_recorder.is_session_in_progress;
            });
        }

        public void pause_count () {

            pause = true;
            count = 0;
            back_button.set_sensitive (true);
        }

        public void resume_count () {

            pause = false;
            start_count ();
            back_button.set_sensitive (false);
        }

        public void stop_count () {

            pause = true;
            count = 0;
        }
    }
}
