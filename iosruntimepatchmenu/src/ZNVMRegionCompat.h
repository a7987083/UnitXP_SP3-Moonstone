#pragma once

#include <mach/mach.h>
#include <mach/vm_map.h>

static inline kern_return_t ZNVMRegionCompat(
    vm_map_read_t task,
    mach_vm_address_t *address,
    mach_vm_size_t *size,
    vm_region_flavor_t flavor,
    vm_region_info_t info,
    mach_msg_type_number_t *infoCount,
    mach_port_t *objectName)
{
    if (!address || !size) return KERN_INVALID_ARGUMENT;

    vm_address_t region = (vm_address_t)(*address);
    vm_size_t regionSize = (vm_size_t)(*size);
    kern_return_t kr = vm_region_64(task,
                                    &region,
                                    &regionSize,
                                    flavor,
                                    info,
                                    infoCount,
                                    objectName);
    if (kr == KERN_SUCCESS) {
        *address = (mach_vm_address_t)region;
        *size = (mach_vm_size_t)regionSize;
    }
    return kr;
}

#ifndef mach_vm_region
#define mach_vm_region ZNVMRegionCompat
#endif
