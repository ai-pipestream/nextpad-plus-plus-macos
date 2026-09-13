#import "SemanticSimilarityEngines.h"
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <Accelerate/Accelerate.h>
#include <cstring>

#pragma mark - Metal / MPS

@implementation MetalSimilarityEngine {
    id<MTLDevice>       _device;
    id<MTLCommandQueue> _queue;
}

+ (nullable instancetype)engineIfAvailable {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device || !MPSSupportsMTLDevice(device)) return nil;
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (!queue) return nil;

    MetalSimilarityEngine *engine = [[self alloc] init];
    engine->_device = device;
    engine->_queue  = queue;
    return engine;
}

- (NSString *)engineName { return @"Metal/MPS"; }

- (BOOL)scoresForQuery:(const float *)query
               vectors:(const float *)vectors
                 count:(NSUInteger)count
             dimension:(NSUInteger)dimension
             outScores:(float *)outScores {
    if (count == 0 || dimension == 0) return YES;

    // MPS wants each matrix row aligned to rowBytesFromColumns; when that
    // matches the packed layout (dim * 4 — true for typical embedding dims,
    // which are multiples of 4) we upload with one memcpy, otherwise we
    // repack row by row into the padded buffer.
    NSUInteger rowBytes = [MPSMatrixDescriptor rowBytesFromColumns:dimension
                                                          dataType:MPSDataTypeFloat32];
    NSUInteger packedRowBytes = dimension * sizeof(float);

    id<MTLBuffer> matBuf = [_device newBufferWithLength:count * rowBytes
                                                options:MTLResourceStorageModeShared];
    id<MTLBuffer> qBuf   = [_device newBufferWithBytes:query
                                                length:packedRowBytes
                                               options:MTLResourceStorageModeShared];
    id<MTLBuffer> outBuf = [_device newBufferWithLength:count * sizeof(float)
                                                options:MTLResourceStorageModeShared];
    if (!matBuf || !qBuf || !outBuf) return NO;

    if (rowBytes == packedRowBytes) {
        memcpy(matBuf.contents, vectors, count * packedRowBytes);
    } else {
        char *dst = (char *)matBuf.contents;
        for (NSUInteger r = 0; r < count; r++)
            memcpy(dst + r * rowBytes, vectors + r * dimension, packedRowBytes);
    }

    MPSMatrixDescriptor *mDesc =
        [MPSMatrixDescriptor matrixDescriptorWithRows:count
                                              columns:dimension
                                             rowBytes:rowBytes
                                             dataType:MPSDataTypeFloat32];
    MPSVectorDescriptor *qDesc =
        [MPSVectorDescriptor vectorDescriptorWithLength:dimension dataType:MPSDataTypeFloat32];
    MPSVectorDescriptor *outDesc =
        [MPSVectorDescriptor vectorDescriptorWithLength:count dataType:MPSDataTypeFloat32];

    MPSMatrix *matrix = [[MPSMatrix alloc] initWithBuffer:matBuf descriptor:mDesc];
    MPSVector *qVec   = [[MPSVector alloc] initWithBuffer:qBuf descriptor:qDesc];
    MPSVector *outVec = [[MPSVector alloc] initWithBuffer:outBuf descriptor:outDesc];

    MPSMatrixVectorMultiplication *mv =
        [[MPSMatrixVectorMultiplication alloc] initWithDevice:_device
                                                    transpose:NO
                                                         rows:count
                                                      columns:dimension
                                                        alpha:1.0
                                                         beta:0.0];

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    if (!cb) return NO;
    [mv encodeToCommandBuffer:cb inputMatrix:matrix inputVector:qVec resultVector:outVec];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.error) return NO;

    memcpy(outScores, outBuf.contents, count * sizeof(float));
    return YES;
}

@end

#pragma mark - Accelerate (CPU fallback)

@implementation AccelerateSimilarityEngine

- (NSString *)engineName { return @"Accelerate"; }

- (BOOL)scoresForQuery:(const float *)query
               vectors:(const float *)vectors
                 count:(NSUInteger)count
             dimension:(NSUInteger)dimension
             outScores:(float *)outScores {
    if (count == 0 || dimension == 0) return YES;
    // scores = M · q, row-major count×dim matrix times dim vector.
    cblas_sgemv(CblasRowMajor, CblasNoTrans,
                (int)count, (int)dimension,
                1.0f, vectors, (int)dimension,
                query, 1,
                0.0f, outScores, 1);
    return YES;
}

@end

id<SemanticSimilarityEngine> NppBestSimilarityEngine(void) {
    MetalSimilarityEngine *metal = [MetalSimilarityEngine engineIfAvailable];
    if (metal) return metal;
    return [[AccelerateSimilarityEngine alloc] init];
}
