# Project name, programming language and version
project (
    'com.github.jedihe.workday',
    'vala', 'c',
    version: '2.3.0',
    license: 'GPL-3.0'
)

# Translation module
i18n = import ('i18n')

# GNOME module
gnome = import ('gnome')

# Project arguments
add_project_arguments (
    '-DGETTEXT_PACKAGE="@0@"'.format (meson.project_name ()),
    language: 'c'
)

# Compiling resources
asresources = gnome.compile_resources (
    'as-resources',
    join_paths ('data', meson.project_name ()) + '.gresource.xml',
    source_dir: 'data',
    c_name: 'as'
)

# Listing dependencies
dependencies = [
    dependency ('glib-2.0'),
    dependency ('gee-0.8'),
    dependency ('granite', version: '>=5.4.0'),
    dependency ('gtk+-3.0'),
    dependency ('x11'),
    dependency ('gdk-x11-3.0'),
    dependency ('gstreamer-1.0'),
    dependency ('gstreamer-pbutils-1.0'),
# gstreamer-plugins-good is missing .vapi definitions, potentially-useful links:
# - https://github.com/elementary/code/issues/678
# - https://gi.readthedocs.io/en/latest/buildsystems/meson.html
# - https://gitlab.freedesktop.org/gstreamer/gst-plugins-good
# - https://gitlab.gnome.org/GNOME/vala/ (GStreamer bindings are bundled with Vala itself)
# - https://mail.gnome.org/archives/vala-list/2011-May/msg00060.html (using extern C code)
# - https://developer.gnome.org/gtk-tutorial/stable/x159.html (g_signal_connect() signature)
# - https://wiki.gnome.org/Projects/Vala/Bindings
# - sudo apt install libgstreamer-plugins-good1.0-dev (to install -dev library)
# In summary: better to wait for upstream to generate .vapi bindings
    #dependency ('gstreamer-plugins-good-1.0'),
    dependency ('clutter-gst-3.0'),
    dependency ('clutter-gtk-1.0')
]

subdir ('src')

# Defining executable
executable (
    meson.project_name (),
    sources,
    asresources,
    dependencies: dependencies,
    install: true
)

subdir('data')
subdir('po')

meson.add_install_script('meson/post_install.py')
