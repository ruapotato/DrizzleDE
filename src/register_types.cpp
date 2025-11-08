#include "register_types.hpp"
#include "x11_compositor.hpp"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include <stdio.h>

using namespace godot;

void initialize_x11_compositor_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    ClassDB::register_class<X11Compositor>();
}

void uninitialize_x11_compositor_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
    // Initialization entry point
    GDExtensionBool GDE_EXPORT x11_compositor_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization
    ) {
        // Debug: Print to stderr to see if this function is called
        fprintf(stderr, "[X11Compositor] Library init function called!\n");
        fflush(stderr);

        godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

        init_obj.register_initializer(initialize_x11_compositor_module);
        init_obj.register_terminator(uninitialize_x11_compositor_module);
        init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

        GDExtensionBool result = init_obj.init();
        fprintf(stderr, "[X11Compositor] Library init result: %d\n", result);
        fflush(stderr);

        return result;
    }
}
