{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE NoStarIsType #-}
{-# OPTIONS_GHC -v2 #-}

module Torch.GraduallyTyped.NN.Transformer.Stack where

import Control.Monad.Indexed.State (IxStateT (..))
import Control.Monad.State (evalStateT)
import Data.Functor.Indexed ((<<$>>))
import Data.Kind (Type)
import qualified Data.Map as Map
import Data.Singletons.Prelude.List (SList (SNil))
import Data.Singletons.TypeLits (SNat (..))
import qualified Data.Vector as V
import qualified Data.Vector.Generic.Sized.Internal as VGS
import qualified Data.Vector.Sized as VS
import GHC.TypeLits (type (+))
import Torch.GraduallyTyped.DType (SDType (..), SDataType (..))
import Torch.GraduallyTyped.Device (SDevice (..), SDeviceType (..))
import Torch.GraduallyTyped.Layout (SLayout (SLayout), SLayoutType (SDense))
import Torch.GraduallyTyped.NN.Class (HasForward (..), HasInitialize (..), HasStateDict (..), ModelSpec, NamedModel (..), VectorSpec (..))
import Torch.GraduallyTyped.NN.Transformer.Block (DecoderBlockCrossAttentionF, DecoderBlockFeedForwardNetworkF, DecoderBlockSelfAttentionF, EncoderBlockCrossAttentionF, EncoderBlockFeedForwardNetworkF, EncoderBlockSelfAttentionF, GTransformerBlock, decoderBlockSpec)
import Torch.GraduallyTyped.NN.Transformer.Type (STransformerStyle (ST5))
import Torch.GraduallyTyped.Random (sMkGenerator)
import Torch.GraduallyTyped.RequiresGradient (SGradient (..), SRequiresGradient (..))
import Torch.GraduallyTyped.Shape.Type (SDim, SName (..), SShape (SShape), SSize (..), pattern (:&:), pattern (:|:))
import Torch.GraduallyTyped.Tensor.Creation (sOnes)
import Torch.GraduallyTyped.Tensor.Type (TensorSpec (TensorSpec))

-- | Generic transformer stack.
--
-- - @stack@ is a stack of tranformer blocks.
newtype GTransformerStack (stack :: Type) where
  GTransformerStack :: forall stack. stack -> GTransformerStack stack

type instance
  ModelSpec (GTransformerStack stack) =
    GTransformerStack (ModelSpec stack)

-- | Specifies the parameters of a transformer stack in an encoder configuration.
--
-- - @style@: the style of the transformer stack, e.g. 'ST5', 'SByT5', etc.
-- - @gradient@: whether to compute the gradient of the stack's parameters.
-- - @device@: the computational device on which the stack is allocated.
-- - @dataType@: the data type of the stack's parameters.
-- - @headDim@: the dimension of all transformer heads in the stack.
-- - @headEmbedDim@: the dimension of the transformer head embeddings.
-- - @embedDim@: the dimension of the transformer embeddings.
-- - @queryEmbedDim@: the dimension of the transformer query embeddings.
-- - @ffnDim@: the dimension of the feed-forward network.
-- - @dropoutP@: the dropout rate.
-- - @eps@: the epsilon value for numerical stability of the layer normalization.
encoderStackSpec ::
  forall style numLayers gradient device dataType headDim headEmbedDim embedDim queryEmbedDim ffnDim.
  STransformerStyle style ->
  SNat numLayers ->
  SGradient gradient ->
  SDevice device ->
  SDataType dataType ->
  SDim headDim ->
  SDim headEmbedDim ->
  SDim embedDim ->
  SDim queryEmbedDim ->
  SDim ffnDim ->
  Double ->
  Double ->
  ModelSpec
    ( GTransformerStack
        ( VS.Vector
            numLayers
            ( GTransformerBlock
                (EncoderBlockSelfAttentionF style gradient device dataType headDim headEmbedDim embedDim queryEmbedDim)
                EncoderBlockCrossAttentionF
                (EncoderBlockFeedForwardNetworkF style gradient device dataType queryEmbedDim ffnDim)
            )
        )
    )
encoderStackSpec = undefined

-- | Specifies the parameters of a transformer stack in a decoder configuration.
--
-- - @style@: the style of the transformer stack, e.g. 'ST5', 'SByT5', etc.
-- - @gradient@: whether to compute the gradient of the stack's parameters.
-- - @device@: the computational device on which the stack is allocated.
-- - @dataType@: the data type of the stack's parameters.
-- - @headDim@: the dimension of all transformer heads in the stack.
-- - @headEmbedDim@: the dimension of the transformer head embeddings.
-- - @embedDim@: the dimension of the transformer embeddings.
-- - @queryEmbedDim@: the dimension of the transformer query embeddings.
-- - @keyEmbedDim@: the dimension of the transformer key embeddings.
-- - @ffnDim@: the dimension of the feed-forward network.
-- - @dropoutP@: the dropout rate.
-- - @eps@: the epsilon value for numerical stability of the layer normalization.
decoderStackSpec ::
  forall style numLayers gradient device dataType headDim headEmbedDim embedDim queryEmbedDim keyEmbedDim ffnDim.
  STransformerStyle style ->
  SNat numLayers ->
  SGradient gradient ->
  SDevice device ->
  SDataType dataType ->
  SDim headDim ->
  SDim headEmbedDim ->
  SDim embedDim ->
  SDim queryEmbedDim ->
  SDim keyEmbedDim ->
  SDim ffnDim ->
  Double ->
  Double ->
  ModelSpec
    ( GTransformerStack
        ( VS.Vector
            numLayers
            ( GTransformerBlock
                (DecoderBlockSelfAttentionF style gradient device dataType headDim headEmbedDim embedDim queryEmbedDim)
                (DecoderBlockCrossAttentionF style gradient device dataType headDim headEmbedDim embedDim queryEmbedDim keyEmbedDim)
                (DecoderBlockFeedForwardNetworkF style gradient device dataType queryEmbedDim ffnDim)
            )
        )
    )
decoderStackSpec style numLayers@SNat gradient device dataType headDim headEmbedDim embedDim queryEmbedDim keyEmbedDim ffnDim dropoutP eps =
  let blockSpec = decoderBlockSpec style gradient device dataType headDim headEmbedDim embedDim queryEmbedDim keyEmbedDim ffnDim dropoutP eps
   in GTransformerStack $ VectorSpec numLayers (VS.replicate' numLayers blockSpec)

instance
  ( HasInitialize block generatorDevice block generatorDevice,
    numLayers' ~ (numLayers + 1)
  ) =>
  HasInitialize
    (GTransformerStack (VS.Vector numLayers' block))
    generatorDevice
    (GTransformerStack (VS.Vector numLayers' block))
    generatorDevice
  where
  initialize (GTransformerStack vSpec) =
    let v = IxStateT . initialize $ vSpec
     in runIxStateT (GTransformerStack <<$>> v)

instance
  HasStateDict block =>
  HasStateDict (GTransformerStack (VS.Vector numLayers block))
  where
  fromStateDict (GTransformerStack vSpec) k =
    GTransformerStack <$> fromStateDict vSpec k
  toStateDict k (GTransformerStack v) = toStateDict k v

instance
  HasForward
    (GTransformerStack (VS.Vector 0 block))
    (query, attentionBias)
    generatorDevice
    query
    generatorDevice
  where
  forward _ (query, _) = pure . (query,)

instance
  HasForward
    block
    (query, attentionBias)
    generatorDevice
    output
    generatorOutputDevice =>
  HasForward
    (GTransformerStack (VS.Vector 1 block))
    (query, attentionBias)
    generatorDevice
    output
    generatorOutputDevice
  where
  forward (GTransformerStack (VGS.Vector v)) input g =
    let Just (block, _) = V.uncons v
     in forward block input g

instance
  HasForward
    (GTransformerStack (VS.Vector 0 block))
    (query, key, attentionBias, crossAttentionBias)
    generator
    query
    generator
  where
  forward _ (query, _, _, _) = pure . (query,)

instance
  HasForward
    block
    (query, key, attentionBias, crossAttentionBias)
    generatorDevice
    output
    generatorOutputDevice =>
  HasForward
    (GTransformerStack (VS.Vector 1 block))
    (query, key, attentionBias, crossAttentionBias)
    generatorDevice
    output
    generatorOutputDevice
  where
  forward (GTransformerStack (VGS.Vector v)) input g =
    let Just (block, _) = V.uncons v
     in forward block input g

-- | 'HasForward' instance for 'GTransformerStack' in an encoder configuration.
--
-- @
-- ┌───────┐  ┌───────────────┐
-- │ query │  │ attentionBias │
-- └───┬───┘  └───────┬───────┘
--     │              │
--     ▼              │
--   block◄───────────┤
--     ▼              │
--   block◄───────────┤
--     ▼              │
--    ...            ...
--     ▼              │
--   block◄───────────┘
--     │
--     ▼
-- ┌───────┐
-- │ query │
-- └───────┘
-- @
instance
  {-# OVERLAPPABLE #-}
  ( HasForward
      block
      (query, attentionBias)
      generatorDevice
      output
      generatorOutputDevice,
    HasForward
      block
      (output, attentionBias)
      generatorOutputDevice
      output
      generatorOutputDevice
  ) =>
  HasForward
    (GTransformerStack (VS.Vector n block))
    (query, attentionBias)
    generatorDevice
    output
    generatorOutputDevice
  where
  forward (GTransformerStack (VGS.Vector v)) (query, attentionBias) g =
    let Just (block, blocks) = V.uncons v
     in V.foldl
          ( \agg block' -> do
              (output, g') <- agg
              (output', g'') <- forward block' (output, attentionBias) g'
              pure (output', g'')
          )
          ( do
              (output, g') <- forward block (query, attentionBias) g
              pure (output, g')
          )
          blocks

-- | 'HasForward' instance for 'GTransformerStack' in a decoder configuration.
--
-- @
-- ┌───────┐  ┌─────┐  ┌───────────────┐  ┌────────────────────┐
-- │ query │  │ key │  │ attentionBias │  │ crossAttentionBias │
-- └───┬───┘  └──┬──┘  └───────┬───────┘  └─────────┬──────────┘
--     │         │             │                    │
--     ▼         │             │                    │
--   block◄──────┤◄────────────┤◄───────────────────┤
--     ▼         │             │                    │
--   block◄──────┤◄────────────┤◄───────────────────┤
--     ▼         │             │                    │
--    ...       ...           ...                  ...
--     ▼         │             │                    │
--   block◄──────┘◄────────────┘◄───────────────────┘
--     │
--     ▼
-- ┌───────┐
-- │ query │
-- └───────┘
-- @
instance
  {-# OVERLAPPABLE #-}
  ( HasForward
      block
      (query, key, attentionBias, crossAttentionBias)
      generatorDevice
      output
      generatorOutputDevice,
    HasForward
      block
      (output, key, attentionBias, crossAttentionBias)
      generatorOutputDevice
      output
      generatorOutputDevice
  ) =>
  HasForward
    (GTransformerStack (VS.Vector n block))
    (query, key, attentionBias, crossAttentionBias)
    generatorDevice
    output
    generatorOutputDevice
  where
  forward (GTransformerStack (VGS.Vector v)) (query, key, attentionBias, crossAttentionBias) g =
    let Just (block, blocks) = V.uncons v
     in V.foldl
          ( \agg block' -> do
              (output, g') <- agg
              (output', g'') <- forward block' (output, key, attentionBias, crossAttentionBias) g'
              pure (output', g'')
          )
          ( do
              (output, g') <- forward block (query, key, attentionBias, crossAttentionBias) g
              pure (output, g')
          )
          blocks

testEncoderStack :: IO _
testEncoderStack = do
  let gradient = SGradient SWithGradient
      device = SDevice SCPU
      dataType = SDataType SFloat
      headDim = SName @"*" :&: SSize @8
      headEmbedDim = SName @"*" :&: SSize @64
      embedDim = SName @"*" :&: SSize @512
      queryEmbedDim = SName @"*" :&: SSize @512
      ffnDim = SName @"*" :&: SSize @2048
      dropoutP = 0
      eps = 1e-6
  let g = sMkGenerator device 0
      spec = NamedModel "stack." $ encoderStackSpec ST5 (SNat @2) gradient device dataType headDim headEmbedDim embedDim queryEmbedDim ffnDim dropoutP eps
  (encoderStack, g') <- initialize spec g
  encoderStack' <- flip evalStateT Map.empty $ do
    toStateDict mempty encoderStack
    fromStateDict spec mempty
  let batchDim = SName @"*" :&: SSize @3
      seqDim = SName @"*" :&: SSize @17
      sOnes' = (sOnes .) . TensorSpec (SGradient SWithoutGradient) (SLayout SDense) device
      query = sOnes' dataType (SShape $ batchDim :|: seqDim :|: queryEmbedDim :|: SNil)
      attentionBias = sOnes' dataType (SShape $ batchDim :|: SName @"*" :&: SSize @1 :|: seqDim :|: seqDim :|: SNil)
  (output, _) <- forward encoderStack' (query, attentionBias) g'
  pure output

testDecoderStack :: IO _
testDecoderStack = do
  let gradient = SGradient SWithGradient
      device = SDevice SCPU
      dataType = SDataType SFloat
      headDim = SName @"*" :&: SSize @8
      headEmbedDim = SName @"*" :&: SSize @64
      embedDim = SName @"*" :&: SSize @512
      queryEmbedDim = SName @"*" :&: SSize @512
      keyEmbedDim = queryEmbedDim
      ffnDim = SName @"*" :&: SSize @2048
      dropoutP = 0
      eps = 1e-6
  let g = sMkGenerator device 0
      spec = NamedModel "stack." $ decoderStackSpec ST5 (SNat @2) gradient device dataType headDim headEmbedDim embedDim queryEmbedDim keyEmbedDim ffnDim dropoutP eps
  (decoderStack, g') <- initialize spec g
  decoderStack' <- flip evalStateT Map.empty $ do
    toStateDict mempty decoderStack
    fromStateDict spec mempty
  let batchDim = SName @"*" :&: SSize @3
      seqDim = SName @"*" :&: SSize @17
      decoderSeqDim = SName @"*" :&: SSize @13
      sOnes' = (sOnes .) . TensorSpec (SGradient SWithoutGradient) (SLayout SDense) device
      query = sOnes' dataType (SShape $ batchDim :|: decoderSeqDim :|: queryEmbedDim :|: SNil)
      key = sOnes' dataType (SShape $ batchDim :|: seqDim :|: keyEmbedDim :|: SNil)
      attentionBias = sOnes' dataType (SShape $ batchDim :|: SName @"*" :&: SSize @1 :|: decoderSeqDim :|: decoderSeqDim :|: SNil)
      crossAttentionBias = sOnes' dataType (SShape $ batchDim :|: SName @"*" :&: SSize @1 :|: decoderSeqDim :|: seqDim :|: SNil)
  (output, _) <- forward decoderStack' (query, key, attentionBias, crossAttentionBias) g'
  pure output
