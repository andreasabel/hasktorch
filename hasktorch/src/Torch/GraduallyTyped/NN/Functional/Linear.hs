{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module Torch.GraduallyTyped.NN.Functional.Linear where

import GHC.TypeLits (Nat, Symbol, TypeError)
import System.IO.Unsafe (unsafePerformIO)
import Torch.DType (DType (..))
import Torch.GraduallyTyped.DType (DataType (..))
import Torch.GraduallyTyped.Device (Device (..), DeviceType (..))
import Torch.GraduallyTyped.Layout (Layout (..), LayoutType (..))
import Torch.GraduallyTyped.Prelude (Reverse, Seq)
import Torch.GraduallyTyped.RequiresGradient (RequiresGradient (..))
import Torch.GraduallyTyped.Shape.Type (Dim (..), Name (..), Shape (..), Size (..))
import Torch.GraduallyTyped.Tensor.Type (Tensor)
import Torch.GraduallyTyped.Unify (type (<+>), type (<|>))
import Torch.Internal.Cast (cast2, cast3)
import qualified Torch.Internal.Managed.Native as ATen
import Type.Errors.Pretty (type (%), type (<>))

-- | Compute the output shape of a linear transformation.
--
-- >>> type InputDim = 'Dim ('Name "input") ('Size 5)
-- >>> type OutputDim = 'Dim ('Name "output") ('Size 10)
-- >>> type BatchDim = 'Dim ('Name "batch") ('Size 20)
-- >>> type WeightShape = 'Shape '[OutputDim, InputDim]
-- >>> type BiasShape = 'Shape '[OutputDim]
-- >>> type InputShape = 'Shape '[BatchDim, InputDim]
-- >>> :kind! LinearWithBiasF WeightShape BiasShape InputShape
-- LinearWithBiasF WeightShape BiasShape InputShape :: Shape [Dim (Name Symbol) (Size Nat)]
-- = 'Shape
--     '[ 'Dim ('Name "batch") ('Size 20),
--        'Dim ('Name "output") ('Size 10)]
type family LinearWithBiasF (weightShape :: Shape [Dim (Name Symbol) (Size Nat)]) (biasShape :: Shape [Dim (Name Symbol) (Size Nat)]) (inputShape :: Shape [Dim (Name Symbol) (Size Nat)]) :: Shape [Dim (Name Symbol) (Size Nat)] where
  LinearWithBiasF ( 'Shape '[]) _ _ = TypeError (LinearWeightDimsErrorMessage '[])
  LinearWithBiasF ( 'Shape '[weightDim]) _ _ = TypeError (LinearWeightDimsErrorMessage '[weightDim])
  LinearWithBiasF ( 'Shape (weightDim ': weightDim' ': weightDim'' ': weightDims)) _ _ = TypeError (LinearWeightDimsErrorMessage (weightDim ': weightDim' ': weightDim'' ': weightDims))
  LinearWithBiasF _ ( 'Shape '[]) _ = TypeError (LinearBiasDimsErrorMessage '[])
  LinearWithBiasF _ ( 'Shape (biasDim ': biasDim' ': biasDims)) _ = TypeError (LinearBiasDimsErrorMessage (biasDim ': biasDim' ': biasDims))
  LinearWithBiasF _ _ ( 'Shape '[]) = TypeError LinearInputDimsErrorMessage
  LinearWithBiasF ( 'Shape weightDims) ( 'Shape biasDims) ( 'Shape inputDims) = 'Shape (Reverse (LinearWithBiasDimsF weightDims biasDims (Reverse inputDims)))
  LinearWithBiasF 'UncheckedShape _ _ = 'UncheckedShape
  LinearWithBiasF _ 'UncheckedShape _ = 'UncheckedShape
  LinearWithBiasF _ _ 'UncheckedShape = 'UncheckedShape

type family LinearWithBiasDimsF (weightDims :: [Dim (Name Symbol) (Size Nat)]) (biasDims :: [Dim (Name Symbol) (Size Nat)]) (reversedInputDims :: [Dim (Name Symbol) (Size Nat)]) :: [Dim (Name Symbol) (Size Nat)] where
  LinearWithBiasDimsF '[outputDim, inputDim] '[outputDim'] (inputDim' ': reversedInputDims) = Seq (inputDim <+> inputDim') (outputDim <+> outputDim' ': reversedInputDims)

type LinearInputDimsErrorMessage =
  "Cannot apply the linear transformation."
    % "The input tensor does not have the minimum required number of dimensions."
    % "At least one dimension is needed, but none were found."

type LinearBiasDimsErrorMessage (biasDims :: [Dim (Name Symbol) (Size Nat)]) =
  "Cannot apply the linear transformation."
    % "The bias tensor must have exactly one dimension,"
    % "but the following dimensions were found:"
    % ""
    % "    " <> biasDims <> "."
    % ""

type LinearWeightDimsErrorMessage (weightDims :: [Dim (Name Symbol) (Size Nat)]) =
  "Cannot apply the linear transformation."
    % "The weight tensor must have exactly two dimensions,"
    % "but the following dimensions were found:"
    % ""
    % "    " <> weightDims <> "."
    % ""

-- | Applies a linear transformation to the incoming data:
-- \[
-- \mathrm{output} = \mathrm{input} \mathrm{weight}^{\intercal} + \mathrm{bias}.
-- \]
--
-- Supported shapes:
--
--     * 'input': \((N, \ldots, \mathrm{inputFeatures})\), where \(N\) is the batch size,
--     \(\ldots\) means any number of additional dimensions and
--     \(\mathrm{inputFeatures}\) are the input features.
--
--     * 'weight': \((\mathrm{outputFeatures}, \mathrm{inputFeatures})\)
--
--     * 'bias': \((\mathrm{outputFeatures})\)
--
--     * 'output': \((N, \ldots, \mathrm{outputFeatures})\)
--
-- Examples:
--
-- >>> type InputDim = 'Dim ('Name "input") ('Size 5)
-- >>> type OutputDim = 'Dim ('Name "output") ('Size 10)
-- >>> type BatchDim = 'Dim ('Name "batch") ('Size 20)
-- >>> type WeightShape = 'Shape '[OutputDim, InputDim]
-- >>> type BiasShape = 'Shape '[OutputDim]
-- >>> type InputShape = 'Shape '[BatchDim, InputDim]
-- >>> g <- generator @('Device 'CPU) 0
-- >>> (weight, g') = randn @'Independent @('Layout 'Dense) @('Device 'CPU) @('DataType 'Float) @WeightShape g
-- >>> (bias, g'') = randn @'Independent @('Layout 'Dense) @('Device 'CPU) @('DataType 'Float) @BiasShape g'
-- >>> (input, _) = randn @'Dependent @('Layout 'Dense) @('Device 'CPU) @('DataType 'Float) @InputShape g''
-- >>> result = linear weight bias input
-- >>> :type result
-- result
--   :: Tensor
--        'Dependent
--        ('Layout 'Dense)
--        ('Device 'CPU)
--        ('DataType 'Float)
--        ('Shape
--           '[ 'Dim ('Name "batch") ('Size 20),
--              'Dim ('Name "output") ('Size 10)])
linearWithBias ::
  forall requiresGradient layout device dataType shape requiresGradient' layout' device' dataType' shape' requiresGradient'' layout'' device'' dataType'' shape''.
  -- | weight
  Tensor requiresGradient layout device dataType shape ->
  -- | bias
  Tensor requiresGradient' layout' device' dataType' shape' ->
  -- | input
  Tensor requiresGradient'' layout'' device'' dataType'' shape'' ->
  -- | output
  Tensor
    (requiresGradient' <|> requiresGradient'' <|> requiresGradient'')
    (layout <+> (layout' <+> layout''))
    (device <+> (device' <+> device''))
    (dataType <+> (dataType' <+> dataType''))
    (LinearWithBiasF shape shape' shape'')
linearWithBias weight bias input = unsafePerformIO $ cast3 ATen.linear_ttt input weight bias

type family LinearWithoutBiasF (weightShape :: Shape [Dim (Name Symbol) (Size Nat)]) (inputShape :: Shape [Dim (Name Symbol) (Size Nat)]) :: Shape [Dim (Name Symbol) (Size Nat)] where
  LinearWithoutBiasF ( 'Shape '[]) _ = TypeError (LinearWeightDimsErrorMessage '[])
  LinearWithoutBiasF ( 'Shape '[weightDim]) _ = TypeError (LinearWeightDimsErrorMessage '[weightDim])
  LinearWithoutBiasF ( 'Shape (weightDim ': weightDim' ': weightDim'' ': weightDims)) _ = TypeError (LinearWeightDimsErrorMessage (weightDim ': weightDim' ': weightDim'' ': weightDims))
  LinearWithoutBiasF _ ( 'Shape '[]) = TypeError LinearInputDimsErrorMessage
  LinearWithoutBiasF ( 'Shape weightDims) ( 'Shape inputDims) = 'Shape (Reverse (LinearWithoutBiasDimsF weightDims (Reverse inputDims)))
  LinearWithoutBiasF 'UncheckedShape _ = 'UncheckedShape
  LinearWithoutBiasF _ 'UncheckedShape = 'UncheckedShape

type family LinearWithoutBiasDimsF (weightDims :: [Dim (Name Symbol) (Size Nat)]) (reversedInputDims :: [Dim (Name Symbol) (Size Nat)]) :: [Dim (Name Symbol) (Size Nat)] where
  LinearWithoutBiasDimsF '[outputDim, inputDim] (inputDim' ': reversedInputDims) = Seq (inputDim <+> inputDim') (outputDim ': reversedInputDims)

linearWithoutBias ::
  forall requiresGradient layout device dataType shape requiresGradient' layout' device' dataType' shape'.
  -- | weight
  Tensor requiresGradient layout device dataType shape ->
  -- | input
  Tensor requiresGradient' layout' device' dataType' shape' ->
  -- | output
  Tensor
    (requiresGradient <|> requiresGradient')
    (layout <+> layout')
    (device <+> device')
    (dataType <+> dataType')
    (LinearWithoutBiasF shape shape')
linearWithoutBias weight input = unsafePerformIO $ cast2 ATen.linear_tt input weight

testLinearWithoutBias ::
  Tensor
    'WithGradient
    ( 'Layout 'Dense)
    'UncheckedDevice
    ( 'DataType 'Float)
    ( 'Shape '[ 'Dim ( 'Name "output") ( 'Size 2)])
testLinearWithoutBias =
  let weight = undefined :: Tensor 'WithGradient ( 'Layout 'Dense) ( 'Device 'CPU) ( 'DataType 'Float) ( 'Shape '[ 'Dim ( 'Name "output") ( 'Size 2), 'Dim ( 'Name "input") ( 'Size 1)])
      input = undefined :: Tensor 'WithoutGradient ( 'Layout 'Dense) 'UncheckedDevice ( 'DataType 'Float) ( 'Shape '[ 'Dim ( 'Name "input") ( 'Size 1)])
   in linearWithoutBias weight input
