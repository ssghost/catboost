#pragma once


#include <catboost/cuda/cuda_lib/kernel/kernel.cuh>
#include <catboost/libs/options/enums.h>

namespace NKernel {

    void MultiLogitValueAndDer(const float* targetClasses, int numClasses,
                               const float* targetWeights,
                               ui32 size,
                               const float* predictions, ui32 predictionsAlignSize,
                               const ui32* loadPredictionsIndices,
                               float* functionValue,
                               float* der, ui32 derAlignSize,
                               TCudaStream stream);

    void MultiLogitSecondDer(const float* targetClasses, int numClasses,
                             const float* targetWeights,
                             ui32 size,
                             const float* predictions, ui32 predictionsAlignSize,
                             float* der2,
                             int der2Row, ui32 der2AlignSize,
                             TCudaStream stream);

}
