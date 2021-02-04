//===- LinalgInterface.h - Linalg operations interfaces -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the operation interfaces for Linalg operations.
//
//===----------------------------------------------------------------------===//

#ifndef MLIR_DIALECT_LINALG_IR_LINALGINTERFACES_H_
#define MLIR_DIALECT_LINALG_IR_LINALGINTERFACES_H_

#include "mlir/Dialect/Utils/StructuredOpsUtils.h"
#include "mlir/IR/AffineMap.h"
#include "mlir/IR/BlockAndValueMapping.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/ViewLikeInterface.h"

namespace mlir {
namespace linalg {

/// Returns the values obtained by applying `map` to the list of values.
SmallVector<Value, 4> applyMapToValues(OpBuilder &b, Location loc,
                                       AffineMap map, ValueRange values);

namespace detail {

/// Verify that `op` conforms to the invariants of StructuredOpInterface
LogicalResult verifyStructuredOpInterface(Operation *op);

} // namespace detail
} // namespace linalg
} // namespace mlir

#include "mlir/Dialect/Linalg/IR/LinalgStructuredOps.h.inc"

/// Include the generated interface declarations.
#include "mlir/Dialect/Linalg/IR/LinalgInterfaces.h.inc"

#endif // MLIR_DIALECT_LINALG_IR_LINALGINTERFACES_H_