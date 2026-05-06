#include "MacMuleZlib.h"

#include <string.h>
#include <zlib.h>

int macmule_zlib_inflate(
    const uint8_t *source,
    size_t sourceSize,
    uint8_t *destination,
    size_t *destinationSize,
    int raw
) {
    if (source == NULL || destination == NULL || destinationSize == NULL) {
        return Z_STREAM_ERROR;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)source;
    stream.avail_in = (uInt)sourceSize;
    stream.next_out = destination;
    stream.avail_out = (uInt)*destinationSize;

    int result = inflateInit2(&stream, raw ? -MAX_WBITS : MAX_WBITS);
    if (result != Z_OK) {
        return result;
    }

    result = inflate(&stream, Z_FINISH);
    if (result == Z_STREAM_END) {
        *destinationSize = (size_t)stream.total_out;
        result = Z_OK;
    }

    inflateEnd(&stream);
    return result;
}
