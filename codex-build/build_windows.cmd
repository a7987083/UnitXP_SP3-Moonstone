@echo off
setlocal EnableExtensions

if "%~1"=="" (
  echo Usage: build_windows.cmd PROJECT_ROOT
  exit /b 2
)

set "PROJECT_ROOT=%~1"
set "LLVM_BIN=C:\Program Files\LLVM\bin"
set "PATH=%LLVM_BIN%;%PATH%"
set "BUILD_DIR=%PROJECT_ROOT%\build"

where clang-cl.exe
if errorlevel 1 exit /b 3
where lld-link.exe
if errorlevel 1 exit /b 4

cd /d "%BUILD_DIR%"

lld-link.exe /lib /def:kernel32.def /machine:x86 /out:kernel32.lib
if errorlevel 1 exit /b 10

set "INC=/Iinclude /I../third_party/minhook/include /I../third_party/minhook/src /I../third_party/minhook/src/hde /I../src"
set "CFLAGS=--target=i686-pc-windows-msvc /nologo /c /O1 /GS- /Zl /D_X86_ /DWIN32 /D_WIN32 /DNULL=0 /DMINHOOK_DISABLE_INTRINSICS"
set "CPPFLAGS=%CFLAGS% /GR- /EHs-c- /std:c++17"

clang-cl.exe %CPPFLAGS% %INC% /Fo:dllmain.obj ../src/dllmain.cpp
if errorlevel 1 exit /b 20
clang-cl.exe %CPPFLAGS% %INC% /Fo:dbc_internal.obj ../src/dbc_internal.cpp
if errorlevel 1 exit /b 21
clang-cl.exe %CPPFLAGS% %INC% /Fo:visual_native.obj ../src/visual_native.cpp
if errorlevel 1 exit /b 22
clang-cl.exe %CPPFLAGS% %INC% /Fo:moonmarker_compat.obj ../src/moonmarker_compat.cpp
if errorlevel 1 exit /b 23
clang-cl.exe %CPPFLAGS% %INC% /Fo:moonmarker_runtime_guard.obj ../src/moonmarker_runtime_guard.cpp
if errorlevel 1 exit /b 24
clang-cl.exe %CPPFLAGS% %INC% /Fo:m2scan_media.obj ../src/m2scan_media.cpp
if errorlevel 1 exit /b 25
clang-cl.exe %CPPFLAGS% %INC% /Fo:moonmarker_advanced.obj ../src/moonmarker_advanced.cpp
if errorlevel 1 exit /b 26
clang-cl.exe %CPPFLAGS% %INC% /Fo:profiler_handoff_b1r5r8.obj ../src/profiler_handoff_b1r5r8.cpp
if errorlevel 1 exit /b 27
clang-cl.exe %CPPFLAGS% %INC% /Fo:dreamavatar_native.obj ../src/dreamavatar_native.cpp
if errorlevel 1 exit /b 28
clang-cl.exe %CPPFLAGS% %INC% /Fo:dreamweapon_native.obj ../src/dreamweapon_native.cpp
if errorlevel 1 exit /b 29
clang-cl.exe %CPPFLAGS% %INC% /Fo:aura_engine.obj ../src/aura_engine.cpp
if errorlevel 1 exit /b 30
clang-cl.exe %CFLAGS% %INC% /Fo:buffer.obj ../third_party/minhook/src/buffer.c
if errorlevel 1 exit /b 31
clang-cl.exe %CFLAGS% %INC% /Fo:hook.obj ../third_party/minhook/src/hook.c
if errorlevel 1 exit /b 32
clang-cl.exe %CFLAGS% %INC% /Fo:trampoline.obj ../third_party/minhook/src/trampoline.c
if errorlevel 1 exit /b 33
clang-cl.exe %CFLAGS% %INC% /Fo:hde32.obj ../third_party/minhook/src/hde/hde32.c
if errorlevel 1 exit /b 34

lld-link.exe /dll /machine:x86 /nodefaultlib /subsystem:windows,5.01 /timestamp:0 /entry:DllMain@12 ^
  /out:"%PROJECT_ROOT%\taiyangshendian.dll" ^
  dllmain.obj dbc_internal.obj visual_native.obj moonmarker_compat.obj moonmarker_runtime_guard.obj ^
  m2scan_media.obj moonmarker_advanced.obj profiler_handoff_b1r5r8.obj dreamavatar_native.obj ^
  dreamweapon_native.obj aura_engine.obj buffer.obj hook.obj trampoline.obj hde32.obj kernel32.lib ^
  /alternatename:__imp__CloseHandle@4=__imp__CloseHandle ^
  /alternatename:__imp__CreateToolhelp32Snapshot@8=__imp__CreateToolhelp32Snapshot ^
  /alternatename:__imp__FlushInstructionCache@12=__imp__FlushInstructionCache ^
  /alternatename:__imp__FindFirstFileA@8=__imp__FindFirstFileA ^
  /alternatename:__imp__FindNextFileA@8=__imp__FindNextFileA ^
  /alternatename:__imp__FindClose@4=__imp__FindClose ^
  /alternatename:__imp__GetCurrentProcess@0=__imp__GetCurrentProcess ^
  /alternatename:__imp__GetCurrentProcessId@0=__imp__GetCurrentProcessId ^
  /alternatename:__imp__GetCurrentThreadId@0=__imp__GetCurrentThreadId ^
  /alternatename:__imp__GetLastError@0=__imp__GetLastError ^
  /alternatename:__imp__GetModuleFileNameA@12=__imp__GetModuleFileNameA ^
  /alternatename:__imp__GetModuleHandleA@4=__imp__GetModuleHandleA ^
  /alternatename:__imp__GetModuleHandleW@4=__imp__GetModuleHandleW ^
  /alternatename:__imp__GetProcAddress@8=__imp__GetProcAddress ^
  /alternatename:__imp__GetSystemInfo@4=__imp__GetSystemInfo ^
  /alternatename:__imp__GetThreadContext@8=__imp__GetThreadContext ^
  /alternatename:__imp__HeapAlloc@12=__imp__HeapAlloc ^
  /alternatename:__imp__HeapCreate@12=__imp__HeapCreate ^
  /alternatename:__imp__HeapDestroy@4=__imp__HeapDestroy ^
  /alternatename:__imp__HeapFree@12=__imp__HeapFree ^
  /alternatename:__imp__HeapReAlloc@16=__imp__HeapReAlloc ^
  /alternatename:__imp__InterlockedCompareExchange@12=__imp__InterlockedCompareExchange ^
  /alternatename:__imp__InterlockedExchange@8=__imp__InterlockedExchange ^
  /alternatename:__imp__OpenThread@12=__imp__OpenThread ^
  /alternatename:__imp__ResumeThread@4=__imp__ResumeThread ^
  /alternatename:__imp__SetThreadContext@8=__imp__SetThreadContext ^
  /alternatename:__imp__Sleep@4=__imp__Sleep ^
  /alternatename:__imp__SuspendThread@4=__imp__SuspendThread ^
  /alternatename:__imp__Thread32First@8=__imp__Thread32First ^
  /alternatename:__imp__Thread32Next@8=__imp__Thread32Next ^
  /alternatename:__imp__VirtualAlloc@16=__imp__VirtualAlloc ^
  /alternatename:__imp__VirtualFree@12=__imp__VirtualFree ^
  /alternatename:__imp__VirtualProtect@16=__imp__VirtualProtect ^
  /alternatename:__imp__VirtualQuery@12=__imp__VirtualQuery ^
  /alternatename:__imp__CreateFileA@28=__imp__CreateFileA ^
  /alternatename:__imp__WriteFile@20=__imp__WriteFile ^
  /alternatename:__imp__ReadFile@20=__imp__ReadFile ^
  /alternatename:__imp__GetFileSize@8=__imp__GetFileSize ^
  /alternatename:__imp__SetFilePointer@16=__imp__SetFilePointer ^
  /alternatename:__imp__GetSystemTime@4=__imp__GetSystemTime ^
  /alternatename:__imp__GetLocalTime@4=__imp__GetLocalTime ^
  /alternatename:__imp__GetTickCount@0=__imp__GetTickCount
if errorlevel 1 exit /b 40

certutil -hashfile "%PROJECT_ROOT%\taiyangshendian.dll" SHA256
exit /b 0
