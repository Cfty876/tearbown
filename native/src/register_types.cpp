#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "voxel_volume.h"

using namespace godot;

static void initialize_voxcore(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(VoxelPalette);
	GDREGISTER_CLASS(VoxelVolume);
}

static void uninitialize_voxcore(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT voxcore_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_voxcore);
	init_obj.register_terminator(uninitialize_voxcore);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
