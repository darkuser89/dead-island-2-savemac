// SPDX-License-Identifier: AGPL-3.0-or-later
#include "NativeCodec.h"
#include "city.h"
#include "zstd.h"
uint64_t di2_hash64(const void *bytes, size_t size) {
    return CityHash64(static_cast<const char *>(bytes), size);
}
size_t di2_compress_bound(size_t size) { return ZSTD_compressBound(size); }
size_t di2_compress(void *output, size_t capacity, const void *input, size_t size) {
    return ZSTD_compress(output, capacity, input, size, 3);
}
size_t di2_decompress(void *output, size_t capacity, const void *input, size_t size) {
    return ZSTD_decompress(output, capacity, input, size);
}
int di2_codec_error(size_t result) { return ZSTD_isError(result); }
