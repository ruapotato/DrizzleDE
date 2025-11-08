#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

# Add X11 compositor dependencies
env.Append(CPPPATH=["src/"])
env.ParseConfig("pkg-config --cflags --libs x11 xcomposite xdamage xfixes xrender")
# Add XTest library for realistic input events (bypasses synthetic event detection)
env.Append(LIBS=["Xtst"])

# Our source files (C++ only, no protocols needed for X11)
sources = Glob("src/*.cpp")

# Build the library
if env["platform"] == "linux":
    library = env.SharedLibrary(
        "addons/x11_compositor/bin/libx11_compositor{}{}".format(
            env["suffix"], env["SHLIBSUFFIX"]
        ),
        source=sources,
    )
    Default(library)
