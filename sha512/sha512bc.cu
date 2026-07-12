/**
 * Basecoin / SHA-512 block header hash (Bitcoin-style 80-byte header).
 * PoW: first 256 bits of SHA512(header) vs target (matches basecoin HashWriter512).
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <openssl/sha.h>

#include <miner.h>
#include <cuda_helper.h>

#define TPB 512
#define NONCES_PER_THREAD 32

static uint32_t *d_resNonces[MAX_GPUS] = { 0 };
static bool init[MAX_GPUS] = { 0 };

static __constant__ uint64_t c_WB[80];
static __constant__ uchar c_hdr76[76];
static __constant__ uint64_t c_hdr64[9];
static __constant__ uint32_t c_ptarget[8];

static const uint64_t host_WB[80] = {
	0x428A2F98D728AE22, 0x7137449123EF65CD, 0xB5C0FBCFEC4D3B2F, 0xE9B5DBA58189DBBC,
	0x3956C25BF348B538, 0x59F111F1B605D019, 0x923F82A4AF194F9B, 0xAB1C5ED5DA6D8118,
	0xD807AA98A3030242, 0x12835B0145706FBE, 0x243185BE4EE4B28C, 0x550C7DC3D5FFB4E2,
	0x72BE5D74F27B896F, 0x80DEB1FE3B1696B1, 0x9BDC06A725C71235, 0xC19BF174CF692694,
	0xE49B69C19EF14AD2, 0xEFBE4786384F25E3, 0x0FC19DC68B8CD5B5, 0x240CA1CC77AC9C65,
	0x2DE92C6F592B0275, 0x4A7484AA6EA6E483, 0x5CB0A9DCBD41FBD4, 0x76F988DA831153B5,
	0x983E5152EE66DFAB, 0xA831C66D2DB43210, 0xB00327C898FB213F, 0xBF597FC7BEEF0EE4,
	0xC6E00BF33DA88FC2, 0xD5A79147930AA725, 0x06CA6351E003826F, 0x142929670A0E6E70,
	0x27B70A8546D22FFC, 0x2E1B21385C26C926, 0x4D2C6DFC5AC42AED, 0x53380D139D95B3DF,
	0x650A73548BAF63DE, 0x766A0ABB3C77B2A8, 0x81C2C92E47EDAEE6, 0x92722C851482353B,
	0xA2BFE8A14CF10364, 0xA81A664BBC423001, 0xC24B8B70D0F89791, 0xC76C51A30654BE30,
	0xD192E819D6EF5218, 0xD69906245565A910, 0xF40E35855771202A, 0x106AA07032BBD1B8,
	0x19A4C116B8D2D0C8, 0x1E376C085141AB53, 0x2748774CDF8EEB99, 0x34B0BCB5E19B48A8,
	0x391C0CB3C5C95A63, 0x4ED8AA4AE3418ACB, 0x5B9CCA4F7763E373, 0x682E6FF3D6B2B8A3,
	0x748F82EE5DEFB2FC, 0x78A5636F43172F60, 0x84C87814A1F0AB72, 0x8CC702081A6439EC,
	0x90BEFFFA23631E28, 0xA4506CEBDE82BDE9, 0xBEF9A3F7B2C67915, 0xC67178F2E372532B,
	0xCA273ECEEA26619C, 0xD186B8C721C0C207, 0xEADA7DD6CDE0EB1E, 0xF57D4F7FEE6ED178,
	0x06F067AA72176FBA, 0x0A637DC5A2C898A6, 0x113F9804BEF90DAE, 0x1B710B35131C471B,
	0x28DB77F523047D84, 0x32CAAB7B40C72493, 0x3C9EBE0A15C9BEBC, 0x431D67C49C100D4C,
	0x4CC5D4BECB3E42B6, 0x597F299CFC657E2A, 0x5FCB6FAB3AD6FAEC, 0x6C44198C4A475817
};


#define BSG5_0(x) xor3(ROTR64(x,28), ROTR64(x,34), ROTR64(x,39))
#define SSG5_0(x) xor3(ROTR64(x, 1), ROTR64(x ,8), shr_t64(x,7))
#define SSG5_1(x) xor3(ROTR64(x,19), ROTR64(x,61), shr_t64(x,6))
#define MAJ(x, y, z)   andor(x,y,z)

__device__ __forceinline__
uint64_t dbe64(const uchar *p)
{
	return ((uint64_t)p[0] << 56) | ((uint64_t)p[1] << 48) | ((uint64_t)p[2] << 40) |
	       ((uint64_t)p[3] << 32) | ((uint64_t)p[4] << 24) | ((uint64_t)p[5] << 16) |
	       ((uint64_t)p[6] << 8) | (uint64_t)p[7];
}

__device__ __forceinline__
uint64_t Tone_bc_at(uint64_t *K, uint64_t *r, uint64_t *W, const int a, const int t)
{
	const uint64_t e = r[(a + 4) & 7];
	uint64_t BSG51 = xor3(ROTR64(e, 14), ROTR64(e, 18), ROTR64(e, 41));
	const uint64_t f = r[(a + 5) & 7];
	const uint64_t g = r[(a + 6) & 7];
	uint64_t CHl = ((f ^ g) & e) ^ g;
	return (r[(a + 7) & 7] + BSG51 + CHl + K[t] + W[t & 15]);
}

#define SHA512_STEP_BC(K, r, W, ord, t) { \
	const int a = (8 - ord) & 7; \
	uint64_t T1 = Tone_bc_at(K, r, W, a, t); \
	r[(a+3) & 7] += T1; \
	uint64_t T2 = (BSG5_0(r[a]) + MAJ(r[a], r[(a+1) & 7], r[(a+2) & 7])); \
	r[(a+7) & 7] = T1 + T2; \
}

__device__ __forceinline__
bool fulltest_bc(const uint32_t *hash)
{
	for (int i = 7; i >= 0; i--) {
		if (hash[i] > c_ptarget[i])
			return false;
		if (hash[i] < c_ptarget[i])
			return true;
	}
	return true;
}

/* Map SHA-512 state words to uint32[8] for fulltest (same as le32dec of BE digest bytes). */
__device__ __forceinline__
void state_to_vhash(uint64_t H0, uint64_t H1, uint64_t H2, uint64_t H3, uint32_t *vh)
{
	vh[0] = cuda_swab32((uint32_t)(H0 >> 32));
	vh[1] = cuda_swab32((uint32_t)H0);
	vh[2] = cuda_swab32((uint32_t)(H1 >> 32));
	vh[3] = cuda_swab32((uint32_t)H1);
	vh[4] = cuda_swab32((uint32_t)(H2 >> 32));
	vh[5] = cuda_swab32((uint32_t)H2);
	vh[6] = cuda_swab32((uint32_t)(H3 >> 32));
	vh[7] = cuda_swab32((uint32_t)H3);
}

__global__ __launch_bounds__(TPB, 2)
void basecoin_sha512_gpu_hash(const uint32_t threads, const uint32_t startNonce, uint32_t *result)
{
	const uint32_t threadindex = (blockDim.x * blockIdx.x + threadIdx.x);
	if (threadindex >= threads)
		return;

	const uint32_t numberofthreads = blockDim.x * gridDim.x;
	const uint32_t maxnonce = startNonce + threadindex + numberofthreads * NONCES_PER_THREAD - 1;

	const uint64_t IV512[8] = {
		0x6A09E667F3BCC908, 0xBB67AE8584CAA73B,
		0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1,
		0x510E527FADE682D1, 0x9B05688C2B3E6C1F,
		0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179
	};

	for (uint32_t nonce = startNonce + threadindex; nonce - 1U < maxnonce; nonce += numberofthreads) {
		uint64_t W[16];
#pragma unroll
		for (int i = 0; i < 9; i++)
			W[i] = c_hdr64[i];
		W[9] = ((uint64_t)c_hdr76[72] << 56) | ((uint64_t)c_hdr76[73] << 48) |
		       ((uint64_t)c_hdr76[74] << 40) | ((uint64_t)c_hdr76[75] << 32) |
		       ((uint64_t)(nonce & 0xffU) << 24) | ((uint64_t)((nonce >> 8) & 0xffU) << 16) |
		       ((uint64_t)((nonce >> 16) & 0xffU) << 8) | (uint64_t)(nonce >> 24);
		W[10] = 0x8000000000000000ULL;
#pragma unroll
		for (int i = 11; i < 15; i++)
			W[i] = 0;
		W[15] = 0x280; /* 640 bits */

		uint64_t r[8];
#pragma unroll
		for (int i = 0; i < 8; i++)
			r[i] = IV512[i];

#pragma unroll
		for (int t = 0; t < 16; t++)
			SHA512_STEP_BC(c_WB, r, W, t & 7, t);
#pragma unroll
		for (int t = 16; t < 80; t++) {
			W[t & 15] = SSG5_1(W[(t - 2) & 15]) + W[(t - 7) & 15] +
				    SSG5_0(W[(t - 15) & 15]) + W[(t - 16) & 15];
			SHA512_STEP_BC(c_WB, r, W, t & 7, t);
		}

		const uint64_t H0 = r[0] + IV512[0];
		const uint64_t H1 = r[1] + IV512[1];
		const uint64_t H2 = r[2] + IV512[2];
		const uint64_t H3 = r[3] + IV512[3];

		uint32_t vh[8];
		state_to_vhash(H0, H1, H2, H3, vh);

		if (fulltest_bc(vh)) {
			uint32_t tmp = atomicCAS(result, 0xffffffffu, nonce);
			if (tmp != 0xffffffffu)
				result[1] = nonce;
		}
	}
}

__host__
static void basecoin_sha512_init_kernels(int thr_id)
{
	(void)thr_id;
	cudaMemcpyToSymbol(c_WB, host_WB, sizeof(host_WB), 0, cudaMemcpyHostToDevice);
}

__host__
void basecoin_sha512_set_header(const uint32_t *pdata)
{
	/* c_hdr76 is used for the tail part (nonce-dependent) bytes.
	 * c_hdr64 precomputes W[0..8] big-endian 64-bit words once per template refresh. */
	unsigned char const *b = (unsigned char const *)pdata;
	uint64_t hdr64[9];
	for (int i = 0; i < 9; i++) {
		hdr64[i] = ((uint64_t)b[i * 8 + 0] << 56) | ((uint64_t)b[i * 8 + 1] << 48) |
		           ((uint64_t)b[i * 8 + 2] << 40) | ((uint64_t)b[i * 8 + 3] << 32) |
		           ((uint64_t)b[i * 8 + 4] << 24) | ((uint64_t)b[i * 8 + 5] << 16) |
		           ((uint64_t)b[i * 8 + 6] << 8) | (uint64_t)b[i * 8 + 7];
	}
	cudaMemcpyToSymbol(c_hdr76, pdata, 76, 0, cudaMemcpyHostToDevice);
	cudaMemcpyToSymbol(c_hdr64, hdr64, sizeof(hdr64), 0, cudaMemcpyHostToDevice);
}

__host__
void basecoin_sha512_set_target(const uint32_t *ptarget)
{
	cudaMemcpyToSymbol(c_ptarget, ptarget, 8 * sizeof(uint32_t), 0, cudaMemcpyHostToDevice);
}

__host__
void basecoin_sha512_hash_launch(int thr_id, uint32_t threads, uint32_t startNonce, uint32_t *d_res)
{
	(void)thr_id;
	const uint32_t npt = NONCES_PER_THREAD;
	dim3 grid((threads + TPB * npt - 1) / (TPB * npt));
	dim3 block(TPB);
	basecoin_sha512_gpu_hash<<<grid, block>>>(threads, startNonce, d_res);
}

/* CPU reference: PoW is int.from_bytes(sha512[:32],'little') vs target; limbs
 * vhash[i]=le32dec(d+4*i) with vhash[7]=MSW (matches GBT target for basecoin). */
extern "C" void basecoin_header_hash(uint32_t *vhash, const void *header80)
{
	unsigned char d[64];
	SHA512_CTX ctx;
	SHA512_Init(&ctx);
	SHA512_Update(&ctx, (const unsigned char *)header80, 80);
	SHA512_Final(d, &ctx);
	for (int i = 0; i < 8; i++)
		vhash[i] = le32dec(d + 4 * i);
}

extern "C" int scanhash_basecoin(int thr_id, struct work *work, uint32_t max_nonce, unsigned long *hashes_done)
{
	uint32_t *pdata = work->data;
	uint32_t *ptarget = work->target;
	const uint32_t first_nonce = pdata[19];
	uint32_t throughput = cuda_default_throughput(thr_id, 1U << 25);
	if (init[thr_id])
		throughput = min(throughput, (max_nonce - first_nonce));

	if (opt_benchmark)
		((uint32_t *)ptarget)[7] = 0x03;

	if (!init[thr_id]) {
		cudaSetDevice(device_map[thr_id]);
		if (opt_cudaschedule == -1 && gpu_threads == 1) {
			cudaDeviceReset();
			cudaSetDeviceFlags(cudaDeviceScheduleBlockingSync);
			CUDA_LOG_ERROR();
		}
		gpulog(LOG_INFO, thr_id, "Intensity set to %g, %u cuda threads", throughput2intensity(throughput), throughput);

		cuda_get_arch(thr_id);
		basecoin_sha512_init_kernels(thr_id);
		CUDA_SAFE_CALL(cudaMalloc(&d_resNonces[thr_id], 2 * sizeof(uint32_t)));
		init[thr_id] = true;
	}

	basecoin_sha512_set_header(pdata);
	basecoin_sha512_set_target(ptarget);

	do {
		*hashes_done = pdata[19] - first_nonce + throughput;

		CUDA_SAFE_CALL(cudaMemset(d_resNonces[thr_id], 0xff, 2 * sizeof(uint32_t)));
		cudaDeviceSynchronize();
		basecoin_sha512_hash_launch(thr_id, throughput, pdata[19], d_resNonces[thr_id]);
		cudaDeviceSynchronize();
		CUDA_SAFE_CALL(cudaMemcpy(work->nonces, d_resNonces[thr_id], 2 * sizeof(uint32_t), cudaMemcpyDeviceToHost));
		if (work->nonces[0] == work->nonces[1])
			work->nonces[1] = UINT32_MAX;

		if (work->nonces[0] != UINT32_MAX) {
			uint32_t _ALIGN(64) vhash[8];
			uint32_t hdr[20];
			memcpy(hdr, pdata, 80);
			hdr[19] = work->nonces[0];
			basecoin_header_hash(vhash, hdr);
			if (vhash[7] <= ptarget[7] && fulltest(vhash, ptarget)) {
				work->valid_nonces = 1;
				work_set_target_ratio(work, vhash);
				if (work->nonces[1] != UINT32_MAX) {
					hdr[19] = work->nonces[1];
					basecoin_header_hash(vhash, hdr);
					if (vhash[7] <= ptarget[7] && fulltest(vhash, ptarget)) {
						work->valid_nonces++;
						bn_set_target_ratio(work, vhash, 1);
					}
					pdata[19] = max(work->nonces[0], work->nonces[1]) + 1;
				} else {
					pdata[19] = work->nonces[0] + 1;
				}
				return work->valid_nonces;
			}
			gpu_increment_reject(thr_id);
			if (!opt_quiet)
				gpulog(LOG_WARNING, thr_id, "result for %08x does not validate on CPU!", work->nonces[0]);
			pdata[19] = work->nonces[0] + 1;
			continue;
		}

		if ((uint64_t)throughput + pdata[19] >= max_nonce) {
			pdata[19] = max_nonce;
			break;
		}
		pdata[19] += throughput;

	} while (!work_restart[thr_id].restart);

	*hashes_done = pdata[19] - first_nonce;
	return 0;
}

extern "C" void free_basecoin(int thr_id)
{
	if (!init[thr_id])
		return;
	cudaDeviceSynchronize();
	if (d_resNonces[thr_id])
		cudaFree(d_resNonces[thr_id]);
	d_resNonces[thr_id] = NULL;
	init[thr_id] = false;
	cudaDeviceSynchronize();
}
