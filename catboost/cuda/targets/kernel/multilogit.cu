#include "multilogit.cuh"
#include <catboost/cuda/cuda_util/kernel/kernel_helpers.cuh>
#include <catboost/cuda/cuda_util/kernel/fill.cuh>

namespace NKernel {


    template <int BlockSize, int ElementsPerThread>
    __launch_bounds__(BlockSize, 2048 / BlockSize)
    __global__ void MultiLogitValAndFirstDerImpl(const float* targetClasses, int numClasses, ui32 size,
                                                 const float* weights,
                                                 const float* predictions,
                                                 const ui32* loadPredictionsIndices,
                                                 ui64 predictionsAlignSize,
                                                 float* functionValue,
                                                 float* der,
                                                 ui64 derAlignSize) {

        ui32 tid = blockIdx.x * BlockSize * ElementsPerThread + threadIdx.x;
        const int effectiveClassCount = numClasses - 1;

        float tmpScore = 0;

        float classApprox[ElementsPerThread];
        float expClassApprox[ElementsPerThread];
        ui8 targetClass[ElementsPerThread];
        float sumExpApproxForAllClasses[ElementsPerThread];

        float weight[ElementsPerThread];
        float maxApprox[ElementsPerThread];

        ui32 loadApproxIndex[ElementsPerThread];
        {

            #pragma unroll
            for (int j = 0; j < ElementsPerThread; ++j) {
                const int idx = tid + j * BlockSize;
                loadApproxIndex[j] = loadPredictionsIndices && idx < size ? __ldg(loadPredictionsIndices + idx) : idx;
                targetClass[j] = idx < size ? static_cast<ui8>(__ldg(targetClasses + idx)) : 0;


                maxApprox[j] = 0;
                for (int k = 0; k < effectiveClassCount; ++k) {
                    maxApprox[j] = idx < size ? max(maxApprox[j], __ldg(predictions + loadApproxIndex[j] + k * predictionsAlignSize)) : 0;
                }

                const float tmp =  targetClass[j] < effectiveClassCount  && idx < size ? __ldg(predictions + loadApproxIndex[j] + targetClass[j] * predictionsAlignSize)  : 0.0f;
                classApprox[j] = tmp - maxApprox[j];
                expClassApprox[j] = __expf(classApprox[j]);

                sumExpApproxForAllClasses[j] = 0.0f;
                for (int k = 0; k < effectiveClassCount; ++k) {
                    sumExpApproxForAllClasses[j] += idx < size ? __expf(__ldg(predictions + loadApproxIndex[j] + k * predictionsAlignSize) - maxApprox[j]) : 0.0f;
                }

                sumExpApproxForAllClasses[j] += __expf(0.0f - maxApprox[j]);
            }
        }


        #pragma unroll
        for (int j = 0; j < ElementsPerThread; ++j) {
            const int idx = tid + j * BlockSize;
            weight[j] = (weights && (idx < size)) ? weights[idx] : 1.0f;
        }



        #pragma unroll
        for (int j = 0; j < ElementsPerThread; ++j) {
            const int idx = tid + j * BlockSize;

            if (der && idx < size) {
                for (int k = 0; k < effectiveClassCount; ++k) {
                    const float pk = __expf(__ldg(predictions + loadApproxIndex[j] + k * predictionsAlignSize) - maxApprox[j]) / sumExpApproxForAllClasses[j];

                    der[idx + k * derAlignSize] = weight[j] * ((targetClass[j] == k ? 1.0f : 0.0f) - pk);
                }
            }


            if (functionValue) {
                const float logDenum = __logf(sumExpApproxForAllClasses[j]);
                tmpScore += (idx < size) ? weight[j] * (classApprox[j] - logDenum) : 0;
            }
        }


        if (functionValue) {
            __shared__ float tmpScores[BlockSize];
            tmpScores[threadIdx.x] = tmpScore;
            __syncthreads();

            float val = FastInBlockReduce<float>(threadIdx.x, tmpScores, BlockSize);

            if (threadIdx.x == 0) {
                atomicAdd(functionValue, val);
            }
        }
    }



    template <int BlockSize, int ElementsPerThread>
    __launch_bounds__(BlockSize, 2048 / BlockSize)
    __global__ void MultiLogitSecondDerRowImpl(const float* targetClasses, int numClasses, ui32 size,
                                               const float* weights,
                                               const float* predictions,
                                               ui64 predictionsAlignSize,
                                               int der2Row,
                                               ui64 der2AlignSize,
                                               float* der2) {

        ui32 tid = blockIdx.x * BlockSize * ElementsPerThread + threadIdx.x;
        const int effectiveClassCount = numClasses - 1;

        float tmpScore = 0;

        ui8 targetClass[ElementsPerThread];
        float sumExpApproxForAllClasses[ElementsPerThread];

        float weight[ElementsPerThread];
        float maxApprox[ElementsPerThread];

        {

            #pragma unroll
            for (int j = 0; j < ElementsPerThread; ++j) {
                const int idx = tid + j * BlockSize;
                targetClass[j] = idx < size ? static_cast<ui8>(__ldg(targetClasses + idx)) : 0;

                maxApprox[j] = 0;
                for (int k = 0; k < effectiveClassCount; ++k) {
                    maxApprox[j] = idx < size ? max(maxApprox[j], __ldg(predictions + idx + k * predictionsAlignSize)) : 0;
                }


                sumExpApproxForAllClasses[j] = 0.0f;
                for (int k = 0; k < effectiveClassCount; ++k) {
                    sumExpApproxForAllClasses[j] += idx < size ? __expf(__ldg(predictions + idx + k * predictionsAlignSize) - maxApprox[j]) : 0;
                }

                sumExpApproxForAllClasses[j] += __expf(0.0f - maxApprox[j]);
            }
        }


        #pragma unroll
        for (int j = 0; j < ElementsPerThread; ++j) {
            const int idx = tid + j * BlockSize;
            weight[j] = (weights && (idx < size)) ? weights[idx] : 1.0f;
        }


        #pragma unroll
        for (int j = 0; j < ElementsPerThread; ++j) {
            const int idx = tid + j * BlockSize;
            const int lastRowToWrite = der2Row;
            if (idx < size) {
                float pRow = 0;
                if (der2Row < effectiveClassCount) {
                    pRow = __expf(__ldg(predictions + idx + der2Row * predictionsAlignSize) - maxApprox[j]) / sumExpApproxForAllClasses[j];
                } else {
                    pRow = __expf(-maxApprox[j]) / sumExpApproxForAllClasses[j];
                }

                for (int k = 0; k < der2Row; ++k) {
                    const float pk = __expf(__ldg(predictions + idx + k * predictionsAlignSize) - maxApprox[j]) / sumExpApproxForAllClasses[j];

                    der2[idx + k * der2AlignSize] = -weight[j] * pk * pRow;
                }
                der2[idx + der2Row * der2AlignSize] = weight[j] * (1.0 - pRow) * pRow;
            }
        }
    }


    void MultiLogitValueAndDer(const float* targetClasses, int numClasses,
                               const float* targetWeights,
                               ui32 size,
                               const float* predictions, ui32 predictionsAlignSize,
                               const ui32* loadPredictionsIndices,
                               float* functionValue,
                               float* der, ui32 derAlignSize,
                               TCudaStream stream) {

        const ui32 blockSize = 256;
        const ui32 elementsPerThreads = 2;
        const ui32 numBlocks = CeilDivide<ui32>(size, elementsPerThreads * blockSize);

        //TODO: get rid of this
        if (functionValue) {
            FillBuffer(functionValue, 0.0f, 1, stream);
        }

        if (numBlocks) {
            MultiLogitValAndFirstDerImpl < blockSize, elementsPerThreads ><<<numBlocks, blockSize, 0, stream>>>(targetClasses, numClasses, size, targetWeights, predictions, loadPredictionsIndices, predictionsAlignSize,  functionValue, der, derAlignSize);
        }
    }


    void MultiLogitSecondDer(const float* targetClasses, int numClasses,
                             const float* targetWeights,
                             ui32 size,
                             const float* predictions, ui32 predictionsAlignSize,
                             float* der2,
                             int der2Row, ui32 der2AlignSize,
                             TCudaStream stream) {

        const ui32 blockSize = 256;
        const ui32 elementsPerThreads = 2;
        const ui32 numBlocks = CeilDivide<ui32>(size, elementsPerThreads * blockSize);


        if (numBlocks) {
            MultiLogitSecondDerRowImpl < blockSize, elementsPerThreads ><<<numBlocks, blockSize, 0, stream>>>(targetClasses, numClasses, size, targetWeights, predictions, predictionsAlignSize, der2Row, der2AlignSize, der2);
        }
    }
}
