#pragma once

#include <cstdint>
#include <string>

#include "Vanilla1121_functions.h"

namespace nativeM2Test {

struct Status {
    bool active;
    bool contextExists;
    bool contextMatches;
    bool resourceReady;
    bool renderReady;
    bool attachedToRenderList;
    std::uint32_t contextPointer;
    std::uint32_t playerObjectPointer;
    std::uint32_t modelPointer;
    std::uint32_t modelContextPointer;
    std::uint32_t modelRefCount;
    std::uint32_t modelUpdateMarker;
    unsigned long createCalls;
    unsigned long createSuccesses;
    unsigned long updateCalls;
    unsigned long reattachCalls;
    unsigned long reattachSuccesses;
    unsigned long releaseCalls;
    unsigned long droppedStalePointers;
    unsigned long loadChecks;
    unsigned long loadReadyTransitions;
    C3Vector position;
    std::string lastErrorStage;
};

// Creates one white MoonBeam M2 four yards in front of the player.
bool createNearPlayer(C3Vector& position);

// Keeps the test model's world matrix and active timestamp current.
void update();

// Removes the test model when it still belongs to the live M2 context.
void clear();

Status status();

} // namespace nativeM2Test
