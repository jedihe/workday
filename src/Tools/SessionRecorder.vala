/*
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
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
 * Authored by: John Herreño <jedihe@gmail.com>
 */

namespace Workday {

    public class SessionRecorder : GLib.Object {

        ScreenrecorderWindow.CaptureType capture_mode;
        public Gdk.Window window;
        public string session_name { get; private set; }
        private int framerate;
        private bool are_speakers_recorded;
        private bool is_mic_recorded;
        private bool is_cursor_captured;
        private string format;
        private string extension;

        public bool is_recording { get; private set; default = false; }
        public bool is_session_in_progress { get; private set; default = false; }

        private Recorder recorder;

        public SessionRecorder () {
        }

        public void config (ScreenrecorderWindow.CaptureType capture_mode,
                            string session_name,
                            int frame_rate,
                            bool record_speakers,
                            bool record_mic,
                            bool capture_cursor,
                            string format,
                            string extension,
                            Gdk.Window? window) {

            this.capture_mode = capture_mode;
            this.session_name = session_name;
            this.framerate = frame_rate;
            this.are_speakers_recorded = record_speakers;
            this.is_mic_recorded = record_mic;
            this.is_cursor_captured = capture_cursor;
            this.format = format;
            this.extension = extension;
            this.window = window;
        }

        public void start_session () {
            this.start_fragment ();
            this.is_recording = true;
            this.is_session_in_progress = true;
        }

        private void start_fragment () {
            DateTime now = new DateTime.now ();
            // @TODO: use milliseconds suffix on fragments?
            var fragment_name = now.format ("%Y-%m-%d-%H-%M-%S");
            var session_dir = this.get_session_dir ();
            WorkdayApp.create_dir_if_missing (session_dir);
            var fragment_file_path = Path.build_filename (session_dir, "Workday-%s%s".printf (fragment_name, this.extension));
            debug ("Fragment file created at: %s", fragment_file_path);

            this.recorder = new Recorder();
            recorder.config (capture_mode,
                            fragment_file_path,
                            framerate,
                            are_speakers_recorded,
                            is_mic_recorded,
                            is_cursor_captured,
                            format,
                            this.window);
            recorder.start ();

            // Auto-splitting mechanism, every 5min.
            // @TODO: use the system clock to compare real elapsed time vs. total recorded time and compensate as necessary, by briefly stopping the recording.
            Timeout.add_seconds (1, () => {
                if (recorder.query_position () >= 300 - 2) {
                    recorder.stop ();
                    Timeout.add (1000, () => {
                        if (!recorder.is_recording) {
                            this.is_recording = true;
                            start_fragment ();
                            return false;
                        }
                        return true;
                    });
                    return false;
                }
                return true;
            });
        }

        public void pause_session () {
            recorder.stop ();

            Timeout.add (450, () => {
                if (!recorder.is_recording) {
                    this.is_recording = false;
                    return false;
                }
                return true;
            });
        }

        public void resume_session () {
            if (this.is_session_in_progress && !this.is_recording) {
                this.start_fragment ();
                this.is_recording = true;
            }
        }

        public void stop_session () {
            if (this.is_recording || this.is_session_in_progress) {
                recorder.stop();

                Timeout.add (450, () => {
                    if (!recorder.is_recording) {
                        this.is_recording = false;
                        this.is_session_in_progress = false;
                        return false;
                    }
                    return true;
                });
            }
        }

        public int query_position () {
            if (this.is_recording) {
                return this.recorder.query_position ();
            }

            return 0;
        }

        public string get_session_dir () {
            return Path.build_filename (
                Environment.get_user_special_dir (UserDirectory.VIDEOS),
                WorkdayApp.SAVE_FOLDER,
                this.session_name);
        }
    }
}
