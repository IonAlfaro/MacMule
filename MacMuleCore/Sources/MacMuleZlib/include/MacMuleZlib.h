#ifndef MACMULE_ZLIB_H
#define MACMULE_ZLIB_H

#include <stddef.h>
#include <stdint.h>

int macmule_zlib_inflate(
    const uint8_t *source,
    size_t sourceSize,
    uint8_t *destination,
    size_t *destinationSize,
    int raw
);

#endif
