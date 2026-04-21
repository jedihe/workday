namespace Workday {

    public class CaptureSource : GLib.Object {

        public enum Backend {
            X11,
            PORTAL
        }

        public Backend backend;
        public ScreenrecorderWindow.CaptureType capture_mode;
        public Gdk.Window? window;
        public Gdk.Rectangle capture_rect;
        public bool has_capture_rect = false;
        public PortalScreenCastSession? portal_session;
        public uint portal_node_id;
        public uint portal_source_type;
        public string? restore_token;

        public CaptureSource.for_x11_rectangle (ScreenrecorderWindow.CaptureType capture_mode,
                                               Gdk.Rectangle capture_rect) {
            this.backend = Backend.X11;
            this.capture_mode = capture_mode;
            this.capture_rect = capture_rect;
            this.has_capture_rect = true;
        }

        public CaptureSource.for_x11_window (ScreenrecorderWindow.CaptureType capture_mode,
                                            Gdk.Window window) {
            this.backend = Backend.X11;
            this.capture_mode = capture_mode;
            this.window = window;
            this.capture_rect = Gdk.Rectangle ();
        }

        public CaptureSource.for_portal (ScreenrecorderWindow.CaptureType capture_mode,
                                         PortalScreenCastSession portal_session) {
            this.backend = Backend.PORTAL;
            this.capture_mode = capture_mode;
            this.portal_session = portal_session;
            this.portal_node_id = portal_session.node_id;
            this.portal_source_type = portal_session.source_type;
            this.restore_token = portal_session.restore_token;
            this.capture_rect = portal_session.capture_rect;
            this.has_capture_rect = portal_session.has_capture_rect;
        }

        public bool is_portal () {
            return this.backend == Backend.PORTAL;
        }

        public int open_pipewire_remote () throws Error {
            if (this.portal_session == null) {
                throw new IOError.FAILED (_("Missing portal session."));
            }

            return this.portal_session.open_pipewire_remote ();
        }

        public void close () {
            if (this.portal_session != null) {
                this.portal_session.close ();
                this.portal_session = null;
            }
        }
    }

    public class PortalScreenCastSession : GLib.Object {

        private const string PORTAL_BUS_NAME = "org.freedesktop.portal.Desktop";
        private const string PORTAL_OBJECT_PATH = "/org/freedesktop/portal/desktop";
        private const string PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties";
        private const string REQUEST_INTERFACE = "org.freedesktop.portal.Request";
        private const string SESSION_INTERFACE = "org.freedesktop.portal.Session";
        private const string SCREENCAST_INTERFACE = "org.freedesktop.portal.ScreenCast";

        private const uint SOURCE_MONITOR = 1;
        private const uint SOURCE_WINDOW = 2;
        private const uint CURSOR_HIDDEN = 1;
        private const uint CURSOR_EMBEDDED = 2;

        public uint node_id;
        public uint source_type;
        public Gdk.Rectangle capture_rect;
        public bool has_capture_rect = false;
        public string? restore_token;

        private DBusConnection connection;
        private string session_handle;
        private bool is_closed = false;

        private PortalScreenCastSession (DBusConnection connection, string session_handle) {
            this.connection = connection;
            this.session_handle = session_handle;
            this.capture_rect = Gdk.Rectangle ();
        }

        public static CaptureSource request_capture_source (ScreenrecorderWindow.CaptureType capture_mode,
                                                            bool capture_cursor) throws Error {
            if (capture_mode == ScreenrecorderWindow.CaptureType.AREA) {
                throw new IOError.NOT_SUPPORTED (_("Area capture is not available on Wayland yet."));
            }

            var connection = Bus.get_sync (BusType.SESSION, null);

            uint available_source_types = get_uint_property (connection, SCREENCAST_INTERFACE, "AvailableSourceTypes");
            uint requested_source_type = capture_mode == ScreenrecorderWindow.CaptureType.SCREEN ?
                SOURCE_MONITOR :
                SOURCE_WINDOW;

            if ((available_source_types & requested_source_type) == 0) {
                throw new IOError.NOT_SUPPORTED (
                    capture_mode == ScreenrecorderWindow.CaptureType.SCREEN ?
                    _("This desktop portal backend does not support monitor capture.") :
                    _("This desktop portal backend does not support window capture.")
                );
            }

            uint available_cursor_modes = CURSOR_HIDDEN;
            try {
                available_cursor_modes = get_uint_property (connection, SCREENCAST_INTERFACE, "AvailableCursorModes");
            } catch (Error e) {
                debug ("ScreenCast portal does not expose AvailableCursorModes: %s", e.message);
            }
            uint cursor_mode = CURSOR_HIDDEN;
            if (capture_cursor && (available_cursor_modes & CURSOR_EMBEDDED) != 0) {
                cursor_mode = CURSOR_EMBEDDED;
            }

            string create_handle_token = generate_token ("create");
            string session_handle_token = generate_token ("session");
            VariantBuilder create_options_builder = new VariantBuilder (new VariantType ("a{sv}"));
            create_options_builder.add ("{sv}", "handle_token", new Variant.string (create_handle_token));
            create_options_builder.add ("{sv}", "session_handle_token", new Variant.string (session_handle_token));
            Variant create_results = call_request (
                connection,
                "CreateSession",
                new Variant ("(@a{sv})", create_options_builder.end ()),
                build_request_path (connection, create_handle_token)
            );

            Variant? session_handle_variant = create_results.lookup_value ("session_handle", new VariantType ("s"));
            if (session_handle_variant == null) {
                throw new IOError.FAILED (_("The portal did not return a session handle."));
            }

            var session = new PortalScreenCastSession (connection, session_handle_variant.get_string ());

            try {
                string select_handle_token = generate_token ("select");
                VariantBuilder select_options_builder = new VariantBuilder (new VariantType ("a{sv}"));
                select_options_builder.add ("{sv}", "handle_token", new Variant.string (select_handle_token));
                select_options_builder.add ("{sv}", "types", new Variant.uint32 (requested_source_type));
                select_options_builder.add ("{sv}", "multiple", new Variant.boolean (false));
                select_options_builder.add ("{sv}", "cursor_mode", new Variant.uint32 (cursor_mode));
                call_request (
                    connection,
                    "SelectSources",
                    new Variant ("(o@a{sv})", session.session_handle, select_options_builder.end ()),
                    build_request_path (connection, select_handle_token)
                );

                string start_handle_token = generate_token ("start");
                VariantBuilder start_options_builder = new VariantBuilder (new VariantType ("a{sv}"));
                start_options_builder.add ("{sv}", "handle_token", new Variant.string (start_handle_token));
                Variant start_results = call_request (
                    connection,
                    "Start",
                    new Variant ("(os@a{sv})", session.session_handle, "", start_options_builder.end ()),
                    build_request_path (connection, start_handle_token)
                );

                session.update_from_start_results (start_results);
                return new CaptureSource.for_portal (capture_mode, session);
            } catch (Error e) {
                session.close ();
                throw e;
            }
        }

        public int open_pipewire_remote () throws Error {
            VariantBuilder options_builder = new VariantBuilder (new VariantType ("a{sv}"));
            UnixFDList? out_fd_list = null;
            Variant reply = this.connection.call_with_unix_fd_list_sync (
                PORTAL_BUS_NAME,
                PORTAL_OBJECT_PATH,
                SCREENCAST_INTERFACE,
                "OpenPipeWireRemote",
                new Variant ("(o@a{sv})", this.session_handle, options_builder.end ()),
                new VariantType ("(h)"),
                DBusCallFlags.NONE,
                -1,
                null,
                out out_fd_list,
                null
            );

            if (out_fd_list == null) {
                throw new IOError.FAILED (_("The portal did not return a PipeWire file descriptor."));
            }

            int fd_index = reply.get_child_value (0).get_handle ();
            return out_fd_list.get (fd_index);
        }

        public void close () {
            if (this.is_closed) {
                return;
            }

            this.is_closed = true;

            try {
                this.connection.call_sync (
                    PORTAL_BUS_NAME,
                    this.session_handle,
                    SESSION_INTERFACE,
                    "Close",
                    null,
                    null,
                    DBusCallFlags.NONE,
                    -1,
                    null
                );
            } catch (Error e) {
                warning ("Failed to close portal session %s: %s", this.session_handle, e.message);
            }
        }

        private void update_from_start_results (Variant start_results) throws Error {
            Variant? streams_variant = start_results.lookup_value ("streams", new VariantType ("a(ua{sv})"));
            if (streams_variant == null || streams_variant.n_children () == 0) {
                throw new IOError.FAILED (_("The portal did not return any PipeWire streams."));
            }

            Variant stream_entry = streams_variant.get_child_value (0);
            this.node_id = stream_entry.get_child_value (0).get_uint32 ();

            Variant stream_properties = stream_entry.get_child_value (1);

            Variant? source_type_variant = stream_properties.lookup_value ("source_type", new VariantType ("u"));
            if (source_type_variant != null) {
                this.source_type = source_type_variant.get_uint32 ();
            }

            Variant? position_variant = stream_properties.lookup_value ("position", new VariantType ("(ii)"));
            if (position_variant != null) {
                this.capture_rect.x = position_variant.get_child_value (0).get_int32 ();
                this.capture_rect.y = position_variant.get_child_value (1).get_int32 ();
            }

            Variant? size_variant = stream_properties.lookup_value ("size", new VariantType ("(ii)"));
            if (size_variant != null) {
                this.capture_rect.width = size_variant.get_child_value (0).get_int32 ();
                this.capture_rect.height = size_variant.get_child_value (1).get_int32 ();
                this.has_capture_rect = true;
            }

            Variant? restore_token_variant = start_results.lookup_value ("restore_token", new VariantType ("s"));
            if (restore_token_variant != null) {
                this.restore_token = restore_token_variant.get_string ();
            }
        }

        private static uint get_uint_property (DBusConnection connection,
                                               string interface_name,
                                               string property_name) throws Error {
            Variant reply = connection.call_sync (
                PORTAL_BUS_NAME,
                PORTAL_OBJECT_PATH,
                PROPERTIES_INTERFACE,
                "Get",
                new Variant ("(ss)", interface_name, property_name),
                new VariantType ("(v)"),
                DBusCallFlags.NONE,
                -1,
                null
            );

            return reply.get_child_value (0).get_variant ().get_uint32 ();
        }

        private static Variant call_request (DBusConnection connection,
                                             string method_name,
                                             Variant parameters,
                                             string expected_request_path) throws Error {
            var waiter = new PortalRequestWaiter (connection, expected_request_path);

            Variant reply = connection.call_sync (
                PORTAL_BUS_NAME,
                PORTAL_OBJECT_PATH,
                SCREENCAST_INTERFACE,
                method_name,
                parameters,
                new VariantType ("(o)"),
                DBusCallFlags.NONE,
                -1,
                null
            );

            string returned_request_path = reply.get_child_value (0).get_string ();
            if (returned_request_path != expected_request_path) {
                waiter.resubscribe (returned_request_path);
            }

            try {
                return waiter.wait_for_response ();
            } finally {
                waiter.close ();
            }
        }

        private static string generate_token (string prefix) {
            return "workday_%s_%s".printf (prefix, Uuid.string_random ().replace ("-", "_"));
        }

        private static string build_request_path (DBusConnection connection, string handle_token) {
            string unique_name = connection.get_unique_name ();
            string sender = unique_name.has_prefix (":") ? unique_name.substring (1) : unique_name;
            return "/org/freedesktop/portal/desktop/request/%s/%s".printf (
                sender.replace (".", "_"),
                handle_token
            );
        }
    }

    private class PortalRequestWaiter : GLib.Object {

        private const string PORTAL_BUS_NAME = "org.freedesktop.portal.Desktop";
        private const string REQUEST_INTERFACE = "org.freedesktop.portal.Request";

        private DBusConnection connection;
        private MainLoop loop;
        private uint subscription_id = 0;
        private uint response_code = 2;
        private Variant? results;
        private bool has_response = false;

        public PortalRequestWaiter (DBusConnection connection, string request_path) {
            this.connection = connection;
            this.loop = new MainLoop ();
            this.resubscribe (request_path);
        }

        public void resubscribe (string request_path) {
            if (this.subscription_id != 0) {
                this.connection.signal_unsubscribe (this.subscription_id);
            }

            this.subscription_id = this.connection.signal_subscribe (
                PORTAL_BUS_NAME,
                REQUEST_INTERFACE,
                "Response",
                request_path,
                null,
                DBusSignalFlags.NONE,
                (connection, sender_name, object_path, interface_name, signal_name, parameters) => {
                    this.response_code = parameters.get_child_value (0).get_uint32 ();
                    this.results = parameters.get_child_value (1);
                    this.has_response = true;

                    if (this.loop.is_running ()) {
                        this.loop.quit ();
                    }
                }
            );
        }

        public Variant wait_for_response () throws Error {
            if (!this.has_response) {
                this.loop.run ();
            }

            switch (this.response_code) {
                case 0:
                    if (this.results != null) {
                        return this.results;
                    }
                    throw new IOError.FAILED (_("The screen cast request returned no data."));
                case 1:
                    throw new IOError.CANCELLED (_("The screen cast request was cancelled."));
                default:
                    throw new IOError.FAILED (_("The screen cast request failed."));
            }
        }

        public void close () {
            if (this.subscription_id != 0) {
                this.connection.signal_unsubscribe (this.subscription_id);
                this.subscription_id = 0;
            }
        }
    }
}
