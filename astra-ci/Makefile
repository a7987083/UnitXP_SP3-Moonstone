TRIPLE   = i686-pc-windows-msvc
CXX      = clang-cl
LD       = lld-link
XWIN_ROOT       = ./xwinSDK
MINHOOK_DIR     = ./MinHook_134
D3DX_INCLUDES   = ./d3d9x_headers
TARGET   = Astra.dll
SRCS = AstraMain.cpp AstraCommandRegistry.cpp Vanilla1121_functions.cpp GroundProbe.cpp AutoRange.cpp \
       MoonMarkerGuildAuth.cpp MoonMarkerRuntimeGuard.cpp MoonMarkerMainModel.cpp MoonMarkerDreamAvatar.cpp \
       MoonMarkerM2Scanner.cpp MoonMarkerAdvancedState.cpp moonMarker.cpp nativeM2Test.cpp \
       $(MINHOOK_DIR)/src/buffer.c $(MINHOOK_DIR)/src/hde/hde32.c \
       $(MINHOOK_DIR)/src/hook.c $(MINHOOK_DIR)/src/trampoline.c
OBJS = $(patsubst %.cpp,%.obj,$(patsubst %.c,%.obj,$(SRCS)))
LIBS = user32.lib kernel32.lib gdi32.lib libcmt.lib
CXXFLAGS = --target=$(TRIPLE) /O1 /MT /EHsc /W3 /nologo /hotpatch /arch:SSE2 /fp:precise \
           /std:c++17 /Zc:__cplusplus /DWIN32_LEAN_AND_MEAN /DNOMINMAX /D_X86_ /D_WIN32 /DNULL=0 \
           /Z7 /GS /Gy -flto=thin \
           -imsvc "$(XWIN_ROOT)/crt/include" -imsvc "$(XWIN_ROOT)/sdk/include/ucrt" \
           -imsvc "$(XWIN_ROOT)/sdk/include/um" -imsvc "$(XWIN_ROOT)/sdk/include/shared" \
           -imsvc "$(MINHOOK_DIR)/include" -imsvc "$(D3DX_INCLUDES)"
LDFLAGS = /NOLOGO /DLL /MACHINE:X86 /OPT:REF /OPT:ICF /SAFESEH /NXCOMPAT /FUNCTIONPADMIN \
          /DEBUG /PDB:"$(TARGET:.dll=.pdb)" /ignore:4099 \
          /LIBPATH:"$(XWIN_ROOT)/crt/lib/x86" /LIBPATH:"$(XWIN_ROOT)/sdk/lib/ucrt/x86" \
          /LIBPATH:"$(XWIN_ROOT)/sdk/lib/um/x86"
all: $(TARGET)
$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) /OUT:$@ $(OBJS) $(LIBS)
%.obj: %.cpp
	$(CXX) $(CXXFLAGS) /c $< /Fo:$@
%.obj: %.c
	$(CXX) $(CXXFLAGS) /c $< /Fo:$@
clean:
	rm -f $(OBJS) *.dll *.lib *.exp *.pdb
.PHONY: all clean
