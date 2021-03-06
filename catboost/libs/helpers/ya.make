LIBRARY()



SRCS(
    array_subset.h
    binarize_target.cpp
    cpu_random.cpp
    data_split.cpp
    dense_hash.cpp
    dense_hash_view.cpp
    hash.h
    index_range.h
    interrupt.cpp
    map_merge.cpp
    matrix.cpp
    maybe_owning_array_holder.h
    power_hash.cpp
    progress_helper.cpp
    permutation.cpp
    query_info_helper.cpp
    resource_constrained_executor.cpp
    resource_holder.h
    restorable_rng.cpp
    wx_test.cpp
)

PEERDIR(
    catboost/libs/data_util
    catboost/libs/logging
    library/binsaver
    library/containers/2d_array
    library/digest/md5
    library/malloc/api
    library/threading/local_executor
    contrib/libs/clapack
)

END()
