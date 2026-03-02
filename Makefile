CC=clang
AR=ar
CFLAGS=-O3 -g -fomit-frame-pointer -march=native -Isrc/libdivsufsort/include -Isrc
OBJDIR=obj
LDFLAGS=-L. -lapultra

$(OBJDIR)/%.o: src/../%.c
	@mkdir -p '$(@D)'
	$(CC) $(CFLAGS) -c $< -o $@

APP := apultra
LIB := libapultra.a

LIBOBJS += $(OBJDIR)/src/expand.o
LIBOBJS += $(OBJDIR)/src/matchfinder.o
LIBOBJS += $(OBJDIR)/src/shrink.o
LIBOBJS += $(OBJDIR)/src/libdivsufsort/lib/divsufsort.o
LIBOBJS += $(OBJDIR)/src/libdivsufsort/lib/divsufsort_utils.o
LIBOBJS += $(OBJDIR)/src/libdivsufsort/lib/sssort.o
LIBOBJS += $(OBJDIR)/src/libdivsufsort/lib/trsort.o

APPOBJS := $(OBJDIR)/src/apultra.o

all: $(APP) $(LIB)

$(APP): $(LIB) $(APPOBJS)
	$(CC) $^ $(LDFLAGS) -o $(APP)

$(LIB): $(LIBOBJS)
	$(AR) rcs $(LIB) $(LIBOBJS)

libs: $(LIB)

# ARM64 decompressor (Apple Silicon)
ARM64_OBJ := $(OBJDIR)/asm/ARM64/aplib_arm64.o

$(ARM64_OBJ): asm/ARM64/aplib_arm64.s
	@mkdir -p '$(@D)'
	as -arch arm64 $< -o $@

arm64: $(ARM64_OBJ)

clean:
	@rm -rf $(APP) $(OBJDIR)
	@rm -rf $(LIB)
