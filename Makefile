ROOT := $(shell pwd)
BREW ?= $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)/opt
HL_DIR := $(ROOT)/hashlink
HL_BUILD := $(HL_DIR)/build-libs
GAME_DIR ?= $(HOME)/Library/Application Support/Steam/steamapps/common/Dead Cells
VERSION ?= 1.0.1

.PHONY: all setup vm sdl steam dist release steam-api check install uninstall clean

all: dist check

setup:
	./tools/setup-deps.sh

vm:
	cmake -S $(HL_DIR) -B $(HL_BUILD) \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DBUILD_TESTING=OFF \
		-DDOWNLOAD_DEPENDENCIES=OFF \
		-DWITH_SDL=OFF -DWITH_SQLITE=OFF -DWITH_VIDEO=OFF -DWITH_HEAPS=OFF -DWITH_MYSQL=OFF \
		-DOPENAL_INCLUDE_DIR=$(BREW)/openal-soft/include \
		-DOPENAL_LIBRARY=$(BREW)/openal-soft/lib/libopenal.dylib \
		-DCMAKE_C_FLAGS="-Dopenal_soft" \
		-DCMAKE_PREFIX_PATH="$(BREW)/mbedtls@3;$(BREW)/openal-soft;$(BREW)/libuv;$(BREW)/libpng;$(BREW)/jpeg-turbo;$(BREW)/libogg;$(BREW)/libvorbis"
	cmake --build $(HL_BUILD) -j10

sdl: vm
	clang -O2 -arch arm64 -shared -fPIC -DGL_SILENCE_DEPRECATION \
		-I$(HL_DIR)/src -I$(BREW)/sdl2/include -I$(BREW)/sdl2/include/SDL2 \
		libsrc/libs/sdl/sdl.c libsrc/libs/sdl/gl.c \
		-o $(HL_BUILD)/bin/sdl.hdll \
		-L$(HL_BUILD)/bin -lhl -L$(BREW)/sdl2/lib -lSDL2 -framework OpenGL \
		-install_name @rpath/sdl.hdll

steam: vm
	cd libsrc/hlsteam && \
	for f in native/*.cpp; do \
		clang++ -arch arm64 -O2 -fPIC -std=c++17 -w -I sdk/public -I $(HL_DIR)/src -c $$f -o $${f%.cpp}.o; \
	done && \
	clang++ -arch arm64 -shared -o $(HL_BUILD)/bin/steam.hdll native/*.o \
		-L$(HL_BUILD)/bin -lhl -Lsdk/redistributable_bin/osx -lsteam_api \
		-install_name @rpath/steam.hdll && \
	cp -f sdk/redistributable_bin/osx/libsteam_api.dylib $(HL_BUILD)/bin/

dist: vm sdl steam
	BREW="$(BREW)" ./tools/package.sh

release: dist
	VERSION="$(VERSION)" ./tools/release.sh

steam-api:
	./tools/setup-steam-api.sh

tools/checknatives: tools/checknatives.c
	clang -O2 -arch arm64 -o tools/checknatives tools/checknatives.c

check: dist tools/checknatives
	./tools/checknatives analysis/natives.txt dist

install: dist
	./tools/install.sh --game-dir "$(GAME_DIR)"

uninstall:
	./tools/install.sh --game-dir "$(GAME_DIR)" --uninstall

