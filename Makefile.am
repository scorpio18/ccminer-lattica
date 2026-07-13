# allow to use Host cuda functions in C/C++
DEF_INCLUDES = @CUDA_INCLUDES@

if WANT_JANSSON
JANSSON_INCLUDES= -I$(top_srcdir)/compat/jansson
else
JANSSON_INCLUDES=
endif

EXTRA_DIST		= autogen.sh README.md README.txt LICENSE.txt \
			  ccminer.sln ccminer.vcxproj ccminer.vcxproj.filters \
			  compat/gettimeofday.c compat/getopt/getopt_long.c

SUBDIRS = compat

bin_PROGRAMS = ccminer

# --- Single-algo (Lattica sha3d) build: only the SHA3-256 / sha3d sources are
# compiled; every other algo's source is excluded. Dead switch branches still
# reference their scanhash_*, so ccminer_LDFLAGS uses
# -Wl,--unresolved-symbols=ignore-all (see below) + algo_stubs.cpp for DATA globals.
ccminer_SOURCES = elist.h miner.h compat.h \
			  compat/inttypes.h compat/stdbool.h compat/unistd.h \
			  compat/sys/time.h compat/getopt/getopt.h \
			  crc32.c \
			  ccminer.cpp solo_addr.cpp pools.cpp util.cpp bench.cpp bignum.cpp \
			  api.cpp hashlog.cpp nvml.cpp stats.cpp sysinfos.cpp cuda.cpp \
			  nvsettings.cpp \
			  algo_stubs.cpp \
			  algos/sha3d/sha3d.cu algos/sha3d/cuda_sha3d.cu \
			  algos/keccak/cuda_keccak_selftest.cu cuda/keccak_device.cuh \
			  cuda_checkhash.cu \
			  sph/sha3d.c sph/keccak.c

if HAVE_NVML
nvml_defs = -DUSE_WRAPNVML
nvml_libs = -ldl
endif

if HAVE_WINDOWS
ccminer_SOURCES += compat/winansi.c
endif

ccminer_LDFLAGS  = $(PTHREAD_FLAGS) @CUDA_LDFLAGS@
ccminer_LDFLAGS += -Wl,--unresolved-symbols=ignore-all # single-algo: dead algo branches
ccminer_LDADD    = @LIBCURL@ @JANSSON_LIBS@ @PTHREAD_LIBS@ @WS2_LIBS@ @CUDA_LIBS@ @OPENMP_CFLAGS@ @LIBS@ $(nvml_libs)
ccminer_CPPFLAGS = @LIBCURL_CPPFLAGS@ @OPENMP_CFLAGS@ $(CPPFLAGS) $(PTHREAD_FLAGS) -fno-strict-aliasing $(JANSSON_INCLUDES) $(DEF_INCLUDES) $(nvml_defs)

if HAVE_OSX
ccminer_CPPFLAGS += -I/usr/local/llvm/lib/clang/4.0.0/include
ccminer_LDFLAGS += -L/usr/local/llvm/lib
ccminer_LDADD += -lomp
endif

#ccminer_CPPFLAGS += -DUSE_LIBSODIUM
#ccminer_LDFLAGS += -Lequi/lib
#ccminer_LDADD += -lsodium
ccminer_LDADD += -lcuda

nvcc_ARCH :=
#nvcc_ARCH += -gencode=arch=compute_120,code=\"sm_120,compute_120\" # CUDA 12.8
#nvcc_ARCH += -gencode=arch=compute_101,code=\"sm_101,compute_101\"
#nvcc_ARCH += -gencode=arch=compute_100a,code=\"sm_100a,compute_100a\"
#nvcc_ARCH += -gencode=arch=compute_100,code=\"sm_100,compute_100\"
nvcc_ARCH += -gencode=arch=compute_86,code=\"sm_86,compute_86\"    # RTX 3000 (Ampere)
nvcc_ARCH += -gencode=arch=compute_89,code=\"sm_89,compute_89\"    # RTX 4000 (Ada)
nvcc_ARCH += -gencode=arch=compute_120,code=\"sm_120,compute_120\" # RTX 5000 (Blackwell)
#nvcc_ARCH += -gencode=arch=compute_70,code=\"sm_70,compute_70\" # CUDA 9.1
#nvcc_ARCH += -gencode=arch=compute_62,code=\"sm_62,compute_62\"
#nvcc_ARCH += -gencode=arch=compute_61,code=\"sm_61,compute_61\" # CUDA 8
#nvcc_ARCH += -gencode=arch=compute_60,code=\"sm_60,compute_60\"
#nvcc_ARCH += -gencode=arch=compute_52,code=\"sm_52,compute_52\"
#nvcc_ARCH += -gencode=arch=compute_50,code=\"sm_50,compute_50\"

nvcc_FLAGS = $(nvcc_ARCH) @CUDA_INCLUDES@ -I. @CUDA_CFLAGS@
nvcc_FLAGS += $(JANSSON_INCLUDES) --ptxas-options="-v" --std=c++17

# we're now targeting all major compute architectures within one binary.
.cu.o:
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=128 -o $@ -c $<

lyra2/cuda_lyra2.o: lyra2/cuda_lyra2.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=128 -o $@ -c $<

Algo256/blake256.o: Algo256/blake256.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=64 -o $@ -c $<

Algo256/cuda_bmw.o: Algo256/cuda_bmw.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=76 -o $@ -c $<

crypto/cryptonight-core.o: crypto/cryptonight-core.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=64 -o $@ -c $<

crypto/cryptonight-extra.o: crypto/cryptonight-extra.cu
	$(NVCC) $(nvcc_FLAGS) -o $@ -c $<

heavy/cuda_hefty1.o: heavy/cuda_hefty1.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

qubit/qubit_luffa512.o: qubit/qubit_luffa512.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

# Luffa and Echo are faster with 80 registers than 128
x11/cuda_x11_luffa512.o: x11/cuda_x11_luffa512.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

x11/cuda_x11_luffa512_Cubehash.o: x11/cuda_x11_luffa512_Cubehash.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=76 -o $@ -c $<

x11/cuda_x11_simd512.o: x11/cuda_x11_simd512.cu
	$(NVCC) $(nvcc_FLAGS) -Xcompiler -Wno-unused-variable -o $@ -c $<

x13/cuda_x13_hamsi512.o: x13/cuda_x13_hamsi512.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=72 -o $@ -c $<

x17/cuda_x17_sha512.o: x17/cuda_x17_sha512.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

quark/cuda_quark_blake512.o: quark/cuda_quark_blake512.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

quark/cuda_jh512.o: quark/cuda_jh512.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

quark/cuda_quark_keccak512.o: quark/cuda_quark_keccak512.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=88 -o $@ -c $<

quark/cuda_quark_compactionTest.o: quark/cuda_quark_compactionTest.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

JHA/cuda_jha_compactionTest.o: JHA/cuda_jha_compactionTest.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=80 -o $@ -c $<

# This object does not use cuda device code but call the different kernels (autotune)
scrypt/salsa_kernel.o: scrypt/salsa_kernel.cu
	$(NVCC) $(JANSSON_INCLUDES) -I. @CUDA_INCLUDES@ @CUDA_CFLAGS@ $(nvcc_ARCH) -o $@ -c $<

# These kernels are for older devices (SM)

scrypt/test_kernel.o: scrypt/test_kernel.cu
	$(NVCC) $(JANSSON_INCLUDES) -I. @CUDA_INCLUDES@ @CUDA_CFLAGS@ $(nvcc_ARCH) -o $@ -c $<

scrypt/fermi_kernel.o: scrypt/fermi_kernel.cu
	$(NVCC) $(JANSSON_INCLUDES) -I. @CUDA_INCLUDES@ @CUDA_CFLAGS@ $(nvcc_ARCH) -o $@ -c $<

scrypt/kepler_kernel.o: scrypt/kepler_kernel.cu
	$(NVCC) $(JANSSON_INCLUDES) -I. @CUDA_INCLUDES@ @CUDA_CFLAGS@ $(nvcc_ARCH) -o $@ -c $<

scrypt/nv_kernel.o: scrypt/nv_kernel.cu
	$(NVCC) $(JANSSON_INCLUDES) -I. @CUDA_INCLUDES@ @CUDA_CFLAGS@ $(nvcc_ARCH) -o $@ -c $<

scrypt/titan_kernel.o: scrypt/titan_kernel.cu
	$(NVCC) $(nvcc_FLAGS) $(nvcc_ARCH) -o $@ -c $<

skein.o: skein.cu
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=64 -o $@ -c $<

neoscrypt/cuda_neoscrypt.o: neoscrypt/cuda_neoscrypt.cu
	$(NVCC) $(JANSSON_INCLUDES) -I. @CUDA_INCLUDES@ @CUDA_CFLAGS@ $(nvcc_ARCH) -o $@ -c $<


