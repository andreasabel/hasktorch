{-# LANGUAGE DataKinds #-}

module Torch.Core.Tensor.Static.DoubleRandom
  ( tds_random
  , tds_clampedRandom
  , tds_cappedRandom
  , tds_geometric
  , tds_bernoulli
  , tds_bernoulliFloat
  , tds_bernoulliDouble
  , tds_uniform
  , tds_normal
  , tds_exponential
  , tds_cauchy
  , tds_multinomial
  ) where

import Foreign
import Foreign.C.Types
import Foreign.Ptr
import Foreign.ForeignPtr (ForeignPtr, withForeignPtr)
import GHC.Ptr (FunPtr)
import System.IO.Unsafe (unsafePerformIO)

import Torch.Core.Tensor.Static.Double
import Torch.Core.Tensor.Double
import Torch.Core.Tensor.Raw
import Torch.Core.Tensor.Types
import Torch.Core.Random

import THTypes
import THRandom
import THDoubleTensor
import THDoubleTensorMath
import THDoubleTensorRandom

import THFloatTensor

import Data.Singletons

tds_random :: SingI d => (TDS d) -> RandGen -> IO (TDS d)
tds_random self gen = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_random s g
         )
    )
  pure self

tds_clampedRandom self gen minVal maxVal = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_clampedRandom s g minC maxC
         )
    )
  pure self
  where (minC, maxC) = (fromIntegral minVal, fromIntegral maxVal)

tds_cappedRandom :: SingI d => (TDS d) -> RandGen -> Int -> IO (TDS d)
tds_cappedRandom self gen maxVal = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_cappedRandom s g maxC
         )
    )
  pure self
  where maxC = fromIntegral maxVal

-- TH_API void THTensor_(geometric)(THTensor *self, THGenerator *_generator, double p);
tds_geometric :: SingI d => (TDS d) -> RandGen -> Double -> IO (TDS d)
tds_geometric self gen p = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_geometric s g pC
         )
    )
  pure self
  where pC = realToFrac p

-- TH_API void THTensor_(bernoulli)(THTensor *self, THGenerator *_generator, double p);
tds_bernoulli :: SingI d => (TDS d) -> RandGen -> Double -> IO (TDS d)
tds_bernoulli self gen p = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_bernoulli s g pC
         )
    )
  pure self
  where pC = realToFrac p

tds_bernoulliFloat :: SingI d => (TDS d) -> RandGen -> TensorFloat -> IO ()
tds_bernoulliFloat self gen p = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
            withForeignPtr (pC)
              (\pTensor ->
                 c_THDoubleTensor_bernoulli_FloatTensor s g pTensor
              )
         )
    )
  where pC = tfTensor p

tds_bernoulliDouble :: SingI d => (TDS d) -> RandGen -> (TDS d) -> IO (TDS d)
tds_bernoulliDouble self gen p = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
            withForeignPtr (pC)
              (\pTensor ->
                 c_THDoubleTensor_bernoulli_DoubleTensor s g pTensor
              )
         )
    )
  pure self
  where pC = tdsTensor p

tds_uniform :: SingI d => (TDS d) -> RandGen -> Double -> Double -> IO (TDS d)
tds_uniform self gen a b = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_uniform s g aC bC
         )
    )
  pure self
  where aC = realToFrac a
        bC = realToFrac b

tds_normal :: SingI d => (TDS d) -> RandGen -> Double -> Double -> IO (TDS d)
tds_normal self gen mean stdv = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_normal s g meanC stdvC
         )
    )
  pure self
  where meanC = realToFrac mean
        stdvC = realToFrac stdv

-- TH_API void THTensor_(normal_means)(THTensor *self, THGenerator *gen, THTensor *means, double stddev);
-- TH_API void THTensor_(normal_stddevs)(THTensor *self, THGenerator *gen, double mean, THTensor *stddevs);
-- TH_API void THTensor_(normal_means_stddevs)(THTensor *self, THGenerator *gen, THTensor *means, THTensor *stddevs);

tds_exponential :: SingI d => (TDS d) -> RandGen -> Double -> IO (TDS d)
tds_exponential self gen lambda = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_exponential s g lambdaC
         )
    )
  pure self
  where lambdaC = realToFrac lambda

tds_cauchy :: SingI d => (TDS d) -> RandGen -> Double -> Double -> IO (TDS d)
tds_cauchy self gen median sigma = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_cauchy s g medianC sigmaC
         )
    )
  pure self
  where medianC = realToFrac median
        sigmaC = realToFrac sigma

tds_logNormal :: SingI d => (TDS d) -> RandGen -> Double -> Double -> IO (TDS d)
tds_logNormal self gen mean stdv = do
  withForeignPtr (tdsTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
             c_THDoubleTensor_logNormal s g meanC stdvC
         )
    )
  pure self
  where meanC = realToFrac mean
        stdvC = realToFrac stdv


tds_multinomial :: SingI d => TensorLong -> RandGen -> (TDS d) -> Int -> Bool -> IO TensorLong
tds_multinomial self gen prob_dist n_sample with_replacement = do
  withForeignPtr (tlTensor self)
    (\s ->
       withForeignPtr (rng gen)
         (\g ->
            withForeignPtr (tdsTensor prob_dist)
              (\p ->
                 c_THDoubleTensor_multinomial s g p n_sampleC with_replacementC
              )
         )
    )
  pure self
  where n_sampleC = fromIntegral n_sample
        with_replacementC = if with_replacement then 1 else 0

-- TH_API void THTensor_(multinomialAliasSetup)(THTensor *prob_dist, THLongTensor *J, THTensor *q);
-- TH_API void THTensor_(multinomialAliasDraw)(THLongTensor *self, THGenerator *_generator, THLongTensor *J, THTensor *q);
-- #endif

test = do
  let t = tds_new :: TDS '[5]
  tds_p t
  gen <- newRNG
  tds_random t gen
  tds_p t
  pure ()