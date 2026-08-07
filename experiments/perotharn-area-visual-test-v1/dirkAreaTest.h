#pragma once

#include <string>

namespace dirkAreaTest {

// Local visual-only simulation. No packets, damage, aura, charm, or server-side object creation.
bool showPre(float scale = 1.0f);
bool showCast(float scale = 1.0f);
bool showFull(float preDelaySeconds = 2.0f, float castHoldSeconds = 2.0f, float scale = 1.0f);

// Read-only reverse-engineering helper. Dumps selected WoW.exe code ranges around the
// DynamicObject / AreaModel / destination-effect paths without calling or patching them.
bool dumpNativeVisualCode(std::string& outputPath);

void clear();
void update();
std::string statusText();

} // namespace dirkAreaTest
