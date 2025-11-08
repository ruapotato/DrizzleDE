#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

# Add wlroots and wayland dependencies
env.Append(CPPPATH=["src/", "protocols/"])
env.Append(CPPDEFINES=["WLR_USE_UNSTABLE"])
env.ParseConfig("pkg-config --cflags --libs wlroots wayland-server pixman-1")

# Our source files (C++ and C)
sources = Glob("src/*.cpp") + Glob("src/*.c") + Glob("protocols/*.c")

# Build the library
if env["platform"] == "linux":
    library = env.SharedLibrary(
        "addons/wayland_compositor/bin/libwayland_compositor{}{}".format(
            env["suffix"], env["SHLIBSUFFIX"]
        ),
        source=sources,
    )
    Default(library)
