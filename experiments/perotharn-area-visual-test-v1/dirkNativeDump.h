#pragma once

#include <string>

namespace dirkNativeDump {

// Read-only diagnostic: copies selected WoW.exe code bytes to DirkNativeDump.txt.
// It does not patch, hook, call, or mutate the inspected functions.
bool dump(std::string& outputPath, std::string& status);

} // namespace dirkNativeDump
