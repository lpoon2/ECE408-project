#ifndef MXNET_OPERATOR_NEW_FORWARD_CUH_
#define MXNET_OPERATOR_NEW_FORWARD_CUH_
#define TILE_WIDTH 13

#include <mxnet/base.h>

namespace mxnet
{
namespace op
{
__global__ void forward_kernel(float * __restrict__ y, const float * __restrict__ x, const float * __restrict__ k, const int B, const int M, const int C, const int H, const int W, const int K){
    float sum = 0.0;
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    int X_width = (TILE_WIDTH+K-1);
    extern __shared__ float shmem[];
    float* X_share = &shmem[0];
    float* W_share = &shmem[C*(X_width*X_width)];
    #define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
    #define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
    #define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]

    int W_grid = ceil(W_out/(TILE_WIDTH*1.0));
    int H_grid=ceil(H_out/(TILE_WIDTH*1.0));

    int b = blockIdx.x;
    int m = blockIdx.y;
    int h0 = threadIdx.y;
    int w0 = threadIdx.x;
    int h_base = (blockIdx.z / W_grid)*TILE_WIDTH;
    int w_base = (blockIdx.z % W_grid)*TILE_WIDTH;
    int h = h_base+h0;
    int w = w_base+w0;
    int c = threadIdx.z;

    if((h0<K) && (w0<K)){
      W_share[c*(K * K)+(threadIdx.y*K)+threadIdx.x]=k4d(m,c,h0,w0);
    }
      __syncthreads();

      for(int i=h; i< h_base + X_width ;i+=TILE_WIDTH){
        for(int j=w; j< w_base + X_width;j+=TILE_WIDTH){
          X_share[c*(X_width*X_width)+(i-h_base)*X_width+(j-w_base)]=x4d(b,c,i,j); //load in tile needed for shared memory
        }
      }
      __syncthreads();

      for(int p=0;p<K;p++){
        for(int q=0;q<K;q++){
          sum += X_share[c*(X_width*X_width)+((threadIdx.y+p)*X_width)+(threadIdx.x+q)]*W_share[c*(K * K)+(p*K)+q];
        }
      }
      __syncthreads();

  if ((b < B) && (m < M) && (h < H_out) && (w < W_out)) {
    atomicAdd(&y4d(b,m,h,w), sum);
  }

    #undef y4d
    #undef x4d
    #undef k4d
}


template <>
void forward<gpu, float>(mshadow::Tensor<gpu, 4, float> & __restrict__ y, const mshadow::Tensor<gpu, 4, float> & __restrict__ x, const mshadow::Tensor<gpu, 4, float> & __restrict__ w)
{
    const int B = x.shape_[0]; //batches
    const int M = y.shape_[1]; //output channels
    const int C = x.shape_[1]; //input channels
    const int H = x.shape_[2]; //height of input
    const int W = x.shape_[3]; //width of input
    const int K = w.shape_[3]; //height and width of weights
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    //cudaStream_t s = y.stream_->stream_;
    const int W_grid = ceil(W_out/(1.0*TILE_WIDTH));
    const int H_grid = ceil(H_out/(1.0*TILE_WIDTH));
    const int Z = W_grid*H_grid;

    //printf("HELLO======= B :%d, M: %d, C: %d, H:%d, W:%d, K:%d", B, M, C, H, W, K);
    dim3 gridDim(B, M, Z);
    dim3 blockDim(TILE_WIDTH,TILE_WIDTH,C);

    size_t shmem_size=sizeof(float)*(((TILE_WIDTH + K - 1) * (TILE_WIDTH + K - 1)*C) + (K * K)*C );
    forward_kernel<<<gridDim, blockDim,shmem_size>>>(y.dptr_, x.dptr_,w.dptr_, B, M, C, H, W, K);
    // Use MSHADOW_CUDA_CALL to check for CUDA runtime errors.
    MSHADOW_CUDA_CALL(cudaDeviceSynchronize());

}

template <typename gpu, typename DType>
void forward(mshadow::Tensor<gpu, 4, DType> &y, const mshadow::Tensor<gpu, 4, DType> &x, const mshadow::Tensor<gpu, 4, DType> &w)
{
    CHECK_EQ(0,1) << "Remove this line and replace it with your implementation.";
}
}
}

#endif
