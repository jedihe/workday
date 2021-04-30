/*-
 * Copyright (c) 2014-2018 elementary LLC.
 * Copyright (C) 2021 John Herreño <jedihe@gmail.com>
 *
 * This software is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this software; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 *              John Herreño <jedihe@gmail.com>
 */

public class Workday.MonitorLabelWindow : Gtk.Window {

    public MonitorLabelWindow (Gdk.Rectangle monitor_rect, string monitor_label) {
        var label = new Gtk.Label ("<span size='15000'>%s</span>\n%i × %i".printf (monitor_label, monitor_rect.width, monitor_rect.height)) {
            use_markup = true
        };
        label.margin = 12;
        add (label);
        move (monitor_rect.x, monitor_rect.y);
    }

    construct {
        input_shape_combine_region (null);
        accept_focus = false;
        decorated = false;
        resizable = false;
        deletable = false;
        can_focus = false;
        skip_taskbar_hint = true;
        skip_pager_hint = true;
        type_hint = Gdk.WindowTypeHint.TOOLTIP;
        set_keep_above (true);
        opacity = 0.8;
    }
}
