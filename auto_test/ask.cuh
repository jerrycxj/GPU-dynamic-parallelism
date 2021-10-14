#pragma once

#include "complex.cuh"
#include "macros.cuh"
#include "mandelbrotHelper.cuh"

__global__ void ASK(unsigned int *d_ns, int *d_offs1, int *d_offs2, int *dwells,
                    int w, int h, complex cmin, complex cmax, int d, int depth,
                    unsigned int SUBDIV, unsigned int MAX_DWELL,
                    unsigned int MIN_SIZE, unsigned int MAX_DEPTH,
                    unsigned int SUBDIV_ELEMS, unsigned int SUBDIV_ELEMS2,
                    unsigned int SUBDIV_ELEMSP, unsigned int SUBDIV_ELEMSX) {
    // check whether all boundary pixels have the same dwell
    unsigned int use =
        blockIdx.x * SUBDIV_ELEMS2 + (blockIdx.z * gridDim.y + blockIdx.y) * 2;

    const unsigned int x0 = d_offs1[use];
    const unsigned int y0 = d_offs1[use + 1];

    __shared__ unsigned int off_index;

    // --------------
    // -- EXPLORACION
    // --------------
    int tid = threadIdx.y * blockDim.x + threadIdx.x;
    int bs = blockDim.x * blockDim.y;
    int comm_dwell = NEUT_DWELL;
    // for all boundary pixels, distributed across threads
    for (int r = tid; r < d; r += bs) {
        // for each boundary: b = 0 is east, then counter-clockwise
        for (int b = 0; b < 4; b++) {
            unsigned int x = b % 2 != 0 ? x0 + r : (b == 0 ? x0 + d - 1 : x0);
            unsigned int y = b % 2 == 0 ? y0 + r : (b == 1 ? y0 + d - 1 : y0);
            int dwell = pixel_dwell(w, h, cmin, cmax, x, y, MAX_DWELL);
            comm_dwell = same_dwell(comm_dwell, dwell, MAX_DWELL);
        }
    } // for all boundary pixels
    // reduce across threads in the block
    __shared__ int ldwells[BSX * BSY];
    int nt = min(d, BSX * BSY);
    if (tid < nt)
        ldwells[tid] = comm_dwell;
    __syncthreads();
    for (; nt > 1; nt /= 2) {
        if (tid < nt / 2)
            ldwells[tid] =
                same_dwell(ldwells[tid], ldwells[tid + nt / 2], MAX_DWELL);
        __syncthreads();
    }
    comm_dwell = ldwells[0];

    __syncthreads();
    // ----------------------
    // SUBDIVISION
    // ----------------------
    //printf("%i - %i - %i - %i, %i\n", comm_dwell, depth, MAX_DEPTH, d, MIN_SIZE);
    if (comm_dwell != DIFF_DWELL) {
        // RELLENAR (T)
        unsigned int x = threadIdx.x;
        unsigned int y = threadIdx.y;
        for (unsigned int ry = y; ry < d; ry += blockDim.y) {
            for (unsigned int rx = x; rx < d; rx += blockDim.x) {
                if (rx < d && ry < d) {
                    unsigned int rxx = rx + x0, ryy = ry + y0;
                    dwells[ryy * (size_t)w + rxx] = comm_dwell;
                }
            }
        }
    } else if (depth + 1 < MAX_DEPTH && d / SUBDIV > MIN_SIZE) {
        // SUBDIVIDIR
        //printf("asd\n");
        if (tid == 0) {
            off_index = atomicAdd(d_ns, 1);
        }
        __syncthreads();
        if (tid < SUBDIV_ELEMS2) {
            d_offs2[(off_index * SUBDIV_ELEMS2) + tid] =
                (x0 + ((tid >> 1) & SUBDIV_ELEMSX) * (d / SUBDIV)) *
                    ((tid + 1) & 1) +
                (y0 + (tid >> SUBDIV_ELEMSP) * (d / SUBDIV)) * (tid & 1);
        }
    } else {
        // FUERZA BRUTA
        // return;
        unsigned int x = threadIdx.x;
        unsigned int y = threadIdx.y;
        for (unsigned int ry = y; ry < d; ry += blockDim.y) {
            for (unsigned int rx = x; rx < d; rx += blockDim.x) {
                if (rx < d && ry < d) {
                    unsigned int rxx = rx + x0, ryy = ry + y0;
                    dwells[ryy * (size_t)w + rxx] = pixel_dwell(w, h, cmin, cmax, rxx, ryy, MAX_DWELL);
                }
            }
        }
    }
}

void AdaptiveSerialKernels(int *dwell, unsigned int *h_nextSize,
                           unsigned int *d_nextSize, int *d_offsets1,
                           int *d_offsets2, int w, int h, complex cmin, complex cmax,
                           int d, int depth, unsigned int INIT_SUBDIV,
                           unsigned int SUBDIV, unsigned int MAX_DWELL,
                           unsigned int MIN_SIZE, unsigned int MAX_DEPTH) {

    dim3 b(BSX, BSY, 1), g(1, INIT_SUBDIV, INIT_SUBDIV);
    // printf("Running kernel with b(%i,%i) and g(%i, %i, %i) and d=%i\n", b.x,
    // b.y, g.x, g.y, g.z, d);

    // INDICAR AL VISUALIZAR QUE PUNTERO --> dwell
    // mapear - conectar el puntero memoria GPU con el de VULKAN/OPENGL
    // abrir ventana

    unsigned int SUBDIV_ELEMS = SUBDIV * SUBDIV;
    unsigned int SUBDIV_ELEMS2 = SUBDIV_ELEMS * 2;
    unsigned int SUBDIV_ELEMSP = log2(SUBDIV) + 1;
    unsigned int SUBDIV_ELEMSX = SUBDIV - 1;
    //printf("Running kernel with b(%i,%i) and g(%i, %i, %i) and d=%i\n",
    //b.x, b.y, g.x, g.y, g.z, d);
    #ifdef VERBOSE
        float time;
        int lastDepth = 0;
        cudaEvent_t start, stop;
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
        cudaEventRecord(start, 0);
    #endif
    ASK<<<g, b>>>(d_nextSize, d_offsets1, d_offsets2, dwell, h, w, cmin, cmax, d,
                  depth, SUBDIV, MAX_DWELL, MIN_SIZE, MAX_DEPTH, SUBDIV_ELEMS,
                  SUBDIV_ELEMS2, SUBDIV_ELEMSP, SUBDIV_ELEMSX);
    cucheck(cudaDeviceSynchronize());
    //printf("%i\n", d);
    for (int i = depth + 1; i < MAX_DEPTH && d / SUBDIV > MIN_SIZE; i++) {
        cudaMemcpy(h_nextSize, d_nextSize, sizeof(int), cudaMemcpyDeviceToHost);
        std::swap(d_offsets1, d_offsets2);

        cudaFree(d_offsets2);
        (cudaMalloc((void **)&d_offsets2, *h_nextSize * SUBDIV * SUBDIV * SUBDIV * SUBDIV * sizeof(int) * 2));
        (cudaMemset(d_nextSize, 0, sizeof(int)));
        d = d / SUBDIV;
        cucheck(cudaDeviceSynchronize());

        #ifdef VERBOSE
            cudaEventRecord(stop, 0);
            cudaEventSynchronize(stop);
            cudaEventElapsedTime(&time, start, stop); // that's our time!
            printf("[level %2i] %f secs -->  P_{%2i} = %f   (grid %8i x %i x %i = %8i --> %i subdivided)\n", i-1, time/1000.0f, i-1, *h_nextSize/(float)(g.x*g.y*g.z), g.x, g.y, g.z, g.x*g.y*g.z, *h_nextSize);
            cudaEventRecord(start, 0);
            lastDepth=i;
        #endif
        g = dim3(*h_nextSize, SUBDIV, SUBDIV);
         //printf("Running kernel with b(%i,%i) and g(%i, %i, %i) and d=%i\n",
         //b.x, b.y, g.x, g.y, g.z, d);
        ASK<<<g, b>>>(d_nextSize, d_offsets1, d_offsets2, dwell, h, w, cmin, cmax, d,
                      i, SUBDIV, MAX_DWELL, MIN_SIZE, MAX_DEPTH, SUBDIV_ELEMS,
                      SUBDIV_ELEMS2, SUBDIV_ELEMSP, SUBDIV_ELEMSX);
        // DIBUJAR LO QUE ESTA EN EL PUNTERO DE MEMORIA 

    }
    #ifdef VERBOSE
        cudaMemcpy(h_nextSize, d_nextSize, sizeof(int), cudaMemcpyDeviceToHost);
        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&time, start, stop); // that's our time!
        printf("<level %2i> %f secs -->  P_{%2i} = %f   (grid %8i x %i x %i = %8i --> %i subdivided)\n", lastDepth, time/1000.0f, lastDepth, *h_nextSize/(float)(g.x*g.y*g.z), g.x, g.y, g.z, g.x*g.y*g.z, *h_nextSize);
    #endif
}
