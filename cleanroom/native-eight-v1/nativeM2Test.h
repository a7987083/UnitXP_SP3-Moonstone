#pragma once

#include <cstdint>
#include <string>

#include <d3d9.h>

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
    std::uint32_t activeCount;
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
    std::string color;
    std::string icon;
    std::string lastErrorStage;
};

// Compatibility test: creates a white/star MoonBeam four yards in front of player.
bool createNearPlayer(C3Vector& position);

// Compatibility overload: creates a white/star MoonBeam.
bool createAt(const C3Vector& position);

// Creates/replaces one native MoonBeam for the requested color slot.
// Supported colors: red, orange, yellow, green, cyan, blue, purple, white.
// Supported icons: star, circle, diamond, triangle, moon, square, cross, skull.
bool createAt(const std::string& colorName, const std::string& iconName,
              const C3Vector& position);

// Removes one color slot without affecting the other seven.
bool clearColor(const std::string& colorName);

// Returns normalized icon names and preserves legacy calls that omit an icon.
std::string defaultIconForColor(const std::string& colorName);
std::string iconForColor(const std::string& colorName);

// Updates all live native models and caches icon screen positions during sceneEnd.
void update();

// Draws cached fixed-size icons immediately before IDirect3DDevice9::Present.
void renderIcons(IDirect3DDevice9* device);

// Removes every native model.
void clear();

Status status();

} // namespace nativeM2Test
