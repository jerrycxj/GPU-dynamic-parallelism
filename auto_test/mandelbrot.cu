#include <assert.h>
#include <png.h>
#include <omp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <algorithm>    // std::swap


/** CUDA check macro */
#define cucheck(call) \
	{\
	cudaError_t res = (call);\
	if(res != cudaSuccess) {\
	const char* err_str = cudaGetErrorString(res);\
	fprintf(stderr, "%s (%d): %s in %s", __FILE__, __LINE__, err_str, #call);	\
	exit(-1);\
	}\
	}

#define cucheck_dev(call) \
	{\
	cudaError_t res = (call);\
	if(res != cudaSuccess) {\
	const char* err_str = cudaGetErrorString(res);\
	printf("%s (%d): %s in %s", __FILE__, __LINE__, err_str, #call);	\
	assert(0);																												\
	}\
	}


/** a useful function to compute the number of threads */
__host__ __device__ int divup(int x, int y) { return x / y + (x % y ? 1 : 0); }

/** gets the color, given the dwell */
void dwell_color(int *r, int *g, int *b, int dwell);

/** save the dwell into a PNG file 
		@remarks: code to save PNG file taken from here 
		  (error handling is removed):
		http://www.labbookpages.co.uk/software/imgProc/libPNG.html
 */
void save_image(const char *filename, int *dwells, int w, int h) {
	png_bytep row;
	
	FILE *fp = fopen(filename, "wb");
	png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, 0, 0, 0);
	png_infop info_ptr = png_create_info_struct(png_ptr);
	// exception handling
	setjmp(png_jmpbuf(png_ptr));
	png_init_io(png_ptr, fp);
	// write header (8 bit colour depth)
	png_set_IHDR(png_ptr, info_ptr, w, h,
							 8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
							 PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);
	// set title
	png_text title_text;
	title_text.compression = PNG_TEXT_COMPRESSION_NONE;
	title_text.key = "Title";
	title_text.text = "Mandelbrot set, per-pixel";
	png_set_text(png_ptr, info_ptr, &title_text, 1);
	png_write_info(png_ptr, info_ptr);

	// write image data
	row = (png_bytep) malloc(3 * w * sizeof(png_byte));
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			int r, g, b;
			dwell_color(&r, &g, &b, dwells[y * w + x]);
			row[3 * x + 0] = (png_byte)r;
			row[3 * x + 1] = (png_byte)g;
			row[3 * x + 2] = (png_byte)b;
		}
		png_write_row(png_ptr, row);
	}
	png_write_end(png_ptr, NULL);

  fclose(fp);
  png_free_data(png_ptr, info_ptr, PNG_FREE_ALL, -1);
  png_destroy_write_struct(&png_ptr, (png_infopp)NULL);
  free(row);
}  // save_image


/** a simple complex type */
struct complex {
	__host__ __device__ complex(float re, float im = 0) {
		this->re = re;
		this->im = im;
	}
	/** real and imaginary part */
	float re, im;
}; // struct complex

// operator overloads for complex numbers
inline __host__ __device__ complex operator+
(const complex &a, const complex &b) {
	return complex(a.re + b.re, a.im + b.im);
}
inline __host__ __device__ complex operator-
(const complex &a) { return complex(-a.re, -a.im); }
inline __host__ __device__ complex operator-
(const complex &a, const complex &b) {
	return complex(a.re - b.re, a.im - b.im);
}
inline __host__ __device__ complex operator*
(const complex &a, const complex &b) {
	return complex(a.re * b.re - a.im * b.im, a.im * b.re + a.re * b.im);
}
inline __host__ __device__ float abs2(const complex &a) {
	return a.re * a.re + a.im * a.im;
}
inline __host__ __device__ complex operator/
(const complex &a, const complex &b) {
	float invabs2 = 1 / abs2(b);
	return complex((a.re * b.re + a.im * b.im) * invabs2,
								 (a.im * b.re - b.im * a.re) * invabs2);
}  // operator/

#ifndef MAX_DWELL
#define MAX_DWELL 512
#endif
/** block size along */
#ifndef BSX
#define BSX 16
#endif

#ifndef BSY
#define BSY 16
#endif
/** maximum recursion depth */
#ifndef MAX_DEPTH
#define MAX_DEPTH 5
#endif
/** region below which do per-pixel */
#define MIN_SIZE 4
/** subdivision factor along each axis */

#ifndef SUBDIV
#define SUBDIV 2
#endif

#ifndef SUBDIV_ELEMSX
#define SUBDIV_ELEMSX 1 //Potencia de 2 mas cercana a subdiv, restado en 1.
#endif

#ifndef SUBDIV_ELEMSP 
#define SUBDIV_ELEMSP 2 // Exponente de la potencia de 2 inmediatamente mayor que subdiv
#endif

#ifndef SUBDIV_ELEMS
#define SUBDIV_ELEMS 64//SUBDIV^2
#endif

#ifndef SUBDIV_ELEMS2
#define SUBDIV_ELEMS2 128 //SUBDIV^2
#endif
/** subdivision when launched from host */
#define INIT_SUBDIV 8

/** find the dwell for the pixel */
__device__ int pixel_dwell(int w, int h, complex cmin, complex cmax, int x, int y) {
	complex dc = cmax - cmin;
	float fx = (float)x / w, fy = (float)y / h;
	complex c = cmin + complex(fx * dc.re, fy * dc.im);
	int dwell = 0;
	complex z = c;
	while(dwell < MAX_DWELL && abs2(z) < 2 * 2) {
		z = z * z + c;
		dwell++;
	}
	return dwell;
}  // pixel_dwell

/** binary operation for common dwell "reduction": MAX_DWELL + 1 = neutral
		element, -1 = dwells are different */
#define NEUT_DWELL (MAX_DWELL + 1)
#define DIFF_DWELL (-1)
__device__ int same_dwell(int d1, int d2) {
	if(d1 == d2)
		return d1;
	else if(d1 == NEUT_DWELL || d2 == NEUT_DWELL)
		return min(d1, d2);
	else
		return DIFF_DWELL;
}  // same_dwell

/** evaluates the common border dwell, if it exists */
__device__ int border_dwell
(int* dwells, int w, int h, complex cmin, complex cmax, int x0, int y0, int d) {
	// check whether all boundary pixels have the same dwell
	int tid = threadIdx.y * blockDim.x + threadIdx.x;
	int bs = blockDim.x * blockDim.y;
	int comm_dwell = NEUT_DWELL;
	// for all boundary pixels, distributed across threads
	for(int r = tid; r < d; r += bs) {
		// for each boundary: b = 0 is east, then counter-clockwise
		for(int b = 0; b < 4; b++) {
			int x = b % 2 != 0 ? x0 + r : (b == 0 ? x0 + d - 1 : x0);
			int y = b % 2 == 0 ? y0 + r : (b == 1 ? y0 + d - 1 : y0);
			int dwell = pixel_dwell(w, h, cmin, cmax, x, y);
			comm_dwell = same_dwell(comm_dwell, dwell);
            //dwells[y * w + x] = 666;//pixel_dwell(w, h, cmin, cmax, x, y);
		}
	}  // for all boundary pixels
	// reduce across threads in the block
	__shared__ int ldwells[BSX * BSY];
	int nt = min(d, BSX * BSY);
	if(tid < nt)
		ldwells[tid] = comm_dwell;
	__syncthreads();
	for(; nt > 1; nt /= 2) {
		if(tid < nt / 2)
			ldwells[tid] = same_dwell(ldwells[tid], ldwells[tid + nt / 2]);
		__syncthreads();
	}
	return ldwells[0];
}  // border_dwell

/** the kernel to fill the image region with a specific dwell value */
__global__ void dwell_fill_k
(int *dwells, int w, int x0, int y0, int d, int dwell) {
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	if(x < d && y < d) {
		x += x0, y += y0; 
        //if (dwells[y * w + x] != 666)
		dwells[y * w + x] = dwell;
	}
}  // dwell_fill_k

/** the kernel to fill in per-pixel values of the portion of the Mandelbrot set
		*/
__global__ void mandelbrot_pixel_k
(int *dwells, int w, int h, complex cmin, complex cmax, int x0, int y0, int d) {
	int x = threadIdx.x + blockDim.x * blockIdx.x;
	int y = threadIdx.y + blockDim.y * blockIdx.y;
	if(x < d && y < d) {
		x += x0, y += y0;
        //if (dwells[y * w + x] != 666)
		dwells[y * w + x] = pixel_dwell(w, h, cmin, cmax, x, y);
	}
}  // mandelbrot_pixel_k

/** checking for an error */
__device__ void check_error(int x0, int y0, int d) {
	int err = cudaGetLastError();
	if(err != cudaSuccess) {
		printf("error launching kernel for region (%d..%d, %d..%d)\n", 
					 x0, x0 + d, y0, y0 + d);
		assert(0);
	}
}

__global__ void border_dwell2
(unsigned int* d_ns, int* d_offs1, int* d_offs2, int* dwells, int w, int h, complex cmin, complex cmax, int d, int depth, int subdiv) {
	// check whether all boundary pixels have the same dwell
    unsigned int use = blockIdx.x*SUBDIV_ELEMS2 + (blockIdx.z*gridDim.y+blockIdx.y)*2;

    const unsigned int x0 = d_offs1[use];
    const unsigned int y0 = d_offs1[use + 1];
    
    __shared__ unsigned int off_index;

	int tid = threadIdx.y * blockDim.x + threadIdx.x;
    //if (threadIdx.x > d || threadIdx.y > d){return;}
    //if (tid == 0){
    //    printf("x0y0 %i, %i\n", x0, y0);
    //}
	int bs = blockDim.x * blockDim.y;
	int comm_dwell = NEUT_DWELL;
	// for all boundary pixels, distributed across threads
	for(int r = tid; r < d; r += bs) {
		// for each boundary: b = 0 is east, then counter-clockwise
		for(int b = 0; b < 4; b++) {
			int x = b % 2 != 0 ? x0 + r : (b == 0 ? x0 + d - 1 : x0);
			int y = b % 2 == 0 ? y0 + r : (b == 1 ? y0 + d - 1 : y0);
			int dwell = pixel_dwell(w, h, cmin, cmax, x, y);
			comm_dwell = same_dwell(comm_dwell, dwell);
            //dwells[y * w + x] = 666;//pixel_dwell(w, h, cmin, cmax, x, y);
		}
	}  // for all boundary pixels
	// reduce across threads in the block
	__shared__ int ldwells[BSX * BSY];
	int nt = min(d, BSX * BSY);
	if(tid < nt)
		ldwells[tid] = comm_dwell;
	__syncthreads();
	for(; nt > 1; nt /= 2) {
		if(tid < nt / 2)
			ldwells[tid] = same_dwell(ldwells[tid], ldwells[tid + nt / 2]);
		__syncthreads();
	}
    comm_dwell = ldwells[0];

	__syncthreads();
    if(comm_dwell != DIFF_DWELL) {
        //return;
        
        int x = threadIdx.x;
        int y = threadIdx.y;
        for (int ry=y; ry < d; ry+=blockDim.y){
            for (int rx=x; rx < d; rx+=blockDim.x){
                if(rx < d && ry < d) {
                    int rxx = rx+x0, ryy = ry+y0;
                    //if (dwells[ryy * w + rxx] != 666)
                    dwells[ryy * w + rxx] = comm_dwell;
                }

            }
        }
    } else if(depth + 1 < MAX_DEPTH && d/SUBDIV > MIN_SIZE) {
        if (tid == 0){
            off_index = atomicAdd(d_ns, 1);
        }
        __syncthreads();
        if (tid < SUBDIV_ELEMS2){
                d_offs2[(off_index*SUBDIV_ELEMS2)+tid] = (x0
                        + ((tid>>1)&SUBDIV_ELEMSX)*(d/SUBDIV))*((tid+1)&1)
                    + (y0 + (tid>>SUBDIV_ELEMSP)*(d/SUBDIV))*(tid&1);
        }
    } else {
        //return;
        int x = threadIdx.x ;
        int y = threadIdx.y ;
        for (int ry=y; ry < d; ry+=blockDim.y){
            for (int rx=x; rx < d; rx+=blockDim.x){
                if(rx < d && ry < d) {
                    int rxx = rx+x0, ryy = ry+y0;
                    //if (dwells[ryy * w + rxx] != 666)
                    dwells[ryy * w + rxx] = pixel_dwell(w, h, cmin, cmax, rxx, ryy);
                }

            }
        }
    }
    //cucheck_dev(cudaGetLastError());

}  // border_dwell

void mandelbrot_pseudo_dynamic_parallelism(int *dwell, unsigned int* h_nextSize, unsigned int* d_nextSize, int* d_offsets1, int* d_offsets2, int w, int h, complex cmin, complex cmax, int d, int depth){
    
	dim3 b(BSX, BSY, 1), g(1, INIT_SUBDIV, INIT_SUBDIV);
    //printf("Running kernel with b(%i,%i) and g(%i, %i, %i) and d=%i\n", b.x, b.y, g.x, g.y, g.z, d);
    border_dwell2<<<g, b>>>(d_nextSize, d_offsets1, d_offsets2, dwell, h, w, cmin, cmax, d, depth, INIT_SUBDIV);
    for (int i=depth+1; i<MAX_DEPTH && d/SUBDIV>MIN_SIZE; i++){
        cudaDeviceSynchronize();
        cudaMemcpy(h_nextSize, d_nextSize, sizeof(int), cudaMemcpyDeviceToHost);
        cudaMemset(d_nextSize, 0, sizeof(int));
        std::swap(d_offsets1, d_offsets2);
        d = d/SUBDIV;
        dim3 g(*h_nextSize, SUBDIV, SUBDIV);
        //printf("Running kernel with b(%i,%i) and g(%i, %i, %i) and d=%i\n", b.x, b.y, g.x, g.y, g.z, d);
        border_dwell2<<<g, b>>>(d_nextSize, d_offsets1, d_offsets2, dwell, h, w, cmin, cmax, d, i, SUBDIV);
    }


}

/** gets the color, given the dwell (on host) */
#define CUT_DWELL (MAX_DWELL / 4)
void dwell_color(int *r, int *g, int *b, int dwell) {
	// black for the Mandelbrot set
    if (dwell == 666){
		*r = 255; 
        *g = *b = 0;
    } else if(dwell >= MAX_DWELL) {
		*r = *g = *b = 0;
	} else {
		// cut at zero
		if(dwell < 0)
			dwell = 0;
		if(dwell <= CUT_DWELL) {
			// from black to blue the first half
			*r = *g = 0;
			*b = 128 + dwell * 127 / (CUT_DWELL);
		} else {
			// from blue to white for the second half
			*b = 255;
			*r = *g = (dwell - CUT_DWELL) * 255 / (MAX_DWELL - CUT_DWELL);
		}
	}
}  // dwell_color

__global__ void mandelbrot_k
(int *dwells, int w, int h, complex cmin, complex cmax) {
	// complex value to start iteration (c)
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int dwell = pixel_dwell(w, h, cmin, cmax, x, y);
	dwells[y * w + x] = dwell;
}  // mandelbrot_k



__global__ void mandelbrot_block_k
(int *dwells, int w, int h, complex cmin, complex cmax, int x0, int y0, 
 int d, int depth) {
	x0 += d * blockIdx.x, y0 += d * blockIdx.y;
	int comm_dwell = border_dwell(dwells, w, h, cmin, cmax, x0, y0, d);
	if(threadIdx.x == 0 && threadIdx.y == 0) {
		if(comm_dwell != DIFF_DWELL) {
			// uniform dwell, just fill
			dim3 bs(BSX, BSY), grid(divup(d, BSX), divup(d, BSY));
			dwell_fill_k<<<grid, bs>>>(dwells, w, x0, y0, d, comm_dwell);
		} else if(depth + 1 < MAX_DEPTH && d / SUBDIV > MIN_SIZE) {
			// subdivide recursively
			dim3 bs(blockDim.x, blockDim.y), grid(SUBDIV, SUBDIV);
			mandelbrot_block_k<<<grid, bs>>>
				(dwells, w, h, cmin, cmax, x0, y0, d / SUBDIV, depth	+ 1);
		} else {
			// leaf, per-pixel kernel
			dim3 bs(BSX, BSY), grid(divup(d, BSX), divup(d, BSY));
			mandelbrot_pixel_k<<<grid, bs>>>
				(dwells, w, h, cmin, cmax, x0, y0, d);
		}
		//cucheck_dev(cudaGetLastError());
		//check_error(x0, y0, d);
	}
}  // mandelbrot_block_k

int checkArray(int* a, int* b, int w, int h){
    int cont = 0;
    for (int i=0; i<w*h; i++){
        if (a[i] != b[i]){
            //printf("%i, %i\n", i%h, i/h);
            cont++;
        }
    }
    return cont;
}
/** data size */
#ifndef H
#define H (32 * 1024)
#endif 

#ifndef W
#define W (32 * 1024)
#endif

#define IMAGE_PATH "./mandelbrot.png"
#define REPEATS 10

int main(int argc, char **argv) {
	// allocate memory
	int w = W, h = H;
	size_t dwell_sz = w * h * sizeof(int);
    double ti, tf, t1=0, t2=0, t3=0;

	int *h_dwells1;
	int *h_dwells2;
	int *h_dwells3;
	int *d_dwells;

	cucheck(cudaMalloc((void**)&d_dwells, dwell_sz));

	h_dwells1 = (int*)malloc(dwell_sz);
	h_dwells2 = (int*)malloc(dwell_sz);
	h_dwells3 = (int*)malloc(dwell_sz);

    unsigned int *h_nextSize;
    int *h_offsets;
    unsigned int *d_nextSize;
    int *d_offsets1;
    int *d_offsets2;

    unsigned int max_elements = 2*(INIT_SUBDIV*INIT_SUBDIV)*pow(SUBDIV*SUBDIV,
            MAX_DEPTH-1)/3;
    printf("%u\n",max_elements);

    h_nextSize = (unsigned int*)malloc(sizeof(int));
	h_offsets
        = (int*)malloc(sizeof(int)*max_elements);
    for (int i=0; i<INIT_SUBDIV*INIT_SUBDIV*2; i+=2){
        h_offsets[i] = ((i/2)%INIT_SUBDIV)*(W/INIT_SUBDIV);
        h_offsets[i+1] = ((i/2)/INIT_SUBDIV)*(W/INIT_SUBDIV);

        //printf("Offsets Iniciales: (%i) - %i, %i\n", i/2, h_offsets[i], h_offsets[i+1]);
    }
    *h_nextSize = INIT_SUBDIV*INIT_SUBDIV;
	cucheck(cudaMalloc((void**)&d_nextSize, sizeof(int)));

	cucheck(cudaMalloc((void**)&d_offsets1, sizeof(int)*max_elements));
	cucheck(cudaMalloc((void**)&d_offsets2, sizeof(int)*max_elements));

    cucheck(cudaMemcpy(d_offsets1, h_offsets, sizeof(int)*max_elements, cudaMemcpyHostToDevice))
    cucheck(cudaMemset(d_nextSize, 0, sizeof(int)));
	// compute the dwells, copy them back


    dim3 bs(BSX, BSY), grid(divup(w, bs.x), divup(h, bs.y));

    // COMMON
    for (int i=0; i< REPEATS; i++){
        ti = omp_get_wtime();
        mandelbrot_k<<<grid, bs>>>
            (d_dwells, w, h, complex(-1.5, -1), complex(0.5, 1));
        cudaDeviceSynchronize();
        tf = omp_get_wtime();
        t1 += tf - ti;
    }
    t1 /= REPEATS;

	cucheck(cudaMemcpy(h_dwells1, d_dwells, dwell_sz, cudaMemcpyDeviceToHost));
    cudaMemset(d_dwells, 0, dwell_sz);
    
    // 1 KERNEL
    for (int i=0; i< REPEATS; i++){
        
        for (int i=0; i<INIT_SUBDIV*INIT_SUBDIV*2; i+=2){
            h_offsets[i] = ((i/2)%INIT_SUBDIV)*(W/INIT_SUBDIV);
            h_offsets[i+1] = ((i/2)/INIT_SUBDIV)*(W/INIT_SUBDIV);

            //printf("Offsets Iniciales: (%i) - %i, %i\n", i/2, h_offsets[i], h_offsets[i+1]);
        }
        *h_nextSize = 1;
        cucheck(cudaMemcpy(d_offsets1, h_offsets, sizeof(int)*max_elements, cudaMemcpyHostToDevice))
        cucheck(cudaMemset(d_nextSize, 0, sizeof(int)));


        ti = omp_get_wtime();
        mandelbrot_pseudo_dynamic_parallelism(d_dwells, h_nextSize, d_nextSize, d_offsets1, d_offsets2, w, h, complex(-1.5, -1), complex(0.5, 1), W / INIT_SUBDIV, 1);
        (cudaDeviceSynchronize());
        tf = omp_get_wtime();
        t2 += tf - ti;
    }
    t2 /= REPEATS;

	cucheck(cudaMemcpy(h_dwells2, d_dwells, dwell_sz, cudaMemcpyDeviceToHost));
    cudaMemset(d_dwells, 0, dwell_sz);
	
    bs = dim3(BSX, BSY); 
    grid = dim3(INIT_SUBDIV, INIT_SUBDIV);

    // DYNAMIC PARALLELISM
    for (int i=0; i< REPEATS; i++){
        ti = omp_get_wtime();
        mandelbrot_block_k<<<grid, bs>>>(d_dwells, w, h, complex(-1.5, -1), complex(0.5, 1), 0, 0, W / INIT_SUBDIV, 1);
        (cudaDeviceSynchronize());
        tf = omp_get_wtime();
        t3 += tf - ti;
    }
    t3 /= REPEATS;

	cucheck(cudaMemcpy(h_dwells3, d_dwells, dwell_sz, cudaMemcpyDeviceToHost));
	
    // save the image to PNG file
	save_image("res1.png", h_dwells1, w, h);
	save_image("res2.png", h_dwells2, w, h);
	save_image("res3.png", h_dwells3, w, h);

	// print performance
    int res1 = 0;
    int res2 = 0;
    int res3 = 0;
    //printf("Check 1:\n");
    res1 = checkArray(h_dwells1, h_dwells2, W, H);
    //printf("Check 2:\n");
    res2 = checkArray(h_dwells1, h_dwells3, W, H);
    //printf("Check 3:\n");
    res3 = checkArray(h_dwells2, h_dwells3, W, H);

    if (res1 != res2){
        exit(99);
    } 

    printf("%i, %i, %i, %i, %i, %i, %i, %f, %f, %f\n", BSX, BSY, W, H, MAX_DWELL, MAX_DEPTH,
            SUBDIV, t1, t2, t3);

	// free data
	cudaFree(d_dwells);
	free(h_dwells1);
	free(h_dwells2);
	free(h_dwells3);
    exit(0);
}  // main
