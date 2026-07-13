/*
 * sha3d — double NIST SHA3-256 (BSHA3 / Yilacoin)
 *
 * CPU reference hash and scanhash wrapper.
 * GPU kernel: cuda_sha3d.cu
 */

extern "C"
{
#include "sph/sph_sha3d.h"

#include "miner.h"
}

#include "cuda_helper.h"

extern void sha3d_cpu_init(int thr_id);
extern void sha3d_cpu_free(int thr_id);
extern void sha3d_cpu_hash_80(int thr_id, uint32_t threads, uint32_t startNonce, uint32_t* resNonces, const uint2 highTarget);
extern void sha3d_setBlock_80(uint64_t *endiandata);
extern void sha3d_setOutput(int thr_id);

// CPU Hash (authoritative re-verify of every GPU candidate)
extern "C" void sha3d_hash(void *state, const void *input)
{
	uint32_t _ALIGN(64) buffer[16], hash[16];
	sph_keccak_context ctx_keccak;

	sph_sha3d256_init(&ctx_keccak);
	sph_sha3d256 (&ctx_keccak, input, 80);
	sph_sha3d256_close(&ctx_keccak, (void*) buffer);
	sph_sha3d256_init(&ctx_keccak);
	sph_sha3d256 (&ctx_keccak, buffer, 32);
	sph_sha3d256_close(&ctx_keccak, (void*) hash);

	memcpy(state, hash, 32);
}

static bool init[MAX_GPUS] = { 0 };

extern "C" int scanhash_sha3d(int thr_id, struct work* work, uint32_t max_nonce, unsigned long *hashes_done)
{
	uint32_t _ALIGN(64) endiandata[20];
	uint32_t *pdata = work->data;
	uint32_t *ptarget = work->target;
	const uint32_t first_nonce = pdata[19];
	const int dev_id = device_map[thr_id];
	const uint32_t intensity = 23;
	uint32_t throughput = cuda_default_throughput(thr_id, 1U << intensity);
	if (init[thr_id]) throughput = min(throughput, max_nonce - first_nonce);

	if (opt_benchmark)
		ptarget[7] = 0x000f;

	if (!init[thr_id])
	{
		cudaSetDevice(dev_id);
		if (opt_cudaschedule == -1 && gpu_threads == 1) {
			cudaDeviceReset();
			// reduce cpu usage
			cudaSetDeviceFlags(cudaDeviceScheduleBlockingSync);
			CUDA_LOG_ERROR();
		}
		cuda_get_arch(thr_id);
		sha3d_cpu_init(thr_id);

		gpulog(LOG_INFO, thr_id, "Intensity set to %g, %u cuda threads", throughput2intensity(throughput), throughput);

		init[thr_id] = true;
	}

	for (int k=0; k < 19; k++) {
		be32enc(&endiandata[k], pdata[k]);
	}

	const uint2 highTarget = make_uint2(ptarget[6], ptarget[7]);
	sha3d_setBlock_80((uint64_t*)endiandata);
	sha3d_setOutput(thr_id);

	do {
		*hashes_done = pdata[19] - first_nonce + throughput;

		sha3d_cpu_hash_80(thr_id, throughput, pdata[19], work->nonces, highTarget);

		// Discard any result OUTSIDE the sub-range this launch actually scanned
		// [start, start+throughput). A value left in the device result buffer by
		// a previous launch (same job, earlier sub-range) would otherwise be
		// re-submitted and rejected by the pool as a duplicate ("nonce already
		// sent"). Half-open interval, wrap-aware.
		{
			const uint32_t start = pdata[19];
			const uint32_t span  = throughput; // launch scanned [start, start+span)
			for (int i = 0; i < 2; i++) {
				const uint32_t nn = work->nonces[i];
				if (nn == UINT32_MAX) continue;
				const uint32_t off = nn - start;   // wrap-aware distance from start
				if (off >= span)
					work->nonces[i] = UINT32_MAX;
			}
		}

		// defensive: never report the same nonce in both result slots (a
		// duplicate here would be submitted twice by the caller)
		if (work->nonces[1] == work->nonces[0])
			work->nonces[1] = UINT32_MAX;

		if (work->nonces[0] != UINT32_MAX && bench_algo < 0)
		{
			const uint32_t Htarg = ptarget[7];
			uint32_t _ALIGN(64) vhash[8];

			be32enc(&endiandata[19], work->nonces[0]);
			sha3d_hash(vhash, endiandata);

			if (vhash[7] <= Htarg && fulltest(vhash, ptarget)) {
				work->valid_nonces = 1;
				work_set_target_ratio(work, vhash);
				if (work->nonces[1] != UINT32_MAX) {
					be32enc(&endiandata[19], work->nonces[1]);
					sha3d_hash(vhash, endiandata);
					if (vhash[7] <= Htarg && fulltest(vhash, ptarget)) {
						work->valid_nonces++;
						bn_set_target_ratio(work, vhash, 1);
					}
					pdata[19] = max(work->nonces[0], work->nonces[1]) + 1;
				} else {
					pdata[19] = work->nonces[0] + 1;
				}
				return work->valid_nonces;
			}
			else if (vhash[7] > Htarg) {
				gpu_increment_reject(thr_id);
				if (!opt_quiet)
					gpulog(LOG_WARNING, thr_id, "result for %08x does not validate on CPU!", work->nonces[0]);
				pdata[19] = work->nonces[0] + 1;
				sha3d_setOutput(thr_id);
				continue;
			}
		}

		if ((uint64_t) throughput + pdata[19] >= max_nonce) {
			pdata[19] = max_nonce;
			break;
		}

		pdata[19] += throughput;

	} while (!work_restart[thr_id].restart);

	*hashes_done = pdata[19] - first_nonce;
	return 0;
}

// cleanup
extern "C" void free_sha3d(int thr_id)
{
	if (!init[thr_id])
		return;

	cudaDeviceSynchronize();

	sha3d_cpu_free(thr_id);

	cudaDeviceSynchronize();
	init[thr_id] = false;
}
