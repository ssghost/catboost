#pragma once

#include <util/system/types.h>

#ifndef __NVCC__

#include <catboost/cuda/cuda_lib/cuda_manager.h>
#include <util/ysaveload.h>
#include <float.h>

#endif
//struct to make bin-feature from ui32 feature
// (compressedIndex[Offset] & Mask  should be true
struct TCBinFeature {
    ui32 FeatureId = -1;
    ui32 BinId = -1;

    bool operator<(const TCBinFeature& other) const {
        return FeatureId < other.FeatureId || (FeatureId == other.FeatureId && BinId < other.BinId);
    }
};

struct TCFeature {
    //how to get features
    //ui64 cindex offset
    ui64 Offset = static_cast<ui64>(-1);
    //offset and mask in ui32
    ui32 Mask = 0;
    ui32 Shift = 0;
    //where and how to write histograms
    //local fold idx (index of first fold for grid on device)
    ui32 FirstFoldIndex = 0;
    //fold count
    ui32 Folds = 0;
    //    global index (not feature-id, index in grid only)
    //    ui32 Index;
    bool OneHotFeature = false;

    TCFeature() = default;

    TCFeature(ui64 offset, ui32 mask, ui32 shift, ui32 firstFoldIndex, ui32 folds, bool oneHotFeature)
        : Offset(offset)
        , Mask(mask)
        , Shift(shift)
        , FirstFoldIndex(firstFoldIndex)
        , Folds(folds)
        , OneHotFeature(oneHotFeature)
    {
    }
};

struct TBinarizedFeature {
    ui32 FirstFoldIndex = 0;
    ui32 Folds = 0;
    bool OneHotFeature = false;
};


struct TBestSplitProperties {
    ui32 FeatureId = static_cast<ui32>(-1);
    ui32 BinId = 0;
    float Score = 10e6;

    TBestSplitProperties() = default;

    TBestSplitProperties(ui32 featureId, ui32 binId, float score)
        : FeatureId(featureId)
        , BinId(binId)
        , Score(score)
    {
    }

    bool operator<(const TBestSplitProperties& other) const {
        if (Score < other.Score) {
            return true;
        } else if (Score == other.Score) {
            if (FeatureId < other.FeatureId) {
                return true;
            } else if (FeatureId == other.FeatureId) {
                return BinId < other.BinId;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }


    bool Defined() const {
        return FeatureId != static_cast<ui32>(-1);
    }

    void Reset() {
        (*this) = TBestSplitProperties();
    }
};

struct TBestSplitPropertiesWithIndex: public TBestSplitProperties {
    ui32 Index = 0;

    bool operator<(const TBestSplitPropertiesWithIndex& other) {
        return static_cast<const TBestSplitProperties&>(*this).operator<(static_cast<const TBestSplitProperties&>(other));
    }
};

struct TPartitionStatistics {
    double Weight;
    double Sum;
    double Count;

    TPartitionStatistics(double weight = 0,
                         double sum = 0,
                         double count = 0)
        : Weight(weight)
        , Sum(sum)
        , Count(count)
    {
    }

    TPartitionStatistics& operator+=(const TPartitionStatistics& other) {
        Weight += other.Weight;
        Sum += other.Sum;
        Count += other.Count;
        return *this;
    }

    bool operator==(const TPartitionStatistics& other) {
        return Weight == other.Weight &&
               Sum == other.Sum &&
               Count == other.Count;
    }
};




/*
 *  so we could write results in the following layout:
 *  leaf0
 *  stat0: f0 bin0 f0 bin1 … f1 bin0 … fk bin0 … bk bin n_k
 *  stat1: f0 bin0 f0 bin1 … f1 bin0 … fk bin0 … bk bin n_k
 *  *  leaf1
 *  stat0: f0 bin0 f0 bin1 … f1 bin0 … fk bin0 … bk bin n_k
 *  stat1: f0 bin0 f0 bin1 … f1 bin0 … fk bin0 … bk bin n_k
 *
 *  we have GroupOffset, GroupSize and FeatureOffsetInGroup
 *
 *
 */
struct TFeatureInBlock {
    ui64 CompressedIndexOffset = 0;
    int Folds = 0;
    int FoldOffsetInGroup = 0;
    int GroupOffset = 0; //offsets with global indexing
    int GroupSize = 0; // size of group = number of binFeatures on devices with this feature after reduceScatter
};



#ifndef __NVCC__
Y_DECLARE_PODTYPE(TCFeature);
Y_DECLARE_PODTYPE(TCBinFeature);

namespace NCudaLib {
    namespace NHelpers {
        template <>
        class TEmptyObjectsHelper<TCFeature> {
        public:
            static inline bool IsEmpty(const TCFeature& val) {
                return val.Offset == static_cast<ui64>(-1);
            }
        };
    }
}
#endif
