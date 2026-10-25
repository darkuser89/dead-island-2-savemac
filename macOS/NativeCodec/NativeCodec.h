// SPDX-License-Identifier: AGPL-3.0-or-later
#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
uint64_t di2_hash64(const void *bytes, size_t size);
size_t di2_compress_bound(size_t size);
size_t di2_compress(void *output, size_t capacity, const void *input, size_t size);
size_t di2_decompress(void *output, size_t capacity, const void *input, size_t size);
int di2_codec_error(size_t result);
#ifdef __cplusplus
}
#endif
