#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle to a dbopl chip instance.
//
// We intentionally make this an opaque pointer (`void`) so Swift imports it
// portably as `UnsafeMutableRawPointer`/`OpaquePointer` across toolchains.
typedef void DBOPLChip;

// Create/destroy
DBOPLChip* dbopl_create(int32_t sample_rate);
void dbopl_destroy(DBOPLChip* chip);

// Register write
void dbopl_write(DBOPLChip* chip, uint8_t reg, uint8_t value);

// Generate mono samples into out_buffer (int32), length frames.
// out_buffer must have at least `frames` elements.
void dbopl_generate(DBOPLChip* chip, int32_t frames, int32_t* out_buffer);

#ifdef __cplusplus
}
#endif
