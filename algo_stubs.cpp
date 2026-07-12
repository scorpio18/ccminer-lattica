// Stubs for the single-algo (Lattica sha3d) build. The other algos' source files
// are excluded from the build; their functions are referenced only by dead
// switch branches that never execute for ALGO_SHA3D, so the linker is told
// to ignore those unresolved refs (see ccminer_LDFLAGS). A few DATA globals can
// still be name-referenced, so define them here with safe defaults.
#include <stdint.h>
#include <stdlib.h>

extern "C" {
	uint64_t scratchpad_size = 0;
	char* opt_scratchpad_url = NULL;
}
