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

using Gee;

namespace Workday {

    public class SessionRecorder : GLib.Object {

        struct FragmentInfo {
            public string name;
            public bool is_resolved;
            public bool is_invalid;
            public int duration; // msec.
        }

        ScreenrecorderWindow.CaptureType capture_mode;
        public Gdk.Window window;
        public string session_name { get; private set; }
        private int framerate;
        private bool are_speakers_recorded;
        private bool is_mic_recorded;
        private bool is_cursor_captured;
        private string format;
        private string extension;
        public int fragment_length; // seconds.

        public bool is_recording { get; private set; default = false; }
        public bool is_session_in_progress { get; private set; default = false; }
        private bool fragment_split_initiated { private get; private set; default = false; }

        private DateTime fragment_start_time;
        private string current_fragment_name;

        private Recorder recorder;
        private ArrayList<string> found_fragments;
        private HashMap<string, FragmentInfo?> fragments_info;
        private int resolved_fragments_total;

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
                            int fragment_length,
                            Gdk.Window? window) {

            this.capture_mode = capture_mode;
            this.session_name = session_name;
            this.framerate = frame_rate;
            this.are_speakers_recorded = record_speakers;
            this.is_mic_recorded = record_mic;
            this.is_cursor_captured = capture_cursor;
            this.format = format;
            this.extension = extension;
            this.fragment_length = fragment_length;
            this.window = window;
        }

        public void start_session () {
            this.start_fragment ();
            this.is_recording = true;
            this.is_session_in_progress = true;

            this.found_fragments = new ArrayList<string> ();
            this.fragments_info = new HashMap<string, FragmentInfo?> ();
        }

        private void start_fragment () {
            this.fragment_start_time = new DateTime.now ();
            // @TODO: use milliseconds suffix on fragments?
            var fragment_suffix = this.fragment_start_time.format ("%Y-%m-%d-%H-%M-%S");
            this.current_fragment_name = "Workday-%s%s".printf (fragment_suffix, this.extension);
            var session_dir = this.get_session_dir ();
            WorkdayApp.create_dir_if_missing (session_dir);
            var fragment_file_path = Path.build_filename (session_dir, this.current_fragment_name);
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

            // Auto-splitting mechanism, every fragment_length seconds.
            // @TODO: check if the recorder.pipeline provides a clock with msec resolution, which can be used instead of manually computing the timespan (which is unreliable, due to sleep/suspend times the computer may go through).
            int max_fragment_duration = this.fragment_length * 1000; // msec.
            Timeout.add_seconds (1, () => {
                if (this.is_session_in_progress && recorder.is_recording && recorder.query_position () >= (max_fragment_duration) - (2 * 1000) && !this.fragment_split_initiated) {
                    this.fragment_split_initiated = true;
                    var timespan = new DateTime.now ().difference (this.fragment_start_time);
                    int next_fragment_delay = max_fragment_duration - (int) (timespan / 1000);
                    if (next_fragment_delay < 1) {
                        next_fragment_delay = 1;
                    }
                    int stop_delay = next_fragment_delay - 100;
                    if (stop_delay < 1) {
                        stop_delay = 1;
                    }
                    stdout.printf("Fragment-splitting waits: stop_delay: %s; next_fragment_delay: %s\n", stop_delay.to_string(), next_fragment_delay.to_string());
                    Timeout.add (stop_delay, () => {
                        this.resolved_fragments_total += max_fragment_duration;
                        recorder.stop();
                        return false;
                    });
                    Timeout.add (next_fragment_delay, () => {
                        if (!recorder.is_recording && this.is_session_in_progress) {
                            this.is_recording = true;
                            start_fragment ();
                            this.fragment_split_initiated = false;
                            this.update_fragments_info ();
                        }
                        else {
                            Timeout.add (25, () => {
                                if (!recorder.is_recording && this.is_session_in_progress) {
                                    this.is_recording = true;
                                    start_fragment ();
                                    this.fragment_split_initiated = false;
                                    this.update_fragments_info ();
                                    return false;
                                }
                                return this.is_session_in_progress;
                            });
                        }
                        return false;
                    });
                    return false;
                }
                return this.is_session_in_progress;
            });
        }

        public void pause_session () {
            recorder.stop ();

            Timeout.add (450, () => {
                this.is_recording = recorder.is_recording;
                if (!this.is_recording) {
                    // stdout.printf ("pause_session (): Updating fragments info...\n");
                    this.update_fragments_info ();
                }
                return this.is_recording;
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
                if (!this.fragment_split_initiated) {
                    recorder.stop();
                }
                this.is_session_in_progress = false;

                Timeout.add (450, () => {
                    this.is_recording = recorder.is_recording;
                    if (!this.is_recording) {
                        if (this.join_full_session ()) {
                            this.delete_fragments ();
                        }
                    }
                    return this.is_recording;
                });
            }
        }

        public int query_position () {
            if (this.is_recording) {
                return this.resolved_fragments_total / 1000 + this.recorder.query_position () / 1000;
            }

            return this.resolved_fragments_total;
        }

        public string get_session_dir () {
            return Path.build_filename (
                Environment.get_user_special_dir (UserDirectory.VIDEOS),
                WorkdayApp.SAVE_FOLDER,
                this.session_name);
        }

        private void update_fragments_info () {
            this.found_fragments = this.find_fragment_files ();
            var unresolved_fragments = this.get_unresolved_fragments ();

            if (this.current_fragment_name != "" && this.is_recording) {
                unresolved_fragments.remove (this.current_fragment_name);
            }
            // print_list ("Unresolved fragments:", unresolved_fragments);

            foreach (var frag_name in unresolved_fragments) {
                var fragment_info = FragmentInfo () {
                    name = frag_name,
                    is_resolved = false,
                    is_invalid = false,
                    duration = 0
                };
                this.fragments_info.set (frag_name, fragment_info);
            }

            var discoverer = new Gst.PbUtils.Discoverer (5 * Gst.SECOND);
            discoverer.discovered.connect ((info, err) => {
                bool success = info.get_result () == Gst.PbUtils.DiscovererResult.OK;
                stdout.printf ("Discovered URI: %s\n", info.get_uri ());
                var frag_name = File.new_for_uri (info.get_uri ())
                    .query_info ("*", FileQueryInfoFlags.NONE)
                    .get_name ();
                stdout.printf ("  File name: %s\n", frag_name);
                var frag_info = fragments_info.get (frag_name);
                frag_info.is_resolved = true;
                frag_info.is_invalid = !success;

                if (success) {
                    stdout.printf ("  Duration: %s\n", info.get_duration ().to_string ());
                    frag_info.duration = (int) (info.get_duration () / Gst.MSECOND);
                }

                // Vala structs are value-types, we must unset, then set the new struct.
                this.fragments_info.unset (frag_info.name);
                this.fragments_info.set (frag_info.name, frag_info);
            });
            discoverer.finished.connect (() => {
                this.update_resolved_fragments_total ();
                discoverer.stop ();
                discoverer = null;
            });
            discoverer.start ();

            foreach (var frag_name in unresolved_fragments) {
                discoverer.discover_uri_async (File.new_for_path (Path.build_filename (this.get_session_dir (), frag_name)).get_uri ());
            }
        }

        private void update_resolved_fragments_total () {
            int total = 0;
            foreach (var frag_info in this.fragments_info.values) {
                if (frag_info.is_resolved && !frag_info.is_invalid && frag_info.name in this.found_fragments) {
                    total += frag_info.duration;
                }
            }
            this.resolved_fragments_total = total;
        }

        private ArrayList<string> find_fragment_files () {
            var fragments = new ArrayList<string> ();
            var session_dir = this.get_session_dir ();
            // Reference snippet: https://stackoverflow.com/a/27703385
            Dir dir = Dir.open(session_dir);
            string? name = null;
            while ((name = dir.read_name ()) != null) {
                string fragment_pattern = "Workday-[0-9-]*%s$".printf (this.extension);
                if (Regex.match_simple (fragment_pattern, name)) {
                    string path = Path.build_filename (session_dir, name);
                    if (FileUtils.test (path, FileTest.IS_REGULAR)) {
                        fragments.add (name);
                    }
                }
            }

            return fragments;
        }

        private ArrayList<string> get_unresolved_fragments () {
            var known_fragments = this.fragments_info.keys;
            // print_list ("Known Fragments:", known_fragments);
            var unresolved_fragments = new ArrayList<string> ();
            foreach (string fragment_name in this.found_fragments) {
                if (!(fragment_name in known_fragments) ||
                    !(this.fragments_info.get (fragment_name).is_resolved)) {
                    unresolved_fragments.add (fragment_name);
                }
            }

            return unresolved_fragments;
        }

        private void print_list (string label, Collection<string> list) {
            stdout.printf (label + ":\n");
            foreach (var item in list) {
                stdout.printf ("  " + item + "\n");
            }
        }

        private bool join_full_session () {
            string command = "for file in Workday-*; do echo \"file $file\" >> workday-file-list.txt; done && ffmpeg -f concat -i workday-file-list.txt -codec copy Full-%s.mp4 && rm workday-file-list.txt".printf (this.session_name);
            return this.run_cli(this.get_session_dir (), command) == 0;
        }

        private void delete_fragments () {
            this.run_cli (this.get_session_dir (), "rm Workday-*.mp4");
        }

        private int run_cli (string cwd, string command) {
            int cmd_status;
            try {
                string[] spawn_args = {
                    "/bin/bash",
                    "-c",
                    command
                };
                string[] spawn_env = Environ.get ();
                string cmd_stdout;
                string cmd_stderr;

                Process.spawn_sync (cwd,
                    spawn_args,
                    spawn_env,
                    SpawnFlags.SEARCH_PATH,
                    null,
                    out cmd_stdout,
                    out cmd_stderr,
                    out cmd_status
                );
            } catch (SpawnError e) {
                cmd_status = 1;
	        }

	        return cmd_status;
        }
    }
}
