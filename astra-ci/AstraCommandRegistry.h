#pragma once
#include <string>

namespace astra {
using CommandHandler = int(*)(void* luaState);
void initializeCommandRegistry();
bool dispatchCommand(void* luaState, const std::string& command, int& returnCount);
}
