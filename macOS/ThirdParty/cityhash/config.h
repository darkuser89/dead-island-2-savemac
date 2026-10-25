// Local configuration for little-endian Apple targets.
#define HAVE_BUILTIN_EXPECT 1
// The save format uses CityHash64, not the optional SSE4.2 CRC functions.
#ifdef __SSE4_2__
#undef __SSE4_2__
#endif
