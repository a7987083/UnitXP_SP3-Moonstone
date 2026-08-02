#pragma once

#include <string>

namespace moonMarkerGuildAuth {

bool isAuthQuery(const std::string& command);
bool isAdvancedCommand(const std::string& command);
bool isAuthorized(void* luaState);
int pushAuthStatus(void* luaState);
int denyAdvanced(void* luaState);
int handleAdvancedCommand(void* luaState, const std::string& command);

} // namespace moonMarkerGuildAuth
