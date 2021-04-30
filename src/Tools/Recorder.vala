/*
 * Rewrite of the python kazam gstreamer backend in Vala.
 * Copyright (c) 2020 Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
 *
 * Original code avaible at https://github.com/hzbd/kazam/blob/master/kazam/backend/gstreamer.py
 * Copyright 2012 David Klasinc <bigwhale@lubica.net>
 *
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
 * Authored by: Stevy THOMAS (dr_Styki) <dr_Styki@hack.i.ng>
 */

namespace Workday {

    public class Recorder : GLib.Object {

        ScreenrecorderWindow.CaptureType capture_mode;
        public Gdk.Window window;
        public Gdk.Rectangle capture_rect { get; private set; }
        private string tmp_file;
        private int framerate;
        private bool are_speakers_recorded;
        private bool is_mic_recorded;
        private bool is_cursor_captured;
        private int startx;
        private int starty;
        private int endx;
        private int endy;
        private int fallback_timer_count;

        public bool is_recording_in_progress { get; private set; default = false; }
        public bool is_recording { get; private set; default = false; }
        public int width { get; private set; }
        public int height { get; private set; }

        dynamic Gst.Pipeline pipeline;
        private Gst.Element mux;
        private Gst.Element videnc;
        private Gst.Element sink;
        private Gst.Element file_queue;
        private Gst.Element videosrc;
        private Gst.Element vid_in_queue;
        private Gst.Element vid_out_queue;
        private Gst.Element vid_caps_filter;
        private Gst.Element videoconvert2;
        private Gst.Element vid_caps_filter2;
        private Gst.Element videoconvert;
        private Gst.Element videorate;
        private Gst.Element aud_out_queue;
        private Gst.Element audioconv;
        private Gst.Element audioenc;
        private Gst.Element audiosrc;
        private Gst.Element aud_caps_filter;
        private Gst.Element aud_in_queue;
        private Gst.Element audio2conv;
        private Gst.Element audio2src;
        private Gst.Element aud2_caps_filter;
        private Gst.Element aud2_in_queue;
        private Gst.Element audiomixer;
        private Gst.Element videocrop;
        private string format;
        private bool crop_vid = false;
        private int cpu_cores;


        public Recorder () {
        }

        public void config (ScreenrecorderWindow.CaptureType capture_mode,
                            string tmp_file,
                            int frame_rate,
                            bool record_speakers,
                            bool record_mic,
                            bool capture_cursor,
                            string format,
                            Gdk.Window? window,
                            Gdk.Rectangle? capture_rect) {

            this.capture_mode = capture_mode;
            this.tmp_file = tmp_file;
            this.framerate = frame_rate;
            this.are_speakers_recorded = record_speakers;
            this.is_mic_recorded = record_mic;
            this.is_cursor_captured = capture_cursor;
            this.format = format;
            this.window = window;
            this.capture_rect = capture_rect;

            string cores = "0-1";
            try {
                Process.spawn_command_line_sync ("cat /sys/devices/system/cpu/online", out cores);
            } catch (Error e) {
                warning (e.message);
            }
            this.cpu_cores = int.parse (cores.substring (2));

            pipeline = new Gst.Pipeline ("screencast-pipe");

            setup_video_source ();
            setup_audio_sources ();
            setup_filesink ();
            setup_pipeline ();
            setup_links ();

            debug("pipeline.get_bus ().add_watch;");
            pipeline.get_bus ().add_watch (Priority.DEFAULT, bus_message_cb);
            pipeline.set_state (Gst.State.READY);
        }

        private void setup_video_source () {

            videosrc = Gst.ElementFactory.make("ximagesrc", "video_src");

            if (this.window != null) {
                Gdk.Rectangle tmp_rect = Gdk.Rectangle ();
                this.window.get_frame_extents (out tmp_rect);
                capture_rect = tmp_rect;
            }

            this.width = capture_rect.width;
            this.height = capture_rect.height;

            if (capture_mode == ScreenrecorderWindow.CaptureType.SCREEN || 
                capture_mode == ScreenrecorderWindow.CaptureType.AREA) {

                this.startx = capture_rect.x;
                this.starty = capture_rect.y;
                this.endx = this.startx + this.width - 1;
                this.endy = this.starty + this.height - 1;

                // H264 requirement is that video dimensions are divisible by 2.
                // If they are not, we have to get rid of that extra pixel.
                if  ( this.width % 2 != 0 && (this.format == "x264enc-mkv" ||
                                              this.format == "x264enc-mp4")) {
                    this.endx -= 1;
                    this.width -= 1;
                }

                if  ( this.height % 2 != 0 && (this.format == "x264enc-mkv" ||
                                               this.format == "x264enc-mp4")) {
                    this.endy -= 1;
                    this.height -= 1;
                }

                videosrc.set ("startx", startx);
                videosrc.set ("starty", starty);
                videosrc.set ("endx",   endx);
                videosrc.set ("endy",   endy);

            } else if (capture_mode == ScreenrecorderWindow.CaptureType.CURRENT_WINDOW) {

                videosrc.set ("xid", ((Gdk.X11.Window) this.window).get_xid());
                debug ("Capture current window.");

                this.startx = 0;
                this.starty = 0;

                if (this.format == "x264enc-mkv" ||
                    this.format == "x264enc-mp4") {

                    this.videocrop = Gst.ElementFactory.make("videocrop", "cropper");

                    if (this.width % 2 == 1) {

                        this.videocrop.set_property("left", 1);
                        this.crop_vid = true;
                        this.width -= 1;
                    }

                    if (height % 2 == 1) {

                        this.videocrop.set_property("bottom", 1);
                        this.crop_vid = true;
                        this.height -= 1;
                    }
                }
            } else {

                print("Open an error dialog window ?");
            }

            debug("setup_video_source \n");
            debug ("startx: " + startx.to_string());
            debug ("starty: " + starty.to_string());
            debug ("width: " + width.to_string());
            debug ("height: " + height.to_string());
            debug ("endx: " + endx.to_string());
            debug ("endy: " + endy.to_string());

            videosrc.set_property ("use-damage", false);
            videosrc.set_property ("show-pointer", is_cursor_captured);

            Gst.Caps vid_caps = Gst.Caps.from_string("video/x-raw,framerate=1/2");
            vid_caps_filter = Gst.ElementFactory.make("capsfilter", "vid_filter");
            vid_caps_filter.set_property("caps", vid_caps);

            videoconvert = Gst.ElementFactory.make("videoconvert", "videoconvert");
            videorate = Gst.ElementFactory.make("videorate", "video_rate");

            if (this.format == "x264enc-mp4") {

                Gst.Caps vid_caps2 = Gst.Caps.from_string("video/x-raw,format=I420");
                vid_caps_filter2 = Gst.ElementFactory.make("capsfilter", "vid_filter2");
                vid_caps_filter2.set_property("caps", vid_caps2);

                videoconvert2 = Gst.ElementFactory.make("videoconvert", "videoconvert2");
            }

            if (format != "raw") {

                debug("Format != raw | Format -> " + format);

                if (this.format == "x264enc-mkv" || 
                    this.format == "x264enc-mp4") {

                    videnc = Gst.ElementFactory.make("x264enc", "video_encoder");

                } else {

                    videnc = Gst.ElementFactory.make(this.format, "video_encoder");
                }
            }

            if (format == "raw") {

                debug("Format == raw | Format -> " + format);
                mux = Gst.ElementFactory.make("avimux", "muxer");

            } else if (format == "vp8enc") {

                videnc.set_property("cpu-used", 2);
                videnc.set_property("end-usage", 0); // vbr
                videnc.set_property("target-bitrate", 800000000);
                videnc.set_property("static-threshold", 1000);
                videnc.set_property("token-partitions", 2);
                videnc.set_property("max-quantizer", 30);
                videnc.set_property("threads", cpu_cores);

                mux = Gst.ElementFactory.make("webmmux", "muxer");

            } else if (format == "x264enc-mp4") {

                // x264enc supports maximum of four cpu_cores
                if (cpu_cores > 4) {

                    cpu_cores = 4;
                }

                videnc.set_property("speed-preset", 3); // veryfast
                videnc.set_property("pass", 4);
                videnc.set_property("quantizer", 18);
                videnc.set_property("threads", cpu_cores);
                videnc.set_property("key-int-max", 15); // 15 frames @ 0.5fps == 30sec
                mux = Gst.ElementFactory.make("mp4mux", "muxer");
                mux.set_property("faststart", 1);
                mux.set_property("faststart-file", this.tmp_file + ".mux");
                mux.set_property("streamable", 1);

            } else if (format == "x264enc-mkv") {

                // x264enc supports maximum of four cpu_cores
                if (cpu_cores > 4) {

                    cpu_cores = 4;
                }

                videnc.set_property("speed-preset", 3); // veryfast
                videnc.set_property("pass", 4);
                videnc.set_property("quantizer", 18);
                videnc.set_property("threads", cpu_cores);
                videnc.set_property("key-int-max", 15); // 15 frames @ 0.5fps == 30sec
                mux = Gst.ElementFactory.make("matroskamux", "muxer");
                mux.set_property("streamable", 1);

            } else if (format == "avenc_huffyuv") {

                mux = Gst.ElementFactory.make("avimux", "muxer");
                videnc.set_property("bitrate", 500000);

            } else if (format == "avenc_ljpeg") {

                mux = Gst.ElementFactory.make("avimux", "muxer");
            }

            vid_in_queue = Gst.ElementFactory.make("queue", "queue_v1");
            vid_out_queue = Gst.ElementFactory.make("queue", "queue_v2");
        }

        private void setup_audio_sources () {

            debug("setup_audio_sources \n");

            if (are_speakers_recorded || is_mic_recorded) {

                aud_out_queue = Gst.ElementFactory.make("queue", "queue_a_out");
                audioconv = Gst.ElementFactory.make("audioconvert", "audio_conv");

                if (format == "vp8enc") {

                    audioenc = Gst.ElementFactory.make("vorbisenc", "audio_encoder");
                    audioenc.set_property("quality", 1);

                } else {

                    audioenc = Gst.ElementFactory.make("lamemp3enc", "audio_encoder");
                    audioenc.set_property("quality", 0);
                }
            }

            if (are_speakers_recorded) {

                string audio_source = get_default_audio_output();

                audiosrc = Gst.ElementFactory.make("pulsesrc", "audio_src");
                audiosrc.set_property("device", audio_source);
                Gst.Caps aud_caps = Gst.Caps.from_string("audio/x-raw");
                aud_caps_filter = Gst.ElementFactory.make("capsfilter", "aud_filter");
                aud_caps_filter.set_property("caps", aud_caps);
                aud_in_queue = Gst.ElementFactory.make("queue", "queue_a_in");
            }

            if (is_mic_recorded) {

                string audio2_source = get_default_audio_input();

                audio2src = Gst.ElementFactory.make("pulsesrc", "audio2_src");
                audio2src.set_property("device", audio2_source);
                Gst.Caps aud2_caps = Gst.Caps.from_string("audio/x-raw");
                aud2_caps_filter = Gst.ElementFactory.make("capsfilter", "aud2_filter");
                aud2_caps_filter.set_property("caps", aud2_caps);
                aud2_in_queue = Gst.ElementFactory.make("queue", "queue_a2_in");
                audio2conv = Gst.ElementFactory.make("audioconvert", "audio2_conv");
            }

            if (are_speakers_recorded && is_mic_recorded) {
                    
                audiomixer = Gst.ElementFactory.make("adder", "audiomixer");
            }
        }

        private void setup_filesink () {

            debug("setup_filesink \n");
            debug("tmp_file location : " + this.tmp_file);

            sink = Gst.ElementFactory.make ("filesink", "sink");
            sink.set ("location", this.tmp_file);
            file_queue = Gst.ElementFactory.make ("queue", "queue_file");

        }

        private void setup_pipeline () {

            debug("setup_pipeline \n");

            bool re = pipeline.add(videosrc);
            debug("Pipeline.add(videosrc) -> " + re.to_string() + "\n");

            pipeline.add(vid_in_queue);

            if (crop_vid) {
                pipeline.add(videocrop);
            }

            pipeline.add(videorate);
            pipeline.add(vid_caps_filter);
            pipeline.add(videoconvert);

            if (this.format == "x264enc-mp4") {

                pipeline.add(vid_caps_filter2);
                pipeline.add(videoconvert2);
            }
            
            pipeline.add(vid_out_queue);
            pipeline.add(file_queue);

            if (this.format != "raw") {
                pipeline.add(videnc);
            }

            if (are_speakers_recorded || is_mic_recorded) {
                pipeline.add(audioconv);
                pipeline.add(audioenc);
                pipeline.add(aud_out_queue);
            }
            if (are_speakers_recorded) {
                pipeline.add(audiosrc);
                pipeline.add(aud_in_queue);
                pipeline.add(aud_caps_filter);
            }
            if (is_mic_recorded) {
                pipeline.add(audio2src);
                pipeline.add(aud2_in_queue);
                pipeline.add(aud2_caps_filter);
            }
            if (are_speakers_recorded && is_mic_recorded) {
                pipeline.add(audiomixer);
            }

            re = pipeline.add(mux);
            debug("pipeline.add(mux); -> " + re.to_string());

            pipeline.add(sink);
        }

        private void setup_links () {
            
            debug("setup_links \n");

            // Connect everything together
            bool re = videosrc.link(vid_in_queue);
            debug("videosrc.link(vid_in_queue); -> " + re.to_string());

            if (crop_vid) {

                re = vid_in_queue.link(videocrop);
                debug("vid_in_queue.link(vvideocrop); -> " + re.to_string());

                re = videocrop.link(videorate);
                debug("videocrop.link(videorate); -> " + re.to_string());

            } else {
                re = vid_in_queue.link(videorate);
                debug("vid_in_queue.link(videorate); -> " + re.to_string());
            }

            re = videorate.link(vid_caps_filter);
            debug("videorate.link(vid_caps_filter); -> " + re.to_string());

            re = vid_caps_filter.link(videoconvert);
            debug("vid_caps_filter.link(videoconvert); -> " + re.to_string());

            if (this.format == "x264enc-mp4") {

                re = videoconvert.link(vid_caps_filter2);
                debug("videoconvert.link(vid_caps_filter2); -> " + re.to_string());
            
                re = vid_caps_filter2.link(videoconvert2);
                debug("vid_caps_filter2.link(videoconvert2); -> " + re.to_string());
            }

            // RAW or Encoded
            if (format == "raw") { //RAW
                
                re = videoconvert.link(vid_out_queue);
                debug("videoconvert.link(vid_out_queue); -> " + re.to_string());

            } else if (format == "x264enc-mp4") {
                
                re = videoconvert2.link(videnc);
                debug("videoconvert2.link(videnc); -> " + re.to_string());
                re = videnc.link(vid_out_queue);
                debug("videnc.link(vid_out_queue); -> " + re.to_string());

            } else {
                re = videoconvert.link(videnc);
                debug("videoconvert.link(videnc); -> " + re.to_string());
                re = videnc.link(vid_out_queue);
                debug("videnc.link(vid_out_queue); -> " + re.to_string());
            }

            re = vid_out_queue.link(mux);
            debug("vid_out_queue.link(mux); -> " + re.to_string());
            

            if (are_speakers_recorded && is_mic_recorded) {
                
                //Linking Audio
                audiosrc.link(aud_in_queue);
                aud_in_queue.link(aud_caps_filter);
                aud_caps_filter.link(audiomixer);


                // Link second audio source to mixer
                audio2src.link(aud2_in_queue);
                aud2_in_queue.link(aud2_caps_filter);
                aud2_caps_filter.link(audiomixer);
                
                // Link mixer to audio convert
                audiomixer.link(audioconv);
            

            } else if (are_speakers_recorded) {

                //Linking Audio"
                audiosrc.link(aud_in_queue);
                aud_in_queue.link(aud_caps_filter);
                aud_caps_filter.link(audioconv);

            } else if (is_mic_recorded) {

                // Link second audio
                audio2src.link(aud2_in_queue);
                aud2_in_queue.link(aud2_caps_filter);
                aud2_caps_filter.link(audioconv);
            }


            if (are_speakers_recorded || is_mic_recorded) {

                // Link audio to muxer
                audioconv.link(audioenc);
                audioenc.link(aud_out_queue);
                aud_out_queue.link(mux);
            }

            re = mux.link(file_queue);
            debug("mux.link(file_queue); -> " + re.to_string());
            
            re = file_queue.link(sink);
            debug("file_queue.link(sink); -> " + re.to_string());
        }

        private bool bus_message_cb (Gst.Bus bus, Gst.Message msg) {
            switch (msg.type) {
            case Gst.MessageType.ERROR :
                GLib.Error err;

                string debug;

                msg.parse_error (out err, out debug);

                //display_error ("Screencast encountered a gstreamer error while recording, creating a screencast is not possible:\n%s\n\n[%s]".printf (err.message, debug), true);
                stderr.printf ("Error: %s\n", debug);
                pipeline.set_state (Gst.State.NULL);
                break;
            case Gst.MessageType.EOS :
                // stdout.printf("On EOS message in pipeline\n");
                // this.print_pos(pipeline);

                pipeline.set_state (Gst.State.NULL);

                this.is_recording = false;
                this.is_recording_in_progress = false;

                //save_file ();
                pipeline.dispose ();
                pipeline = null;
                break;
            default :
                break;
            }

            return true;
        }

        private string get_default_audio_output () {

            string default_output = "";

            try {
                string sound_devices = "";
                Process.spawn_command_line_sync ("pacmd list-sinks", out sound_devices);
                var regex = new Regex ("(?<=\\*\\sindex:\\s\\d\\s\\sname:\\s<)[\\w\\.\\-]*");
                MatchInfo match_info;

                if (regex.match (sound_devices, 0, out match_info)) {
                    default_output = match_info.fetch (0);
                }

                default_output += ".monitor";
                debug ("Detected system sound device: %s", default_output);

            } catch (Error e) {

                warning (e.message);
            }

            debug("Default audio output = " + default_output);
            return default_output;
        }

        private string get_default_audio_input () {
            
            string default_input = "";

            try {
                string sound_devices = "";
                Process.spawn_command_line_sync ("pacmd list-sources", out sound_devices);
                var regex = new Regex ("(?<=\\*\\sindex:\\s\\d\\s\\sname:\\s<)[\\w\\.\\-]*");
                MatchInfo match_info;
            
                if (regex.match (sound_devices, 0, out match_info)) {
                    default_input = match_info.fetch (0);
                }
            
                debug ("Detected microphone: %s", default_input);

            } catch (Error e) {

                warning (e.message);
            }

            debug("Default audio input = " + default_input);
            return default_input;
        }

        public void start () {

            pipeline.set_state (Gst.State.PLAYING);
            this.is_recording = true;
            this.is_recording_in_progress = true;
            this.start_fallback_timer();
        }

        public void pause () {
            pipeline.set_state (Gst.State.PAUSED);
            this.is_recording = false;
            this.print_pos(pipeline);
        }

        public void resume () {

            this.pipeline.set_state (Gst.State.PLAYING);
            this.is_recording = true;
        }

        public void stop () {
            stdout.printf("Before processing Recorder.stop()\n");
            this.print_pos(pipeline);

            if (!this.is_recording) {
                //this.resume();
            }
            pipeline.send_event (new Gst.Event.eos ());

            stdout.printf("After processing Recorder.stop()\n");
            this.print_pos(pipeline);
        }

        private void start_fallback_timer() {
            Timeout.add (1000, () => {
                fallback_timer_count++;
                return this.is_recording && this.pipeline_query_position() == -1;
            });
        }

        private int64 pipeline_query_position() {
            int64 position = -1;
            if (this.is_recording) {
                pipeline.query_position(Gst.Format.TIME, out position);
            }

            return position;
        }

        public int query_position() {
            int64 pos = this.pipeline_query_position();
            if (pos == -1) {
                stdout.printf("Recorder.query_position(): using fallback_timer_count\n");
                return fallback_timer_count * 1000;
            }
            else {
                stdout.printf("Recorder.query_position(): using pipeline_query_position()\n");
                return (int) (pos / 1000000);
            }
        }

        private void print_pos(Gst.Pipeline ppl) {
            stdout.printf("Pipeline position; %s\n", pipeline_query_position().to_string());
        }
    }
}
