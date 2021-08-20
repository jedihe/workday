# Workday

Record a timelapse of your workday.

## Building & Installation

You'll need the following dependencies:

* meson
* libgranite-dev
* libgtk3-dev
* libx11-dev
* libgstreamer1.0-dev
* libclutter-gst-3.0-dev
* libclutter-gtk-1.0-dev
* valac

Run `meson` to configure the build environment and then `ninja` to build and install

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`, then execute with `com.github.jedihe.workday`

    sudo ninja install
    com.github.jedihe.workday

## Credits
Originally forked from [ScreenRec](https://github.com/dr-Styki/ScreenRec). Icon by [Nararyans R.I. (Fatih20)](https://github.com/Fatih20). Video of Fatih20 making the icon [here](https://lbry.tv/@Fatih109:4/Final-Design:6?r=Cg1pp5MCWV1a5Nj5jDumPs9b13dNZqWG)
