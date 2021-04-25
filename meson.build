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

# Resolve the math library, to use as dependency.
# See https://mesonbuild.com/howtox.html#add-math-library-lm-portably
cc = meson.get_compiler('c')
m_dep = cc.find_library('m', required: false)

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
    dependency ('clutter-gst-3.0'),
    dependency ('clutter-gtk-1.0'),
    m_dep
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
