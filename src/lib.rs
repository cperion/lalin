use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::immediates::{Ieee32, Ieee64};
use cranelift_codegen::ir::{
    AbiParam, AtomicRmwOp, Block, BlockArg, InstBuilder, MemFlags, Signature, StackSlot,
    StackSlotData, StackSlotKind, TrapCode, Type, UserFuncName, Value, types,
};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Switch};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{DataDescription, DataId, FuncId, Linkage, Module, default_libcall_names};
use cranelift_object::{ObjectBuilder, ObjectModule};
use std::collections::{HashMap, HashSet};
use std::error::Error;
use std::ffi::c_void;
use std::fmt;
use std::sync::{Arc, OnceLock};

pub mod host_arena;
pub mod lua_api;
pub mod ffi;

macro_rules! id_type {
    ($name:ident) => {
        #[derive(Clone, Debug, PartialEq, Eq, Hash)]
        pub struct $name(pub String);

        impl $name {
            pub fn new(text: impl Into<String>) -> Self {
                Self(text.into())
            }

            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl From<&str> for $name {
            fn from(value: &str) -> Self {
                Self(value.to_string())
            }
        }

        impl From<String> for $name {
            fn from(value: String) -> Self {
                Self(value)
            }
        }
    };
}

id_type!(BackSigId);
id_type!(BackFuncId);
id_type!(BackExternId);
id_type!(BackDataId);
id_type!(BackBlockId);
id_type!(BackValId);
id_type!(BackStackSlotId);
id_type!(BackAccessId);

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackSwitchCase {
    pub raw: String,
    pub dest: BackBlockId,
}

impl BackSwitchCase {
    pub fn new(raw: impl Into<String>, dest: BackBlockId) -> Self {
        Self {
            raw: raw.into(),
            dest,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackScalar {
    Bool,
    I8,
    I16,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    F32,
    F64,
    Ptr,
    Index,
}

impl BackScalar {
    fn clif_type(self, ptr_ty: Type) -> Type {
        match self {
            Self::Bool => types::I8,
            Self::I8 | Self::U8 => types::I8,
            Self::I16 | Self::U16 => types::I16,
            Self::I32 | Self::U32 => types::I32,
            Self::I64 | Self::U64 => types::I64,
            Self::F32 => types::F32,
            Self::F64 => types::F64,
            Self::Ptr | Self::Index => ptr_ty,
        }
    }

    fn byte_size(self, ptr_bytes: u32) -> u32 {
        match self {
            Self::Bool | Self::I8 | Self::U8 => 1,
            Self::I16 | Self::U16 => 2,
            Self::I32 | Self::U32 | Self::F32 => 4,
            Self::I64 | Self::U64 | Self::F64 => 8,
            Self::Ptr | Self::Index => ptr_bytes,
        }
    }

    fn supports_atomic(self) -> bool {
        !matches!(self, Self::F32 | Self::F64)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct BackVec {
    pub elem: BackScalar,
    pub lanes: u32,
}

impl BackVec {
    pub fn new(elem: BackScalar, lanes: u32) -> Self {
        Self { elem, lanes }
    }

    fn byte_size(self, ptr_bytes: u32) -> u32 {
        self.elem.byte_size(ptr_bytes).saturating_mul(self.lanes)
    }

    fn clif_type(self, ptr_ty: Type) -> Result<Type, MoonliftError> {
        if self.lanes < 2 || !self.lanes.is_power_of_two() {
            return Err(MoonliftError::new(format!(
                "vector lane count {} must be a power of two >= 2",
                self.lanes
            )));
        }
        let elem_ty = self.elem.clif_type(ptr_ty);
        elem_ty.by(self.lanes).ok_or_else(|| {
            MoonliftError::new(format!(
                "Cranelift cannot represent vector type {:?}x{}",
                self.elem, self.lanes
            ))
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackIntOverflow {
    Wrap,
    NoSignedWrap,
    NoUnsignedWrap,
    NoWrap,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackIntExact {
    MayLose,
    Exact,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackIntSemantics {
    pub overflow: BackIntOverflow,
    pub exact: BackIntExact,
}

impl BackIntSemantics {
    pub fn new(overflow: BackIntOverflow, exact: BackIntExact) -> Self {
        Self { overflow, exact }
    }

    pub fn wrapping() -> Self {
        Self { overflow: BackIntOverflow::Wrap, exact: BackIntExact::MayLose }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackFloatSemantics {
    Strict,
    FastMath,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackAlignment {
    Unknown,
    Known(u32),
    AtLeast(u32),
    Assumed(u32),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackDereference {
    Unknown,
    Bytes(u32),
    Assumed(u32),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackTrap {
    MayTrap,
    NonTrapping,
    Checked,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackMotion {
    MayNotMove,
    CanMove,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackAccessMode {
    Read,
    Write,
    ReadWrite,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackAtomicOrdering {
    SeqCst,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackAtomicRmwOp {
    Add,
    Sub,
    And,
    Or,
    Xor,
    Xchg,
}

impl BackAtomicRmwOp {
    fn clif(self) -> AtomicRmwOp {
        match self {
            Self::Add => AtomicRmwOp::Add,
            Self::Sub => AtomicRmwOp::Sub,
            Self::And => AtomicRmwOp::And,
            Self::Or => AtomicRmwOp::Or,
            Self::Xor => AtomicRmwOp::Xor,
            Self::Xchg => AtomicRmwOp::Xchg,
        }
    }

    fn supports_scalar(self, ty: BackScalar) -> bool {
        match self {
            Self::Xchg => ty.supports_atomic(),
            Self::Add | Self::Sub => matches!(ty, BackScalar::I8 | BackScalar::I16 | BackScalar::I32 | BackScalar::I64 | BackScalar::U8 | BackScalar::U16 | BackScalar::U32 | BackScalar::U64 | BackScalar::Index),
            Self::And | Self::Or | Self::Xor => matches!(ty, BackScalar::Bool | BackScalar::I8 | BackScalar::I16 | BackScalar::I32 | BackScalar::I64 | BackScalar::U8 | BackScalar::U16 | BackScalar::U32 | BackScalar::U64 | BackScalar::Index),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackMemoryInfo {
    pub access: BackAccessId,
    pub alignment: BackAlignment,
    pub dereference: BackDereference,
    pub trap: BackTrap,
    pub motion: BackMotion,
    pub mode: BackAccessMode,
}

impl BackMemoryInfo {
    pub fn new(
        access: BackAccessId,
        alignment: BackAlignment,
        dereference: BackDereference,
        trap: BackTrap,
        motion: BackMotion,
        mode: BackAccessMode,
    ) -> Self {
        Self { access, alignment, dereference, trap, motion, mode }
    }

    fn memflags(&self, access_bytes: u32, natural_align: u32) -> MemFlags {
        let mut flags = MemFlags::new();
        match self.trap {
            BackTrap::NonTrapping => flags.set_notrap(),
            BackTrap::Checked => {} // default MemFlags already has HEAP_OUT_OF_BOUNDS trap code
            BackTrap::MayTrap => {}
        }
        if matches!(self.motion, BackMotion::CanMove) {
            flags.set_can_move();
        }
        let align_bytes = match self.alignment {
            BackAlignment::Known(bytes) | BackAlignment::AtLeast(bytes) | BackAlignment::Assumed(bytes) => Some(bytes),
            BackAlignment::Unknown => None,
        };
        if align_bytes.is_some_and(|bytes| bytes >= natural_align && natural_align > 0) {
            flags.set_aligned();
        }
        if matches!(self.trap, BackTrap::MayTrap) {
            match self.dereference {
                BackDereference::Bytes(bytes) | BackDereference::Assumed(bytes) if bytes >= access_bytes => flags.set_notrap(),
                _ => {}
            }
        }
        flags
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackCmd {
    CreateSig(BackSigId, Vec<BackScalar>, Vec<BackScalar>),
    DeclareData(BackDataId, u32, u32),
    DataInitZero(BackDataId, u32, u32),
    DataInitInt(BackDataId, u32, BackScalar, String),
    DataInitFloat(BackDataId, u32, BackScalar, String),
    DataInitBool(BackDataId, u32, bool),
    DataAddr(BackValId, BackDataId),
    FuncAddr(BackValId, BackFuncId),
    ExternAddr(BackValId, BackExternId),
    DeclareFuncLocal(BackFuncId, BackSigId),
    DeclareFuncExport(BackFuncId, BackSigId),
    DeclareFuncExtern(BackExternId, String, BackSigId),
    BeginFunc(BackFuncId),
    CreateBlock(BackBlockId),
    SwitchToBlock(BackBlockId),
    SealBlock(BackBlockId),
    BindEntryParams(BackBlockId, Vec<BackValId>),
    AppendBlockParam(BackBlockId, BackValId, BackScalar),
    AppendVecBlockParam(BackBlockId, BackValId, BackVec),
    CreateStackSlot(BackStackSlotId, u32, u32),
    Alias(BackValId, BackValId),
    StackAddr(BackValId, BackStackSlotId),
    ConstInt(BackValId, BackScalar, String),
    ConstFloat(BackValId, BackScalar, String),
    ConstBool(BackValId, bool),
    ConstNull(BackValId),
    Ineg(BackValId, BackScalar, BackValId),
    Fneg(BackValId, BackScalar, BackValId),
    Bnot(BackValId, BackScalar, BackValId),
    BoolNot(BackValId, BackValId),
    Popcount(BackValId, BackScalar, BackValId),
    Clz(BackValId, BackScalar, BackValId),
    Ctz(BackValId, BackScalar, BackValId),
    Bswap(BackValId, BackScalar, BackValId),
    Sqrt(BackValId, BackScalar, BackValId),
    Abs(BackValId, BackScalar, BackValId),
    Floor(BackValId, BackScalar, BackValId),
    Ceil(BackValId, BackScalar, BackValId),
    TruncFloat(BackValId, BackScalar, BackValId),
    Round(BackValId, BackScalar, BackValId),
    Iadd(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Isub(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Imul(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Fadd(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fsub(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fmul(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Sdiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Udiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Fdiv(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Srem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Urem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Band(BackValId, BackScalar, BackValId, BackValId),
    Bor(BackValId, BackScalar, BackValId, BackValId),
    Bxor(BackValId, BackScalar, BackValId, BackValId),
    Ishl(BackValId, BackScalar, BackValId, BackValId),
    Ushr(BackValId, BackScalar, BackValId, BackValId),
    Sshr(BackValId, BackScalar, BackValId, BackValId),
    Rotl(BackValId, BackScalar, BackValId, BackValId),
    Rotr(BackValId, BackScalar, BackValId, BackValId),
    IcmpEq(BackValId, BackScalar, BackValId, BackValId),
    IcmpNe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    FCmpEq(BackValId, BackScalar, BackValId, BackValId),
    FCmpNe(BackValId, BackScalar, BackValId, BackValId),
    FCmpLt(BackValId, BackScalar, BackValId, BackValId),
    FCmpLe(BackValId, BackScalar, BackValId, BackValId),
    FCmpGt(BackValId, BackScalar, BackValId, BackValId),
    FCmpGe(BackValId, BackScalar, BackValId, BackValId),
    Bitcast(BackValId, BackScalar, BackValId),
    Ireduce(BackValId, BackScalar, BackValId),
    Sextend(BackValId, BackScalar, BackValId),
    Uextend(BackValId, BackScalar, BackValId),
    Fpromote(BackValId, BackScalar, BackValId),
    Fdemote(BackValId, BackScalar, BackValId),
    SToF(BackValId, BackScalar, BackValId),
    UToF(BackValId, BackScalar, BackValId),
    FToS(BackValId, BackScalar, BackValId),
    FToU(BackValId, BackScalar, BackValId),
    PtrAdd(BackValId, BackValId, BackValId),
    PtrOffset(BackValId, BackValId, BackValId, u32, i64),
    LoadInfo(BackValId, BackScalar, BackValId, BackMemoryInfo),
    StoreInfo(BackScalar, BackValId, BackValId, BackMemoryInfo),
    AtomicLoad(BackValId, BackScalar, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicStore(BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicRmw(BackValId, BackAtomicRmwOp, BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicCas(BackValId, BackScalar, BackValId, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicFence(BackAtomicOrdering),
    Memcpy(BackValId, BackValId, BackValId),
    Memset(BackValId, BackValId, BackValId),
    Select(BackValId, BackScalar, BackValId, BackValId, BackValId),
    Fma(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId, BackValId),
    VecSplat(BackValId, BackVec, BackValId),
    VecIcmpEq(BackValId, BackVec, BackValId, BackValId),
    VecIcmpNe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGe(BackValId, BackVec, BackValId, BackValId),
    VecSelect(BackValId, BackVec, BackValId, BackValId, BackValId),
    VecMaskNot(BackValId, BackVec, BackValId),
    VecMaskAnd(BackValId, BackVec, BackValId, BackValId),
    VecMaskOr(BackValId, BackVec, BackValId, BackValId),
    VecIadd(BackValId, BackVec, BackValId, BackValId),
    VecIsub(BackValId, BackVec, BackValId, BackValId),
    VecImul(BackValId, BackVec, BackValId, BackValId),
    VecBand(BackValId, BackVec, BackValId, BackValId),
    VecBor(BackValId, BackVec, BackValId, BackValId),
    VecBxor(BackValId, BackVec, BackValId, BackValId),
    VecLoadInfo(BackValId, BackVec, BackValId, BackMemoryInfo),
    VecStoreInfo(BackVec, BackValId, BackValId, BackMemoryInfo),
    VecInsertLane(BackValId, BackVec, BackValId, BackValId, u32),
    VecExtractLane(BackValId, BackScalar, BackValId, u32),
    CallValueDirect(BackValId, BackScalar, BackFuncId, BackSigId, Vec<BackValId>),
    CallStmtDirect(BackFuncId, BackSigId, Vec<BackValId>),
    CallValueExtern(BackValId, BackScalar, BackExternId, BackSigId, Vec<BackValId>),
    CallStmtExtern(BackExternId, BackSigId, Vec<BackValId>),
    CallValueIndirect(BackValId, BackScalar, BackValId, BackSigId, Vec<BackValId>),
    CallStmtIndirect(BackValId, BackSigId, Vec<BackValId>),
    Jump(BackBlockId, Vec<BackValId>),
    BrIf(BackValId, BackBlockId, Vec<BackValId>, BackBlockId, Vec<BackValId>),
    SwitchInt(BackValId, BackScalar, Vec<BackSwitchCase>, BackBlockId),
    ReturnVoid,
    ReturnValue(BackValId),
    Trap,
    FinishFunc(BackFuncId),
    FinalizeModule,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackDeclCmd {
    CreateSig(BackSigId, Vec<BackScalar>, Vec<BackScalar>),
    DeclareData(BackDataId, u32, u32),
    DataInitZero(BackDataId, u32, u32),
    DataInitInt(BackDataId, u32, BackScalar, String),
    DataInitFloat(BackDataId, u32, BackScalar, String),
    DataInitBool(BackDataId, u32, bool),
    DeclareFuncLocal(BackFuncId, BackSigId),
    DeclareFuncExport(BackFuncId, BackSigId),
    DeclareFuncExtern(BackExternId, String, BackSigId),
    BeginFunc(BackFuncId),
    FinishFunc(BackFuncId),
    FinalizeModule,
}

// ── CFG Scaffolding ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CfgOp {
    CreateBlock(BackBlockId),
    SwitchToBlock(BackBlockId),
    SealBlock(BackBlockId),
    BindEntryParams(BackBlockId, Vec<BackValId>),
    AppendBlockParam(BackBlockId, BackValId, BackScalar),
    AppendVecBlockParam(BackBlockId, BackValId, BackVec),
    CreateStackSlot(BackStackSlotId, u32, u32),
}

// ── Address ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AddressOp {
    DataAddr(BackValId, BackDataId),
    FuncAddr(BackValId, BackFuncId),
    ExternAddr(BackValId, BackExternId),
    StackAddr(BackValId, BackStackSlotId),
}

// ── Constants ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConstOp {
    ConstInt(BackValId, BackScalar, String),
    ConstFloat(BackValId, BackScalar, String),
    ConstBool(BackValId, bool),
    ConstNull(BackValId),
}

// ── Scalar Unary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ScalarUnaryOp {
    Ineg(BackValId, BackScalar, BackValId),
    Fneg(BackValId, BackScalar, BackValId),
    Bnot(BackValId, BackScalar, BackValId),
    BoolNot(BackValId, BackValId),   // 2 fields — intentionally no BackScalar
}

// ── Intrinsics ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum IntrinsicOp {
    Popcount(BackValId, BackScalar, BackValId),
    Clz(BackValId, BackScalar, BackValId),
    Ctz(BackValId, BackScalar, BackValId),
    Bswap(BackValId, BackScalar, BackValId),
    Sqrt(BackValId, BackScalar, BackValId),
    Abs(BackValId, BackScalar, BackValId),
    Floor(BackValId, BackScalar, BackValId),
    Ceil(BackValId, BackScalar, BackValId),
    TruncFloat(BackValId, BackScalar, BackValId),
    Round(BackValId, BackScalar, BackValId),
}

// ── Integer Binary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum IntBinaryOp {
    Iadd(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Isub(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Imul(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Sdiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Udiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Srem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Urem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
}

// ── Float Binary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FloatBinaryOp {
    Fadd(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fsub(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fmul(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fdiv(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
}

// ── Bitwise ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BitwiseOp {
    Band(BackValId, BackScalar, BackValId, BackValId),
    Bor(BackValId, BackScalar, BackValId, BackValId),
    Bxor(BackValId, BackScalar, BackValId, BackValId),
}

// ── Shift ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ShiftOp {
    Ishl(BackValId, BackScalar, BackValId, BackValId),
    Ushr(BackValId, BackScalar, BackValId, BackValId),
    Sshr(BackValId, BackScalar, BackValId, BackValId),
}

// ── Rotate ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RotateOp {
    Rotl(BackValId, BackScalar, BackValId, BackValId),
    Rotr(BackValId, BackScalar, BackValId, BackValId),
}

// ── Compare ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CompareOp {
    IcmpEq(BackValId, BackScalar, BackValId, BackValId),
    IcmpNe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    FCmpEq(BackValId, BackScalar, BackValId, BackValId),
    FCmpNe(BackValId, BackScalar, BackValId, BackValId),
    FCmpLt(BackValId, BackScalar, BackValId, BackValId),
    FCmpLe(BackValId, BackScalar, BackValId, BackValId),
    FCmpGt(BackValId, BackScalar, BackValId, BackValId),
    FCmpGe(BackValId, BackScalar, BackValId, BackValId),
}

// ── Cast ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CastOp {
    Bitcast(BackValId, BackScalar, BackValId),
    Ireduce(BackValId, BackScalar, BackValId),
    Sextend(BackValId, BackScalar, BackValId),
    Uextend(BackValId, BackScalar, BackValId),
    Fpromote(BackValId, BackScalar, BackValId),
    Fdemote(BackValId, BackScalar, BackValId),
    SToF(BackValId, BackScalar, BackValId),
    UToF(BackValId, BackScalar, BackValId),
    FToS(BackValId, BackScalar, BackValId),
    FToU(BackValId, BackScalar, BackValId),
}

// ── Pointer ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PtrOp {
    PtrAdd(BackValId, BackValId, BackValId),
    PtrOffset(BackValId, BackValId, BackValId, u32, i64),
}

// ── Memory ────
// NOTE: Address synthesis commands (StackAddr, DataAddr, PtrAdd) are in AddressOp/PtrOp,
// NOT in MemoryOp. This sub-enum covers only Load/Store/Atomic operations.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MemoryOp {
    LoadInfo(BackValId, BackScalar, BackValId, BackMemoryInfo),
    StoreInfo(BackScalar, BackValId, BackValId, BackMemoryInfo),
    AtomicLoad(BackValId, BackScalar, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicStore(BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicRmw(BackValId, BackAtomicRmwOp, BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicCas(BackValId, BackScalar, BackValId, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicFence(BackAtomicOrdering),
    Memcpy(BackValId, BackValId, BackValId),
    Memset(BackValId, BackValId, BackValId),
}

// ── Call ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CallOp {
    CallValueDirect(BackValId, BackScalar, BackFuncId, BackSigId, Vec<BackValId>),
    CallStmtDirect(BackFuncId, BackSigId, Vec<BackValId>),
    CallValueExtern(BackValId, BackScalar, BackExternId, BackSigId, Vec<BackValId>),
    CallStmtExtern(BackExternId, BackSigId, Vec<BackValId>),
    CallValueIndirect(BackValId, BackScalar, BackValId, BackSigId, Vec<BackValId>),
    CallStmtIndirect(BackValId, BackSigId, Vec<BackValId>),
}

// ── Control Flow ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ControlOp {
    Jump(BackBlockId, Vec<BackValId>),
    BrIf(BackValId, BackBlockId, Vec<BackValId>, BackBlockId, Vec<BackValId>),
    SwitchInt(BackValId, BackScalar, Vec<BackSwitchCase>, BackBlockId),
    ReturnVoid,
    ReturnValue(BackValId),
    Trap,
}

// ── Vector Unary/Ternary ────
// NOTE: VecMaskNot is unary (3 fields), VecMaskAnd/VecMaskOr are binary (4 fields) —
// the different arity is fine since Rust enum variants can differ in shape.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecUnaryOp {
    VecSplat(BackValId, BackVec, BackValId),
    VecSelect(BackValId, BackVec, BackValId, BackValId, BackValId),
    VecInsertLane(BackValId, BackVec, BackValId, BackValId, u32),
    VecExtractLane(BackValId, BackScalar, BackValId, u32),
    VecMaskNot(BackValId, BackVec, BackValId),
}

// ── Vector Binary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecBinaryOp {
    VecIadd(BackValId, BackVec, BackValId, BackValId),
    VecIsub(BackValId, BackVec, BackValId, BackValId),
    VecImul(BackValId, BackVec, BackValId, BackValId),
    VecBand(BackValId, BackVec, BackValId, BackValId),
    VecBor(BackValId, BackVec, BackValId, BackValId),
    VecBxor(BackValId, BackVec, BackValId, BackValId),
    VecMaskAnd(BackValId, BackVec, BackValId, BackValId),
    VecMaskOr(BackValId, BackVec, BackValId, BackValId),
}

// ── Vector Compare ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecCompareOp {
    VecIcmpEq(BackValId, BackVec, BackValId, BackValId),
    VecIcmpNe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGe(BackValId, BackVec, BackValId, BackValId),
}

// ── Vector Memory ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecMemoryOp {
    VecLoadInfo(BackValId, BackVec, BackValId, BackMemoryInfo),
    VecStoreInfo(BackVec, BackValId, BackValId, BackMemoryInfo),
}

// ── Singleton (ungrouped) ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OtherOp {
    Alias(BackValId, BackValId),
    Select(BackValId, BackScalar, BackValId, BackValId, BackValId),
    Fma(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId, BackValId),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackBodyCmd {
    Cfg(CfgOp),
    Address(AddressOp),
    Const(ConstOp),
    Unary(ScalarUnaryOp),
    Intrinsic(IntrinsicOp),
    IntBinary(IntBinaryOp),
    FloatBinary(FloatBinaryOp),
    Bitwise(BitwiseOp),
    Shift(ShiftOp),
    Rotate(RotateOp),
    Compare(CompareOp),
    Cast(CastOp),
    Ptr(PtrOp),
    Memory(MemoryOp),
    Call(CallOp),
    Control(ControlOp),
    VecUnary(VecUnaryOp),
    VecBinary(VecBinaryOp),
    VecCompare(VecCompareOp),
    VecMemory(VecMemoryOp),
    Other(OtherOp),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackProgram {
    pub decls: Vec<BackDeclCmd>,
    pub bodies: Vec<(BackFuncId, Vec<BackBodyCmd>)>,
}

impl BackProgram {
    pub fn new(decls: Vec<BackDeclCmd>, bodies: Vec<(BackFuncId, Vec<BackBodyCmd>)>) -> Self {
        Self { decls, bodies }
    }

    pub fn partition(cmds: Vec<BackCmd>) -> Result<Self, MoonliftError> {
        let mut decls: Vec<BackDeclCmd> = Vec::new();
        let mut bodies: Vec<(BackFuncId, Vec<BackBodyCmd>)> = Vec::new();
        let mut current_func: Option<BackFuncId> = None;
        let mut current_cmds: Vec<BackBodyCmd> = Vec::new();

        for cmd in cmds {
            match cmd {
                BackCmd::CreateSig(a, b, c) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("CreateSig cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::CreateSig(a, b, c));
                }
                BackCmd::DeclareData(a, b, c) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DeclareData cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DeclareData(a, b, c));
                }
                BackCmd::DataInitZero(a, b, c) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DataInitZero cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DataInitZero(a, b, c));
                }
                BackCmd::DataInitInt(a, b, c, d) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DataInitInt cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DataInitInt(a, b, c, d));
                }
                BackCmd::DataInitFloat(a, b, c, d) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DataInitFloat cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DataInitFloat(a, b, c, d));
                }
                BackCmd::DataInitBool(a, b, c) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DataInitBool cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DataInitBool(a, b, c));
                }
                BackCmd::DataAddr(a, b) => {
                    if current_func.is_none() {
                        return Err(MoonliftError::new("DataAddr cannot appear at module top level".to_string()));
                    }
                    current_cmds.push(BackBodyCmd::Address(AddressOp::DataAddr(a, b)));
                }
                BackCmd::FuncAddr(a, b) => {
                    if current_func.is_none() {
                        return Err(MoonliftError::new("FuncAddr cannot appear at module top level".to_string()));
                    }
                    current_cmds.push(BackBodyCmd::Address(AddressOp::FuncAddr(a, b)));
                }
                BackCmd::ExternAddr(a, b) => {
                    if current_func.is_none() {
                        return Err(MoonliftError::new("ExternAddr cannot appear at module top level".to_string()));
                    }
                    current_cmds.push(BackBodyCmd::Address(AddressOp::ExternAddr(a, b)));
                }
                BackCmd::DeclareFuncLocal(a, b) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DeclareFuncLocal cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DeclareFuncLocal(a, b));
                }
                BackCmd::DeclareFuncExport(a, b) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DeclareFuncExport cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DeclareFuncExport(a, b));
                }
                BackCmd::DeclareFuncExtern(a, b, c) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("DeclareFuncExtern cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::DeclareFuncExtern(a, b, c));
                }
                BackCmd::BeginFunc(func) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new(format!(
                            "nested BeginFunc for '{}' is not allowed",
                            func.as_str()
                        )));
                    }
                    if bodies.iter().any(|(id, _)| id == &func) {
                        return Err(MoonliftError::new(format!(
                            "duplicate BeginFunc for '{}'",
                            func.as_str()
                        )));
                    }
                    decls.push(BackDeclCmd::BeginFunc(func.clone()));
                    current_func = Some(func);
                    current_cmds.clear();
                }
                BackCmd::FinishFunc(func) => {
                    let open = current_func.take().ok_or_else(|| {
                        MoonliftError::new(format!(
                            "FinishFunc('{}') appears outside any function body",
                            func.as_str()
                        ))
                    })?;
                    if open != func {
                        return Err(MoonliftError::new(format!(
                            "FinishFunc('{}') closes '{}', expected matching function id",
                            func.as_str(),
                            open.as_str()
                        )));
                    }
                    decls.push(BackDeclCmd::FinishFunc(func));
                    bodies.push((open, std::mem::take(&mut current_cmds)));
                }
                BackCmd::FinalizeModule => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new("FinalizeModule cannot appear inside a function body".to_string()));
                    }
                    decls.push(BackDeclCmd::FinalizeModule);
                }
                BackCmd::CreateBlock(a) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::CreateBlock(a))),
                BackCmd::SwitchToBlock(a) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::SwitchToBlock(a))),
                BackCmd::SealBlock(a) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::SealBlock(a))),
                BackCmd::BindEntryParams(a, b) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::BindEntryParams(a, b))),
                BackCmd::AppendBlockParam(a, b, c) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::AppendBlockParam(a, b, c))),
                BackCmd::AppendVecBlockParam(a, b, c) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::AppendVecBlockParam(a, b, c))),
                BackCmd::CreateStackSlot(a, b, c) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::CreateStackSlot(a, b, c))),
                BackCmd::Alias(a, b) => current_cmds.push(BackBodyCmd::Other(OtherOp::Alias(a, b))),
                BackCmd::StackAddr(a, b) => current_cmds.push(BackBodyCmd::Address(AddressOp::StackAddr(a, b))),
                BackCmd::ConstInt(a, b, c) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstInt(a, b, c))),
                BackCmd::ConstFloat(a, b, c) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstFloat(a, b, c))),
                BackCmd::ConstBool(a, b) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstBool(a, b))),
                BackCmd::ConstNull(a) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstNull(a))),
                BackCmd::Ineg(a, b, c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Ineg(a, b, c))),
                BackCmd::Fneg(a, b, c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Fneg(a, b, c))),
                BackCmd::Bnot(a, b, c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Bnot(a, b, c))),
                BackCmd::BoolNot(a, b) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::BoolNot(a, b))),
                BackCmd::Popcount(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Popcount(a, b, c))),
                BackCmd::Clz(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Clz(a, b, c))),
                BackCmd::Ctz(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Ctz(a, b, c))),
                BackCmd::Bswap(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Bswap(a, b, c))),
                BackCmd::Sqrt(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Sqrt(a, b, c))),
                BackCmd::Abs(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Abs(a, b, c))),
                BackCmd::Floor(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Floor(a, b, c))),
                BackCmd::Ceil(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Ceil(a, b, c))),
                BackCmd::TruncFloat(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::TruncFloat(a, b, c))),
                BackCmd::Round(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Round(a, b, c))),
                BackCmd::Iadd(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Iadd(a, b, c, d, e))),
                BackCmd::Isub(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Isub(a, b, c, d, e))),
                BackCmd::Imul(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Imul(a, b, c, d, e))),
                BackCmd::Sdiv(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Sdiv(a, b, c, d, e))),
                BackCmd::Udiv(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Udiv(a, b, c, d, e))),
                BackCmd::Srem(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Srem(a, b, c, d, e))),
                BackCmd::Urem(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Urem(a, b, c, d, e))),
                BackCmd::Fadd(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fadd(a, b, c, d, e))),
                BackCmd::Fsub(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fsub(a, b, c, d, e))),
                BackCmd::Fmul(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fmul(a, b, c, d, e))),
                BackCmd::Fdiv(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fdiv(a, b, c, d, e))),
                BackCmd::Band(a, b, c, d) => current_cmds.push(BackBodyCmd::Bitwise(BitwiseOp::Band(a, b, c, d))),
                BackCmd::Bor(a, b, c, d) => current_cmds.push(BackBodyCmd::Bitwise(BitwiseOp::Bor(a, b, c, d))),
                BackCmd::Bxor(a, b, c, d) => current_cmds.push(BackBodyCmd::Bitwise(BitwiseOp::Bxor(a, b, c, d))),
                BackCmd::Ishl(a, b, c, d) => current_cmds.push(BackBodyCmd::Shift(ShiftOp::Ishl(a, b, c, d))),
                BackCmd::Ushr(a, b, c, d) => current_cmds.push(BackBodyCmd::Shift(ShiftOp::Ushr(a, b, c, d))),
                BackCmd::Sshr(a, b, c, d) => current_cmds.push(BackBodyCmd::Shift(ShiftOp::Sshr(a, b, c, d))),
                BackCmd::Rotl(a, b, c, d) => current_cmds.push(BackBodyCmd::Rotate(RotateOp::Rotl(a, b, c, d))),
                BackCmd::Rotr(a, b, c, d) => current_cmds.push(BackBodyCmd::Rotate(RotateOp::Rotr(a, b, c, d))),
                BackCmd::IcmpEq(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::IcmpEq(a, b, c, d))),
                BackCmd::IcmpNe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::IcmpNe(a, b, c, d))),
                BackCmd::SIcmpLt(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::SIcmpLt(a, b, c, d))),
                BackCmd::SIcmpLe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::SIcmpLe(a, b, c, d))),
                BackCmd::SIcmpGt(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::SIcmpGt(a, b, c, d))),
                BackCmd::SIcmpGe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::SIcmpGe(a, b, c, d))),
                BackCmd::UIcmpLt(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::UIcmpLt(a, b, c, d))),
                BackCmd::UIcmpLe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::UIcmpLe(a, b, c, d))),
                BackCmd::UIcmpGt(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::UIcmpGt(a, b, c, d))),
                BackCmd::UIcmpGe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::UIcmpGe(a, b, c, d))),
                BackCmd::FCmpEq(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::FCmpEq(a, b, c, d))),
                BackCmd::FCmpNe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::FCmpNe(a, b, c, d))),
                BackCmd::FCmpLt(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::FCmpLt(a, b, c, d))),
                BackCmd::FCmpLe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::FCmpLe(a, b, c, d))),
                BackCmd::FCmpGt(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::FCmpGt(a, b, c, d))),
                BackCmd::FCmpGe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::FCmpGe(a, b, c, d))),
                BackCmd::Bitcast(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Bitcast(a, b, c))),
                BackCmd::Ireduce(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Ireduce(a, b, c))),
                BackCmd::Sextend(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Sextend(a, b, c))),
                BackCmd::Uextend(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Uextend(a, b, c))),
                BackCmd::Fpromote(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Fpromote(a, b, c))),
                BackCmd::Fdemote(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Fdemote(a, b, c))),
                BackCmd::SToF(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::SToF(a, b, c))),
                BackCmd::UToF(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::UToF(a, b, c))),
                BackCmd::FToS(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::FToS(a, b, c))),
                BackCmd::FToU(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::FToU(a, b, c))),
                BackCmd::PtrAdd(a, b, c) => current_cmds.push(BackBodyCmd::Ptr(PtrOp::PtrAdd(a, b, c))),
                BackCmd::PtrOffset(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Ptr(PtrOp::PtrOffset(a, b, c, d, e))),
                BackCmd::LoadInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::LoadInfo(a, b, c, d))),
                BackCmd::StoreInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::StoreInfo(a, b, c, d))),
                BackCmd::AtomicLoad(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicLoad(a, b, c, d, e))),
                BackCmd::AtomicStore(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicStore(a, b, c, d, e))),
                BackCmd::AtomicRmw(a, b, c, d, e, f, g) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicRmw(a, b, c, d, e, f, g))),
                BackCmd::AtomicCas(a, b, c, d, e, f, g) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicCas(a, b, c, d, e, f, g))),
                BackCmd::AtomicFence(a) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicFence(a))),
                BackCmd::Memcpy(a, b, c) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::Memcpy(a, b, c))),
                BackCmd::Memset(a, b, c) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::Memset(a, b, c))),
                BackCmd::Select(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Other(OtherOp::Select(a, b, c, d, e))),
                BackCmd::Fma(a, b, c, d, e, f) => current_cmds.push(BackBodyCmd::Other(OtherOp::Fma(a, b, c, d, e, f))),
                BackCmd::VecSplat(a, b, c) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecSplat(a, b, c))),
                BackCmd::VecIcmpEq(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecIcmpEq(a, b, c, d))),
                BackCmd::VecIcmpNe(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecIcmpNe(a, b, c, d))),
                BackCmd::VecSIcmpLt(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecSIcmpLt(a, b, c, d))),
                BackCmd::VecSIcmpLe(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecSIcmpLe(a, b, c, d))),
                BackCmd::VecSIcmpGt(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecSIcmpGt(a, b, c, d))),
                BackCmd::VecSIcmpGe(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecSIcmpGe(a, b, c, d))),
                BackCmd::VecUIcmpLt(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecUIcmpLt(a, b, c, d))),
                BackCmd::VecUIcmpLe(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecUIcmpLe(a, b, c, d))),
                BackCmd::VecUIcmpGt(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecUIcmpGt(a, b, c, d))),
                BackCmd::VecUIcmpGe(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecUIcmpGe(a, b, c, d))),
                BackCmd::VecSelect(a, b, c, d, e) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecSelect(a, b, c, d, e))),
                BackCmd::VecMaskNot(a, b, c) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecMaskNot(a, b, c))),
                BackCmd::VecMaskAnd(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecMaskAnd(a, b, c, d))),
                BackCmd::VecMaskOr(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecMaskOr(a, b, c, d))),
                BackCmd::VecIadd(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecIadd(a, b, c, d))),
                BackCmd::VecIsub(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecIsub(a, b, c, d))),
                BackCmd::VecImul(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecImul(a, b, c, d))),
                BackCmd::VecBand(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecBand(a, b, c, d))),
                BackCmd::VecBor(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecBor(a, b, c, d))),
                BackCmd::VecBxor(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecBxor(a, b, c, d))),
                BackCmd::VecLoadInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::VecMemory(VecMemoryOp::VecLoadInfo(a, b, c, d))),
                BackCmd::VecStoreInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::VecMemory(VecMemoryOp::VecStoreInfo(a, b, c, d))),
                BackCmd::VecInsertLane(a, b, c, d, e) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecInsertLane(a, b, c, d, e))),
                BackCmd::VecExtractLane(a, b, c, d) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecExtractLane(a, b, c, d))),
                BackCmd::CallValueDirect(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Call(CallOp::CallValueDirect(a, b, c, d, e))),
                BackCmd::CallStmtDirect(a, b, c) => current_cmds.push(BackBodyCmd::Call(CallOp::CallStmtDirect(a, b, c))),
                BackCmd::CallValueExtern(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Call(CallOp::CallValueExtern(a, b, c, d, e))),
                BackCmd::CallStmtExtern(a, b, c) => current_cmds.push(BackBodyCmd::Call(CallOp::CallStmtExtern(a, b, c))),
                BackCmd::CallValueIndirect(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Call(CallOp::CallValueIndirect(a, b, c, d, e))),
                BackCmd::CallStmtIndirect(a, b, c) => current_cmds.push(BackBodyCmd::Call(CallOp::CallStmtIndirect(a, b, c))),
                BackCmd::Jump(a, b) => current_cmds.push(BackBodyCmd::Control(ControlOp::Jump(a, b))),
                BackCmd::BrIf(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Control(ControlOp::BrIf(a, b, c, d, e))),
                BackCmd::SwitchInt(a, b, c, d) => current_cmds.push(BackBodyCmd::Control(ControlOp::SwitchInt(a, b, c, d))),
                BackCmd::ReturnVoid => current_cmds.push(BackBodyCmd::Control(ControlOp::ReturnVoid)),
                BackCmd::ReturnValue(a) => current_cmds.push(BackBodyCmd::Control(ControlOp::ReturnValue(a))),
                BackCmd::Trap => current_cmds.push(BackBodyCmd::Control(ControlOp::Trap)),
            }
        }

        if let Some(func) = current_func {
            return Err(MoonliftError::new(format!(
                "unterminated function body for '{}'",
                func.as_str()
            )));
        }

        Ok(Self { decls, bodies })
    }
}

#[derive(Debug)]
pub struct MoonliftError(pub String);

impl MoonliftError {
    fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for MoonliftError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Error for MoonliftError {}

fn switch_int_bits(ty: BackScalar, ptr_ty: Type) -> Result<u8, MoonliftError> {
    match ty {
        BackScalar::Bool | BackScalar::I8 | BackScalar::U8 => Ok(8),
        BackScalar::I16 | BackScalar::U16 => Ok(16),
        BackScalar::I32 | BackScalar::U32 => Ok(32),
        BackScalar::I64 | BackScalar::U64 => Ok(64),
        BackScalar::Index => Ok(ptr_ty.bits() as u8),
        _ => Err(MoonliftError::new(format!(
            "BackCmdSwitchInt requires bool/integer/index type, got {:?}",
            ty
        ))),
    }
}

fn mask_to_bits(value: u128, bits: u8) -> u128 {
    if bits >= 128 {
        value
    } else {
        value & ((1u128 << bits) - 1)
    }
}

fn parse_switch_int_case(raw: &str, ty: BackScalar, ptr_ty: Type) -> Result<u128, MoonliftError> {
    let bits = switch_int_bits(ty, ptr_ty)?;
    match ty {
        BackScalar::Bool => match raw {
            "0" => Ok(0),
            "1" => Ok(1),
            _ => Err(MoonliftError::new(format!(
                "BackCmdSwitchInt bool case must be '0' or '1', got '{}'",
                raw
            ))),
        },
        BackScalar::I8 | BackScalar::I16 | BackScalar::I32 | BackScalar::I64 => {
            let value = raw.parse::<i128>().map_err(|e| {
                MoonliftError::new(format!("could not parse signed switch case '{}': {}", raw, e))
            })?;
            Ok(mask_to_bits(value as u128, bits))
        }
        BackScalar::U8 | BackScalar::U16 | BackScalar::U32 | BackScalar::U64 | BackScalar::Index => {
            let value = raw.parse::<u128>().map_err(|e| {
                MoonliftError::new(format!("could not parse unsigned switch case '{}': {}", raw, e))
            })?;
            Ok(mask_to_bits(value, bits))
        }
        _ => Err(MoonliftError::new(format!(
            "BackCmdSwitchInt requires bool/integer/index type, got {:?}",
            ty
        ))),
    }
}

pub struct Jit {
    symbols: HashMap<String, *const u8>,
}

impl Jit {
    pub fn new() -> Self {
        Self {
            symbols: HashMap::new(),
        }
    }

    pub fn symbol(&mut self, name: impl Into<String>, ptr: *const u8) {
        self.symbols.insert(name.into(), ptr);
    }

    pub fn compile(&self, program: &BackProgram) -> Result<Artifact, MoonliftError> {
        let compiler = Compiler::new(&self.symbols)?;
        compiler.compile(program)
    }

    pub fn compile_tape(&self, payload: &str) -> Result<Artifact, MoonliftError> {
        let cmds = ffi::parse_back_command_tape(payload)?;
        let program = BackProgram::partition(cmds)?;
        self.compile(&program)
    }

    pub fn compile_binary(&self, payload: &[u8]) -> Result<Artifact, MoonliftError> {
        let cmds = ffi::parse_back_command_binary(payload)?;
        let program = BackProgram::partition(cmds)?;
        self.compile(&program)
    }
}

pub fn compile_object_binary(payload: &[u8], module_name: &str) -> Result<ObjectArtifact, MoonliftError> {
    let cmds = ffi::parse_back_command_binary(payload)?;
    let program = BackProgram::partition(cmds)?;
    compile_object(&program, module_name)
}

impl Default for Jit {
    fn default() -> Self {
        Self::new()
    }
}

pub struct Artifact {
    _module: JITModule,
    function_ptrs: HashMap<BackFuncId, *const u8>,
}

pub struct ObjectArtifact {
    bytes: Vec<u8>,
}

impl ObjectArtifact {
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn into_bytes(self) -> Vec<u8> {
        self.bytes
    }
}

pub fn compile_object(program: &BackProgram, module_name: &str) -> Result<ObjectArtifact, MoonliftError> {
    let compiler = Compiler::new_object(module_name)?;
    compiler.compile_object(program)
}

impl Artifact {
    pub fn getpointer(&self, func: &BackFuncId) -> Result<*const c_void, MoonliftError> {
        let ptr = self
            .function_ptrs
            .get(func)
            .copied()
            .ok_or_else(|| MoonliftError::new(format!("unknown compiled function id '{}'", func.as_str())))?;
        Ok(ptr.cast())
    }

    pub fn getpointer_by_name(&self, func: &str) -> Result<*const c_void, MoonliftError> {
        self.getpointer(&BackFuncId::from(func))
    }

    pub fn free(self) {}

    pub fn contains_function(&self, func: &BackFuncId) -> bool {
        self.function_ptrs.contains_key(func)
    }

    pub fn function_ids(&self) -> impl Iterator<Item = &BackFuncId> {
        self.function_ptrs.keys()
    }
}

#[derive(Clone)]
struct FuncDecl {
    sig: BackSigId,
    linkage: Linkage,
    symbol: String,
    func_id: Option<FuncId>,
}

#[derive(Clone)]
struct ExternDecl {
    sig: BackSigId,
    symbol: String,
    func_id: Option<FuncId>,
}

#[derive(Clone)]
enum DataInit {
    Zero { offset: u32, size: u32 },
    Int { offset: u32, ty: BackScalar, raw: String },
    Float { offset: u32, ty: BackScalar, raw: String },
    Bool { offset: u32, value: bool },
}

#[derive(Clone)]
struct DataDecl {
    symbol: String,
    size: u32,
    align: u32,
    inits: Vec<DataInit>,
    data_id: Option<DataId>,
}

struct Compiler<M: Module> {
    module: M,
    signatures: HashMap<BackSigId, Signature>,
    funcs: HashMap<BackFuncId, FuncDecl>,
    externs: HashMap<BackExternId, ExternDecl>,
    datas: HashMap<BackDataId, DataDecl>,
    bodies: Vec<(BackFuncId, Vec<BackBodyCmd>)>,
}

impl Compiler<JITModule> {
    fn new(symbols: &HashMap<String, *const u8>) -> Result<Self, MoonliftError> {
        let isa = host_isa(false)?;
        let mut builder = JITBuilder::with_isa(isa, default_libcall_names());
        for (name, ptr) in symbols {
            builder.symbol(name, *ptr);
        }

        Ok(Self::with_module(JITModule::new(builder)))
    }

    fn compile(mut self, program: &BackProgram) -> Result<Artifact, MoonliftError> {
        self.collect(program)?;
        self.declare_all()?;
        self.define_all()?;
        self.module
            .finalize_definitions()
            .map_err(|e| MoonliftError::new(format!("failed to finalize Moonlift artifact: {e}")))?;

        let mut function_ptrs = HashMap::new();
        for (id, decl) in &self.funcs {
            let func_id = decl
                .func_id
                .ok_or_else(|| MoonliftError::new(format!("internal error: missing finalized FuncId for '{}'", id.as_str())))?;
            let ptr = self.module.get_finalized_function(func_id);
            function_ptrs.insert(id.clone(), ptr);
        }

        Ok(Artifact {
            _module: self.module,
            function_ptrs,
        })
    }
}

impl Compiler<ObjectModule> {
    fn new_object(module_name: &str) -> Result<Self, MoonliftError> {
        let isa = host_isa(true)?;
        let builder = ObjectBuilder::new(isa, module_name, default_libcall_names())
            .map_err(|e| MoonliftError::new(format!("failed to create Cranelift object builder: {e}")))?;
        Ok(Self::with_module(ObjectModule::new(builder)))
    }

    fn compile_object(mut self, program: &BackProgram) -> Result<ObjectArtifact, MoonliftError> {
        self.collect(program)?;
        self.declare_all()?;
        self.define_all()?;
        let product = self.module.finish();
        let bytes = product
            .emit()
            .map_err(|e| MoonliftError::new(format!("failed to emit Moonlift object file: {e}")))?;
        Ok(ObjectArtifact { bytes })
    }
}

impl<M: Module> Compiler<M> {
    fn with_module(module: M) -> Self {
        Self {
            module,
            signatures: HashMap::new(),
            funcs: HashMap::new(),
            externs: HashMap::new(),
            datas: HashMap::new(),
            bodies: Vec::new(),
        }
    }

    fn collect(&mut self, program: &BackProgram) -> Result<(), MoonliftError> {
        // Index all declarations
        for cmd in &program.decls {
            self.collect_global_decl_from_decl_cmd(cmd)?;
        }

        // Verify begin/finish pairing was already done by partition()
        let mut seen_funcs: HashSet<BackFuncId> = HashSet::new();
        for (func_id, _) in &program.bodies {
            if !seen_funcs.insert(func_id.clone()) {
                return Err(MoonliftError::new(format!(
                    "duplicate function body for '{}'", func_id.as_str()
                )));
            }
        }

        for (func, decl) in &self.funcs {
            if decl.linkage != Linkage::Import && !seen_funcs.contains(func) {
                return Err(MoonliftError::new(format!(
                    "declared function '{}' has no body",
                    func.as_str()
                )));
            }
        }

        // Copy bodies directly — no extraction needed
        self.bodies = program.bodies.clone();

        Ok(())
    }

    fn collect_global_decl_from_decl_cmd(&mut self, cmd: &BackDeclCmd) -> Result<(), MoonliftError> {
        match cmd {
            BackDeclCmd::CreateSig(id, params, results) => {
                if results.len() > 1 {
                    return Err(MoonliftError::new(format!(
                        "signature '{}' currently has {} results; the direct function-pointer artifact API currently supports at most one result",
                        id.as_str(),
                        results.len()
                    )));
                }
                let sig = make_signature(&self.module, params, results);
                if let Some(existing) = self.signatures.get(id) {
                    if existing != &sig {
                        return Err(MoonliftError::new(format!(
                            "signature id '{}' was declared multiple times with different shapes",
                            id.as_str()
                        )));
                    }
                } else {
                    self.signatures.insert(id.clone(), sig);
                }
            }
            BackDeclCmd::DeclareData(data, size, align) => {
                if *size == 0 {
                    return Err(MoonliftError::new(format!(
                        "data object '{}' must have size >= 1",
                        data.as_str()
                    )));
                }
                if *align == 0 || !align.is_power_of_two() {
                    return Err(MoonliftError::new(format!(
                        "data object '{}' alignment {} must be a non-zero power of two",
                        data.as_str(),
                        align
                    )));
                }
                match self.datas.get(data) {
                    Some(existing) => {
                        if existing.size != *size || existing.align != *align {
                            return Err(MoonliftError::new(format!(
                                "data id '{}' was declared multiple times with different size/alignment",
                                data.as_str()
                            )));
                        }
                    }
                    None => {
                        self.datas.insert(
                            data.clone(),
                            DataDecl {
                                symbol: local_data_symbol_name(data),
                                size: *size,
                                align: *align,
                                inits: Vec::new(),
                                data_id: None,
                            },
                        );
                    }
                }
            }
            BackDeclCmd::DataInitZero(data, offset, size) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Zero { offset: *offset, size: *size });
            }
            BackDeclCmd::DataInitInt(data, offset, ty, raw) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Int { offset: *offset, ty: *ty, raw: raw.clone() });
            }
            BackDeclCmd::DataInitFloat(data, offset, ty, raw) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Float { offset: *offset, ty: *ty, raw: raw.clone() });
            }
            BackDeclCmd::DataInitBool(data, offset, value) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Bool { offset: *offset, value: *value });
            }
            BackDeclCmd::DeclareFuncLocal(func, sig) => {
                self.insert_func_decl(func, sig, Linkage::Local)?;
            }
            BackDeclCmd::DeclareFuncExport(func, sig) => {
                self.insert_func_decl(func, sig, Linkage::Export)?;
            }
            BackDeclCmd::DeclareFuncExtern(extern_id, symbol, sig) => {
                let spec = self
                    .signatures
                    .get(sig)
                    .ok_or_else(|| MoonliftError::new(format!(
                        "extern '{}' references unknown signature '{}'",
                        extern_id.as_str(),
                        sig.as_str()
                    )))?;
                if spec.returns.len() > 1 {
                    return Err(MoonliftError::new(format!(
                        "extern '{}' uses signature '{}' with {} results; multi-result extern ABIs are not yet supported by the raw pointer API",
                        extern_id.as_str(),
                        sig.as_str(),
                        spec.returns.len()
                    )));
                }
                match self.externs.get(extern_id) {
                    Some(existing) => {
                        if existing.sig != *sig || existing.symbol != *symbol {
                            return Err(MoonliftError::new(format!(
                                "extern id '{}' was declared multiple times with different symbol/signature data",
                                extern_id.as_str()
                            )));
                        }
                    }
                    None => {
                        self.externs.insert(
                            extern_id.clone(),
                            ExternDecl {
                                sig: sig.clone(),
                                symbol: symbol.clone(),
                                func_id: None,
                            },
                        );
                    }
                }
            }
            BackDeclCmd::BeginFunc(_)
            | BackDeclCmd::FinishFunc(_)
            | BackDeclCmd::FinalizeModule => {}
        }
        Ok(())
    }

    fn insert_func_decl(&mut self, func: &BackFuncId, sig: &BackSigId, linkage: Linkage) -> Result<(), MoonliftError> {
        let spec = self.signatures.get(sig).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown signature '{}'",
                func.as_str(),
                sig.as_str()
            ))
        })?;
        if spec.returns.len() > 1 {
            return Err(MoonliftError::new(format!(
                "function '{}' uses signature '{}' with {} results; the direct function-pointer artifact API currently supports at most one result",
                func.as_str(),
                sig.as_str(),
                spec.returns.len()
            )));
        }
        let symbol = if linkage == Linkage::Export {
            func.as_str().to_string()
        } else {
            local_symbol_name(func)
        };
        match self.funcs.get(func) {
            Some(existing) => {
                if existing.sig != *sig || existing.linkage != linkage {
                    return Err(MoonliftError::new(format!(
                        "function id '{}' was declared multiple times with different linkage/signature data",
                        func.as_str()
                    )));
                }
            }
            None => {
                self.funcs.insert(
                    func.clone(),
                    FuncDecl {
                        sig: sig.clone(),
                        linkage,
                        symbol,
                        func_id: None,
                    },
                );
            }
        }
        Ok(())
    }

    fn declare_all(&mut self) -> Result<(), MoonliftError> {
        for decl in self.datas.values_mut() {
            let data_id = self
                .module
                .declare_data(&decl.symbol, Linkage::Local, true, false)
                .map_err(|e| MoonliftError::new(format!("failed to declare data object '{}': {e}", decl.symbol)))?;
            decl.data_id = Some(data_id);
        }

        for decl in self.externs.values_mut() {
            let sig = self.signatures.get(&decl.sig).ok_or_else(|| {
                MoonliftError::new(format!("missing signature '{}' for extern declaration", decl.sig.as_str()))
            })?;
            let func_id = self
                .module
                .declare_function(&decl.symbol, Linkage::Import, sig)
                .map_err(|e| MoonliftError::new(format!("failed to declare extern function '{}': {e}", decl.symbol)))?;
            decl.func_id = Some(func_id);
        }

        for decl in self.funcs.values_mut() {
            let sig = self.signatures.get(&decl.sig).ok_or_else(|| {
                MoonliftError::new(format!("missing signature '{}' for function declaration", decl.sig.as_str()))
            })?;
            let func_id = self
                .module
                .declare_function(&decl.symbol, decl.linkage, sig)
                .map_err(|e| MoonliftError::new(format!("failed to declare function '{}': {e}", decl.symbol)))?;
            decl.func_id = Some(func_id);
        }
        Ok(())
    }

    fn define_all(&mut self) -> Result<(), MoonliftError> {
        let ptr_ty = self.module.target_config().pointer_type();
        for (data_id_text, decl) in &self.datas {
            let data_id = decl.data_id.ok_or_else(|| {
                MoonliftError::new(format!("internal error: missing DataId for '{}'", data_id_text.as_str()))
            })?;
            let mut bytes = vec![0u8; decl.size as usize];
            for init in &decl.inits {
                write_data_init(&mut bytes, ptr_ty, init)?;
            }
            let mut data_desc = DataDescription::new();
            data_desc.define(bytes.into_boxed_slice());
            data_desc.set_align(decl.align as u64);
            self.module
                .define_data(data_id, &data_desc)
                .map_err(|e| MoonliftError::new(format!("failed to define data object '{}': {e:?}", data_id_text.as_str())))?;
        }

        let mut func_ctx = FunctionBuilderContext::new();

        for (func_id_text, cmds) in &self.bodies {
            let decl = self.funcs.get(func_id_text).ok_or_else(|| {
                MoonliftError::new(format!(
                    "function body '{}' has no matching DeclareFuncLocal/DeclareFuncExport",
                    func_id_text.as_str()
                ))
            })?;
            let func_id = decl.func_id.ok_or_else(|| {
                MoonliftError::new(format!("internal error: missing FuncId for '{}'", func_id_text.as_str()))
            })?;
            let sig = self.signatures.get(&decl.sig).ok_or_else(|| {
                MoonliftError::new(format!(
                    "internal error: missing signature '{}' for '{}'",
                    decl.sig.as_str(),
                    func_id_text.as_str()
                ))
            })?;

            let mut ctx = self.module.make_context();
            ctx.func.signature = sig.clone();
            ctx.func.name = UserFuncName::user(0, func_id.as_u32());

            {
                let mut builder = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
                {
                    let mut lower = FunctionLowerer::new(
                        &mut self.module,
                        &self.signatures,
                        &self.funcs,
                        &self.externs,
                        &self.datas,
                        ptr_ty,
                        func_id_text,
                        &mut builder,
                    );
                    lower.lower(cmds)?;
                }
                builder.seal_all_blocks();
                builder.finalize();
            }

            if std::env::var("MOONLIFT_DUMP_CLIF").ok().as_deref() == Some("1") {
                eprintln!("MOONLIFT_CLIF {}:\n{}", func_id_text.as_str(), ctx.func.display());
            }

            self.module
                .define_function(func_id, &mut ctx)
                .map_err(|e| MoonliftError::new(format!("failed to define function '{}': {e:?}", func_id_text.as_str())))?;
            self.module.clear_context(&mut ctx);
        }

        Ok(())
    }
}

struct FunctionLowerer<'a, 'b, M: Module> {
    module: &'a mut M,
    signatures: &'a HashMap<BackSigId, Signature>,
    funcs: &'a HashMap<BackFuncId, FuncDecl>,
    externs: &'a HashMap<BackExternId, ExternDecl>,
    datas: &'a HashMap<BackDataId, DataDecl>,
    ptr_ty: Type,
    func_name: &'a BackFuncId,
    builder: &'b mut FunctionBuilder<'a>,
    values: HashMap<BackValId, Value>,
    blocks: HashMap<BackBlockId, Block>,
    stack_slots: HashMap<BackStackSlotId, StackSlot>,
}

impl<'a, 'b, M: Module> FunctionLowerer<'a, 'b, M> {
    fn new(
        module: &'a mut M,
        signatures: &'a HashMap<BackSigId, Signature>,
        funcs: &'a HashMap<BackFuncId, FuncDecl>,
        externs: &'a HashMap<BackExternId, ExternDecl>,
        datas: &'a HashMap<BackDataId, DataDecl>,
        ptr_ty: Type,
        func_name: &'a BackFuncId,
        builder: &'b mut FunctionBuilder<'a>,
    ) -> Self {
        Self {
            module,
            signatures,
            funcs,
            externs,
            datas,
            ptr_ty,
            func_name,
            builder,
            values: HashMap::new(),
            blocks: HashMap::new(),
            stack_slots: HashMap::new(),
        }
    }

    fn lower(&mut self, cmds: &[BackBodyCmd]) -> Result<(), MoonliftError> {
        for cmd in cmds {
            self.lower_cmd(cmd)?;
        }
        Ok(())
    }

    fn lower_cmd(&mut self, cmd: &BackBodyCmd) -> Result<(), MoonliftError> {
        match cmd {
            BackBodyCmd::Cfg(op) => self.lower_cfg(op),
            BackBodyCmd::Address(op) => self.lower_address(op),
            BackBodyCmd::Const(op) => self.lower_const(op),
            BackBodyCmd::Unary(op) => self.lower_unary(op),
            BackBodyCmd::Intrinsic(op) => self.lower_intrinsic(op),
            BackBodyCmd::IntBinary(op) => self.lower_int_binary(op),
            BackBodyCmd::FloatBinary(op) => self.lower_float_binary(op),
            BackBodyCmd::Bitwise(op) => self.lower_bitwise(op),
            BackBodyCmd::Shift(op) => self.lower_shift(op),
            BackBodyCmd::Rotate(op) => self.lower_rotate(op),
            BackBodyCmd::Compare(op) => self.lower_compare(op),
            BackBodyCmd::Cast(op) => self.lower_cast(op),
            BackBodyCmd::Ptr(op) => self.lower_ptr(op),
            BackBodyCmd::Memory(op) => self.lower_memory(op),
            BackBodyCmd::Call(op) => self.lower_call(op),
            BackBodyCmd::Control(op) => self.lower_control(op),
            BackBodyCmd::VecUnary(op) => self.lower_vec_unary(op),
            BackBodyCmd::VecBinary(op) => self.lower_vec_binary(op),
            BackBodyCmd::VecCompare(op) => self.lower_vec_compare(op),
            BackBodyCmd::VecMemory(op) => self.lower_vec_memory(op),
            BackBodyCmd::Other(op) => self.lower_other(op),
        }
    }

    // ── CFG scaffolding ────
    fn lower_cfg(&mut self, op: &CfgOp) -> Result<(), MoonliftError> {
        match op {
            CfgOp::CreateBlock(id) => {
                let block = self.builder.create_block();
                if self.blocks.insert(id.clone(), block).is_some() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' created block '{}' more than once",
                        self.func_name.as_str(),
                        id.as_str()
                    )));
                }
                Ok(())
            }
            CfgOp::SwitchToBlock(id) => {
                let block = self.block(id)?;
                self.builder.switch_to_block(block);
                Ok(())
            }
            CfgOp::SealBlock(id) => {
                let block = self.block(id)?;
                self.builder.seal_block(block);
                Ok(())
            }
            CfgOp::BindEntryParams(id, values) => {
                let block = self.block(id)?;
                self.builder.append_block_params_for_function_params(block);
                let block_params = self.builder.block_params(block).to_vec();
                if block_params.len() != values.len() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' bound {} entry params for block '{}' but the function signature has {} params",
                        self.func_name.as_str(),
                        values.len(),
                        id.as_str(),
                        block_params.len()
                    )));
                }
                for (name, value) in values.iter().zip(block_params.iter().copied()) {
                    self.bind_value(name, value)?;
                }
                Ok(())
            }
            CfgOp::AppendBlockParam(block_id, value_id, ty) => {
                let block = self.block(block_id)?;
                let value = self.builder.append_block_param(block, ty.clif_type(self.ptr_ty));
                self.bind_value(value_id, value)?;
                Ok(())
            }
            CfgOp::AppendVecBlockParam(block_id, value_id, ty) => {
                let block = self.block(block_id)?;
                let value = self.builder.append_block_param(block, ty.clif_type(self.ptr_ty)?);
                self.bind_value(value_id, value)?;
                Ok(())
            }
            CfgOp::CreateStackSlot(id, size, align) => {
                let align_shift = align_to_shift(*align)?;
                let slot = self.builder.create_sized_stack_slot(StackSlotData::new(
                    StackSlotKind::ExplicitSlot,
                    *size,
                    align_shift,
                ));
                if self.stack_slots.insert(id.clone(), slot).is_some() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' created stack slot '{}' more than once",
                        self.func_name.as_str(),
                        id.as_str()
                    )));
                }
                Ok(())
            }
        }
    }

    // ── Address ────
    fn lower_address(&mut self, op: &AddressOp) -> Result<(), MoonliftError> {
        match op {
            AddressOp::StackAddr(dst, slot_id) => {
                let slot = self.stack_slot(slot_id)?;
                let value = self.builder.ins().stack_addr(self.ptr_ty, slot, 0);
                self.bind_value(dst, value)
            }
            AddressOp::DataAddr(dst, data_id) => {
                let data = self.data(data_id)?;
                let gv = self.module.declare_data_in_func(data, &mut self.builder.func);
                let value = self.builder.ins().global_value(self.ptr_ty, gv);
                self.bind_value(dst, value)
            }
            AddressOp::FuncAddr(dst, func) => {
                let decl = self.funcs.get(func).ok_or_else(|| {
                    MoonliftError::new(format!(
                        "function '{}' takes address of unknown function '{}'",
                        self.func_name.as_str(),
                        func.as_str()
                    ))
                })?;
                let func_id = decl.func_id.ok_or_else(|| {
                    MoonliftError::new(format!("internal error: missing FuncId for function '{}'", func.as_str()))
                })?;
                let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
                let value = self.builder.ins().func_addr(self.ptr_ty, func_ref);
                self.bind_value(dst, value)
            }
            AddressOp::ExternAddr(dst, extern_id) => {
                let decl = self.externs.get(extern_id).ok_or_else(|| {
                    MoonliftError::new(format!(
                        "function '{}' takes address of unknown extern '{}'",
                        self.func_name.as_str(),
                        extern_id.as_str()
                    ))
                })?;
                let func_id = decl.func_id.ok_or_else(|| {
                    MoonliftError::new(format!("internal error: missing FuncId for extern '{}'", extern_id.as_str()))
                })?;
                let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
                let value = self.builder.ins().func_addr(self.ptr_ty, func_ref);
                self.bind_value(dst, value)
            }
        }
    }

    // ── Constants ────
    fn lower_const(&mut self, op: &ConstOp) -> Result<(), MoonliftError> {
        match op {
            ConstOp::ConstInt(dst, ty, raw) => {
                let value = lower_const_int(self.builder, self.ptr_ty, *ty, raw)?;
                self.bind_value(dst, value)
            }
            ConstOp::ConstFloat(dst, ty, raw) => {
                let value = lower_const_float(self.builder, *ty, raw)?;
                self.bind_value(dst, value)
            }
            ConstOp::ConstBool(dst, value) => {
                let raw = self.builder.ins().iconst(types::I8, if *value { 1 } else { 0 });
                self.bind_value(dst, raw)
            }
            ConstOp::ConstNull(dst) => {
                let value = self.builder.ins().iconst(self.ptr_ty, 0);
                self.bind_value(dst, value)
            }
        }
    }

    // ── Scalar Unary ────
    fn lower_unary(&mut self, op: &ScalarUnaryOp) -> Result<(), MoonliftError> {
        match op {
            ScalarUnaryOp::Ineg(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ineg(value);
                self.bind_value(dst, out)
            }
            ScalarUnaryOp::Fneg(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fneg(value);
                self.bind_value(dst, out)
            }
            ScalarUnaryOp::Bnot(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().bnot(value);
                self.bind_value(dst, out)
            }
            ScalarUnaryOp::BoolNot(dst, value) => {
                let value = self.value(value)?;
                let cond = self.builder.ins().icmp_imm(IntCC::Equal, value, 0);
                let out = bool_value_from_cond(self.builder, cond);
                self.bind_value(dst, out)
            }
        }
    }

    // ── Intrinsics ────
    fn lower_intrinsic(&mut self, op: &IntrinsicOp) -> Result<(), MoonliftError> {
        match op {
            IntrinsicOp::Popcount(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().popcnt(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::Clz(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().clz(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::Ctz(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ctz(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::Bswap(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().bswap(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::Sqrt(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().sqrt(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::Abs(dst, ty, value) => {
                let value = self.value(value)?;
                let out = match ty {
                    BackScalar::F32 | BackScalar::F64 => self.builder.ins().fabs(value),
                    _ => self.builder.ins().iabs(value),
                };
                self.bind_value(dst, out)
            }
            IntrinsicOp::Floor(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().floor(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::Ceil(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ceil(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::TruncFloat(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().trunc(value);
                self.bind_value(dst, out)
            }
            IntrinsicOp::Round(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().nearest(value);
                self.bind_value(dst, out)
            }
        }
    }

    // ── Integer Binary ────
    fn lower_int_binary(&mut self, op: &IntBinaryOp) -> Result<(), MoonliftError> {
        match op {
            IntBinaryOp::Iadd(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().iadd(l, r)),
            IntBinaryOp::Isub(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().isub(l, r)),
            IntBinaryOp::Imul(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().imul(l, r)),
            IntBinaryOp::Sdiv(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().sdiv(l, r)),
            IntBinaryOp::Udiv(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().udiv(l, r)),
            IntBinaryOp::Srem(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().srem(l, r)),
            IntBinaryOp::Urem(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().urem(l, r)),
        }
    }

    // ── Float Binary ────
    fn lower_float_binary(&mut self, op: &FloatBinaryOp) -> Result<(), MoonliftError> {
        match op {
            FloatBinaryOp::Fadd(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fadd(l, r)),
            FloatBinaryOp::Fsub(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fsub(l, r)),
            FloatBinaryOp::Fmul(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fmul(l, r)),
            FloatBinaryOp::Fdiv(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fdiv(l, r)),
        }
    }

    // ── Bitwise ────
    fn lower_bitwise(&mut self, op: &BitwiseOp) -> Result<(), MoonliftError> {
        match op {
            BitwiseOp::Band(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().band(l, r)),
            BitwiseOp::Bor(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().bor(l, r)),
            BitwiseOp::Bxor(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().bxor(l, r)),
        }
    }

    // ── Shift ────
    fn lower_shift(&mut self, op: &ShiftOp) -> Result<(), MoonliftError> {
        match op {
            ShiftOp::Ishl(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().ishl(l, r)),
            ShiftOp::Ushr(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().ushr(l, r)),
            ShiftOp::Sshr(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().sshr(l, r)),
        }
    }

    // ── Rotate ────
    fn lower_rotate(&mut self, op: &RotateOp) -> Result<(), MoonliftError> {
        match op {
            RotateOp::Rotl(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().rotl(l, r)),
            RotateOp::Rotr(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().rotr(l, r)),
        }
    }

    // ── Compare ────
    fn lower_compare(&mut self, op: &CompareOp) -> Result<(), MoonliftError> {
        match op {
            CompareOp::IcmpEq(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::Equal, lhs, rhs),
            CompareOp::IcmpNe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::NotEqual, lhs, rhs),
            CompareOp::SIcmpLt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedLessThan, lhs, rhs),
            CompareOp::SIcmpLe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedLessThanOrEqual, lhs, rhs),
            CompareOp::SIcmpGt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedGreaterThan, lhs, rhs),
            CompareOp::SIcmpGe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedGreaterThanOrEqual, lhs, rhs),
            CompareOp::UIcmpLt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedLessThan, lhs, rhs),
            CompareOp::UIcmpLe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedLessThanOrEqual, lhs, rhs),
            CompareOp::UIcmpGt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedGreaterThan, lhs, rhs),
            CompareOp::UIcmpGe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedGreaterThanOrEqual, lhs, rhs),
            CompareOp::FCmpEq(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::Equal, lhs, rhs),
            CompareOp::FCmpNe(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::NotEqual, lhs, rhs),
            CompareOp::FCmpLt(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::LessThan, lhs, rhs),
            CompareOp::FCmpLe(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::LessThanOrEqual, lhs, rhs),
            CompareOp::FCmpGt(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::GreaterThan, lhs, rhs),
            CompareOp::FCmpGe(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::GreaterThanOrEqual, lhs, rhs),
        }
    }

    // ── Cast ────
    fn lower_cast(&mut self, op: &CastOp) -> Result<(), MoonliftError> {
        match op {
            CastOp::Bitcast(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().bitcast(ty.clif_type(self.ptr_ty), MemFlags::new(), value);
                self.bind_value(dst, out)
            }
            CastOp::Ireduce(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ireduce(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::Sextend(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().sextend(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::Uextend(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().uextend(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::Fpromote(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fpromote(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::Fdemote(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fdemote(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::SToF(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_from_sint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::UToF(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_from_uint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::FToS(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_to_sint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            CastOp::FToU(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_to_uint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
        }
    }

    // ── Pointer ────
    fn lower_ptr(&mut self, op: &PtrOp) -> Result<(), MoonliftError> {
        match op {
            PtrOp::PtrAdd(dst, base, byte_offset) => {
                let base_value = self.value(base)?;
                let offset_value = self.value(byte_offset)?;
                self.require_value_type(base, base_value, self.ptr_ty, "BackCmdPtrAdd base")?;
                self.require_value_type(byte_offset, offset_value, self.ptr_ty, "BackCmdPtrAdd byte_offset")?;
                let out = self.builder.ins().iadd(base_value, offset_value);
                self.bind_value(dst, out)
            }
            PtrOp::PtrOffset(dst, base, index, elem_size, const_offset) => {
                let base_value = self.value(base)?;
                let index_value = self.value(index)?;
                self.require_value_type(base, base_value, self.ptr_ty, "BackCmdPtrOffset base")?;
                self.require_value_type(index, index_value, self.ptr_ty, "BackCmdPtrOffset index")?;
                let elem_size_value = self.builder.ins().iconst(self.ptr_ty, i64::from(*elem_size));
                let scaled = self.builder.ins().imul(index_value, elem_size_value);
                let total = if *const_offset == 0 {
                    scaled
                } else {
                    let const_value = self.builder.ins().iconst(self.ptr_ty, *const_offset);
                    self.builder.ins().iadd(scaled, const_value)
                };
                let out = self.builder.ins().iadd(base_value, total);
                self.bind_value(dst, out)
            }
        }
    }

    // ── Memory ────
    fn lower_memory(&mut self, op: &MemoryOp) -> Result<(), MoonliftError> {
        match op {
            MemoryOp::LoadInfo(dst, ty, addr, memory) => {
                let addr = self.value(addr)?;
                let clif_ty = ty.clif_type(self.ptr_ty);
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                let out = self.builder.ins().load(clif_ty, flags, addr, 0);
                self.bind_value(dst, out)
            }
            MemoryOp::StoreInfo(ty, addr, value, memory) => {
                let addr = self.value(addr)?;
                let value = self.value(value)?;
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                self.builder.ins().store(flags, value, addr, 0);
                Ok(())
            }
            MemoryOp::AtomicLoad(dst, ty, addr, memory, BackAtomicOrdering::SeqCst) => {
                if !ty.supports_atomic() {
                    return Err(MoonliftError::new(format!("BackCmdAtomicLoad requires integer/pointer type, got {:?}", ty)));
                }
                let addr_value = self.value(addr)?;
                self.require_value_type(addr, addr_value, self.ptr_ty, "BackCmdAtomicLoad addr")?;
                let clif_ty = ty.clif_type(self.ptr_ty);
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                let out = self.builder.ins().atomic_load(clif_ty, flags, addr_value);
                self.bind_value(dst, out)
            }
            MemoryOp::AtomicStore(ty, addr, value, memory, BackAtomicOrdering::SeqCst) => {
                if !ty.supports_atomic() {
                    return Err(MoonliftError::new(format!("BackCmdAtomicStore requires integer/pointer type, got {:?}", ty)));
                }
                let addr_value = self.value(addr)?;
                let store_value = self.value(value)?;
                let clif_ty = ty.clif_type(self.ptr_ty);
                self.require_value_type(addr, addr_value, self.ptr_ty, "BackCmdAtomicStore addr")?;
                self.require_value_type(value, store_value, clif_ty, "BackCmdAtomicStore value")?;
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                self.builder.ins().atomic_store(flags, store_value, addr_value);
                Ok(())
            }
            MemoryOp::AtomicRmw(dst, op, ty, addr, value, memory, BackAtomicOrdering::SeqCst) => {
                if !op.supports_scalar(*ty) {
                    return Err(MoonliftError::new(format!("BackCmdAtomicRmw op {:?} does not support type {:?}", op, ty)));
                }
                let addr_value = self.value(addr)?;
                let input_value = self.value(value)?;
                let clif_ty = ty.clif_type(self.ptr_ty);
                self.require_value_type(addr, addr_value, self.ptr_ty, "BackCmdAtomicRmw addr")?;
                self.require_value_type(value, input_value, clif_ty, "BackCmdAtomicRmw value")?;
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                let out = self.builder.ins().atomic_rmw(clif_ty, flags, op.clif(), addr_value, input_value);
                self.bind_value(dst, out)
            }
            MemoryOp::AtomicCas(dst, ty, addr, expected, replacement, memory, BackAtomicOrdering::SeqCst) => {
                if !ty.supports_atomic() {
                    return Err(MoonliftError::new(format!("BackCmdAtomicCas requires integer/pointer type, got {:?}", ty)));
                }
                let addr_value = self.value(addr)?;
                let expected_value = self.value(expected)?;
                let replacement_value = self.value(replacement)?;
                let clif_ty = ty.clif_type(self.ptr_ty);
                self.require_value_type(addr, addr_value, self.ptr_ty, "BackCmdAtomicCas addr")?;
                self.require_value_type(expected, expected_value, clif_ty, "BackCmdAtomicCas expected")?;
                self.require_value_type(replacement, replacement_value, clif_ty, "BackCmdAtomicCas replacement")?;
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                let out = self.builder.ins().atomic_cas(flags, addr_value, expected_value, replacement_value);
                self.bind_value(dst, out)
            }
            MemoryOp::AtomicFence(BackAtomicOrdering::SeqCst) => {
                self.builder.ins().fence();
                Ok(())
            }
            MemoryOp::Memcpy(dst, src, len) => {
                let dst_value = self.value(dst)?;
                let src_value = self.value(src)?;
                let len_value = self.value(len)?;
                self.require_value_type(dst, dst_value, self.ptr_ty, "BackCmdMemcpy destination")?;
                self.require_value_type(src, src_value, self.ptr_ty, "BackCmdMemcpy source")?;
                self.require_value_type(len, len_value, self.ptr_ty, "BackCmdMemcpy length")?;
                let config = self.module.target_config();
                self.builder.call_memcpy(config, dst_value, src_value, len_value);
                Ok(())
            }
            MemoryOp::Memset(dst, byte, len) => {
                let dst_value = self.value(dst)?;
                let len_value = self.value(len)?;
                self.require_value_type(dst, dst_value, self.ptr_ty, "BackCmdMemset destination")?;
                self.require_value_type(len, len_value, self.ptr_ty, "BackCmdMemset length")?;
                let byte_value = self.byte_fill_value(byte)?;
                let config = self.module.target_config();
                self.builder.call_memset(config, dst_value, byte_value, len_value);
                Ok(())
            }
        }
    }

    // ── Call ────
    fn lower_call(&mut self, op: &CallOp) -> Result<(), MoonliftError> {
        match op {
            CallOp::CallValueDirect(dst, _, func, sig, args) => {
                let value = self.call_direct(func, sig, args)?;
                self.bind_value(dst, value)
            }
            CallOp::CallStmtDirect(func, sig, args) => {
                self.call_direct_stmt(func, sig, args)?;
                Ok(())
            }
            CallOp::CallValueExtern(dst, _, func, sig, args) => {
                let value = self.call_extern(func, sig, args)?;
                self.bind_value(dst, value)
            }
            CallOp::CallStmtExtern(func, sig, args) => {
                self.call_extern_stmt(func, sig, args)?;
                Ok(())
            }
            CallOp::CallValueIndirect(dst, _, callee, sig, args) => {
                let value = self.call_indirect(callee, sig, args)?;
                self.bind_value(dst, value)
            }
            CallOp::CallStmtIndirect(callee, sig, args) => {
                self.call_indirect_stmt(callee, sig, args)?;
                Ok(())
            }
        }
    }

    // ── Control Flow ────
    fn lower_control(&mut self, op: &ControlOp) -> Result<(), MoonliftError> {
        match op {
            ControlOp::Jump(dest, args) => {
                let block = self.block(dest)?;
                let args = self.block_args(args)?;
                self.builder.ins().jump(block, &args);
                Ok(())
            }
            ControlOp::BrIf(cond, then_block, then_args, else_block, else_args) => {
                let cond = self.cond_value(cond)?;
                let then_block = self.block(then_block)?;
                let else_block = self.block(else_block)?;
                let then_args = self.block_args(then_args)?;
                let else_args = self.block_args(else_args)?;
                self.builder.ins().brif(cond, then_block, &then_args, else_block, &else_args);
                Ok(())
            }
            ControlOp::SwitchInt(value_id, ty, cases, default_id) => {
                let value = self.value(value_id)?;
                let value_ty = self.builder.func.dfg.value_type(value);
                let expected_ty = ty.clif_type(self.ptr_ty);
                if value_ty != expected_ty {
                    return Err(MoonliftError::new(format!(
                        "function '{}' used BackCmdSwitchInt value '{}' with CLIF type {:?}, expected {:?}",
                        self.func_name.as_str(),
                        value_id.as_str(),
                        value_ty,
                        expected_ty
                    )));
                }
                let default_block = self.block(default_id)?;
                let mut switch = Switch::new();
                let mut seen = HashSet::new();
                for case in cases {
                    let index = parse_switch_int_case(&case.raw, *ty, self.ptr_ty)?;
                    if !seen.insert(index) {
                        return Err(MoonliftError::new(format!(
                            "function '{}' repeated BackCmdSwitchInt case '{}'",
                            self.func_name.as_str(),
                            case.raw
                        )));
                    }
                    switch.set_entry(index, self.block(&case.dest)?);
                }
                switch.emit(&mut self.builder, value, default_block);
                Ok(())
            }
            ControlOp::ReturnVoid => {
                self.builder.ins().return_(&[]);
                Ok(())
            }
            ControlOp::ReturnValue(value) => {
                let value = self.value(value)?;
                self.builder.ins().return_(&[value]);
                Ok(())
            }
            ControlOp::Trap => {
                self.builder.ins().trap(TrapCode::unwrap_user(1));
                Ok(())
            }
        }
    }

    // ── Vector Unary ────
    fn lower_vec_unary(&mut self, op: &VecUnaryOp) -> Result<(), MoonliftError> {
        match op {
            VecUnaryOp::VecSplat(dst, ty, value) => {
                let scalar = self.value(value)?;
                let scalar_ty = ty.elem.clif_type(self.ptr_ty);
                self.require_value_type(value, scalar, scalar_ty, "BackCmdVecSplat scalar")?;
                let out = self.builder.ins().splat(ty.clif_type(self.ptr_ty)?, scalar);
                self.bind_value(dst, out)
            }
            VecUnaryOp::VecSelect(dst, ty, mask, then_value, else_value) => self.bind_vec_select(dst, *ty, mask, then_value, else_value),
            VecUnaryOp::VecMaskNot(dst, ty, value) => self.bind_vec_mask_not(dst, *ty, value),
            VecUnaryOp::VecInsertLane(dst, ty, value, lane_value, lane) => {
                let vector = self.value(value)?;
                let scalar = self.value(lane_value)?;
                let vector_ty = ty.clif_type(self.ptr_ty)?;
                self.require_value_type(value, vector, vector_ty, "BackCmdVecInsertLane vector")?;
                self.require_value_type(lane_value, scalar, ty.elem.clif_type(self.ptr_ty), "BackCmdVecInsertLane lane value")?;
                if *lane >= ty.lanes {
                    return Err(MoonliftError::new(format!(
                        "function '{}' inserts lane {} into vector '{}' with only {} lanes",
                        self.func_name.as_str(),
                        lane,
                        value.as_str(),
                        ty.lanes
                    )));
                }
                let lane_u8 = u8::try_from(*lane).map_err(|_| MoonliftError::new(format!("lane {} does not fit in u8", lane)))?;
                let out = self.builder.ins().insertlane(vector, scalar, lane_u8);
                self.bind_value(dst, out)
            }
            VecUnaryOp::VecExtractLane(dst, ty, value, lane) => {
                let vector = self.value(value)?;
                let vector_ty = self.builder.func.dfg.value_type(vector);
                if !vector_ty.is_vector() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' uses BackCmdVecExtractLane value '{}' with non-vector CLIF type {:?}",
                        self.func_name.as_str(),
                        value.as_str(),
                        vector_ty
                    )));
                }
                if *lane >= vector_ty.lane_count() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' extracts lane {} from '{}' with only {} lanes",
                        self.func_name.as_str(),
                        lane,
                        value.as_str(),
                        vector_ty.lane_count()
                    )));
                }
                let expected_lane_ty = ty.clif_type(self.ptr_ty);
                if vector_ty.lane_type() != expected_lane_ty {
                    return Err(MoonliftError::new(format!(
                        "function '{}' extracts {:?} lane from '{}' with lane type {:?}",
                        self.func_name.as_str(),
                        expected_lane_ty,
                        value.as_str(),
                        vector_ty.lane_type()
                    )));
                }
                let lane_u8 = u8::try_from(*lane).map_err(|_| MoonliftError::new(format!("lane {} does not fit in u8", lane)))?;
                let out = self.builder.ins().extractlane(vector, lane_u8);
                self.bind_value(dst, out)
            }
        }
    }

    // ── Vector Binary ────
    fn lower_vec_binary(&mut self, op: &VecBinaryOp) -> Result<(), MoonliftError> {
        match op {
            VecBinaryOp::VecMaskAnd(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().band(l, r)),
            VecBinaryOp::VecMaskOr(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().bor(l, r)),
            VecBinaryOp::VecIadd(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().iadd(l, r)),
            VecBinaryOp::VecIsub(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().isub(l, r)),
            VecBinaryOp::VecImul(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().imul(l, r)),
            VecBinaryOp::VecBand(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().band(l, r)),
            VecBinaryOp::VecBor(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().bor(l, r)),
            VecBinaryOp::VecBxor(dst, ty, lhs, rhs) => self.bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().bxor(l, r)),
        }
    }

    // ── Vector Compare ────
    fn lower_vec_compare(&mut self, op: &VecCompareOp) -> Result<(), MoonliftError> {
        match op {
            VecCompareOp::VecIcmpEq(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::Equal, lhs, rhs),
            VecCompareOp::VecIcmpNe(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::NotEqual, lhs, rhs),
            VecCompareOp::VecSIcmpLt(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::SignedLessThan, lhs, rhs),
            VecCompareOp::VecSIcmpLe(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::SignedLessThanOrEqual, lhs, rhs),
            VecCompareOp::VecSIcmpGt(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::SignedGreaterThan, lhs, rhs),
            VecCompareOp::VecSIcmpGe(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::SignedGreaterThanOrEqual, lhs, rhs),
            VecCompareOp::VecUIcmpLt(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::UnsignedLessThan, lhs, rhs),
            VecCompareOp::VecUIcmpLe(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::UnsignedLessThanOrEqual, lhs, rhs),
            VecCompareOp::VecUIcmpGt(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::UnsignedGreaterThan, lhs, rhs),
            VecCompareOp::VecUIcmpGe(dst, ty, lhs, rhs) => self.bind_vec_icmp(dst, *ty, IntCC::UnsignedGreaterThanOrEqual, lhs, rhs),
        }
    }

    // ── Vector Memory ────
    fn lower_vec_memory(&mut self, op: &VecMemoryOp) -> Result<(), MoonliftError> {
        match op {
            VecMemoryOp::VecLoadInfo(dst, ty, addr, memory) => {
                let addr_value = self.value(addr)?;
                self.require_value_type(addr, addr_value, self.ptr_ty, "BackCmdVecLoadInfo addr")?;
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                let out = self.builder.ins().load(ty.clif_type(self.ptr_ty)?, flags, addr_value, 0);
                self.bind_value(dst, out)
            }
            VecMemoryOp::VecStoreInfo(ty, addr, value, memory) => {
                let addr_value = self.value(addr)?;
                let store_value = self.value(value)?;
                self.require_value_type(addr, addr_value, self.ptr_ty, "BackCmdVecStoreInfo addr")?;
                self.require_value_type(value, store_value, ty.clif_type(self.ptr_ty)?, "BackCmdVecStoreInfo value")?;
                let ptr_bytes = self.ptr_ty.bytes();
                let flags = memory.memflags(ty.byte_size(ptr_bytes), ty.byte_size(ptr_bytes));
                self.builder.ins().store(flags, store_value, addr_value, 0);
                Ok(())
            }
        }
    }

    // ── Singleton (ungrouped) ────
    fn lower_other(&mut self, op: &OtherOp) -> Result<(), MoonliftError> {
        match op {
            OtherOp::Alias(dst, src) => {
                let value = self.value(src)?;
                self.values.insert(dst.clone(), value);
                Ok(())
            }
            OtherOp::Select(dst, _, cond, then_value, else_value) => {
                let cond_value = self.cond_value(cond)?;
                let then_value = self.value(then_value)?;
                let else_value = self.value(else_value)?;
                let out = self.builder.ins().select(cond_value, then_value, else_value);
                self.bind_value(dst, out)
            }
            OtherOp::Fma(dst, _, _, a, b, c) => {
                let a = self.value(a)?;
                let b = self.value(b)?;
                let c = self.value(c)?;
                let out = self.builder.ins().fma(a, b, c);
                self.bind_value(dst, out)
            }
        }
    }

    fn bind_binop<F>(&mut self, dst: &BackValId, lhs: &BackValId, rhs: &BackValId, f: F) -> Result<(), MoonliftError>
    where
        F: FnOnce(&mut FunctionBuilder<'a>, Value, Value) -> Value,
    {
        let lhs = self.value(lhs)?;
        let rhs = self.value(rhs)?;
        let out = f(self.builder, lhs, rhs);
        self.bind_value(dst, out)
    }

    fn bind_vec_binop<F>(&mut self, dst: &BackValId, ty: BackVec, lhs: &BackValId, rhs: &BackValId, f: F) -> Result<(), MoonliftError>
    where
        F: FnOnce(&mut FunctionBuilder<'a>, Value, Value) -> Value,
    {
        let expected = ty.clif_type(self.ptr_ty)?;
        let lhs_value = self.value(lhs)?;
        let rhs_value = self.value(rhs)?;
        self.require_value_type(lhs, lhs_value, expected, "vector lhs")?;
        self.require_value_type(rhs, rhs_value, expected, "vector rhs")?;
        let out = f(self.builder, lhs_value, rhs_value);
        self.bind_value(dst, out)
    }

    fn bind_vec_icmp(&mut self, dst: &BackValId, ty: BackVec, cc: IntCC, lhs: &BackValId, rhs: &BackValId) -> Result<(), MoonliftError> {
        let expected = ty.clif_type(self.ptr_ty)?;
        let lhs_value = self.value(lhs)?;
        let rhs_value = self.value(rhs)?;
        self.require_value_type(lhs, lhs_value, expected, "vector compare lhs")?;
        self.require_value_type(rhs, rhs_value, expected, "vector compare rhs")?;
        let out = self.builder.ins().icmp(cc, lhs_value, rhs_value);
        self.bind_value(dst, out)
    }

    fn bind_vec_select(&mut self, dst: &BackValId, ty: BackVec, mask: &BackValId, then_value: &BackValId, else_value: &BackValId) -> Result<(), MoonliftError> {
        let expected = ty.clif_type(self.ptr_ty)?;
        let mask_value = self.value(mask)?;
        let then_value = self.value(then_value)?;
        let else_value = self.value(else_value)?;
        self.require_value_type(mask, mask_value, expected, "vector select mask")?;
        self.require_value_type(dst, then_value, expected, "vector select then")?;
        self.require_value_type(dst, else_value, expected, "vector select else")?;
        if matches!(ty.elem, BackScalar::F32 | BackScalar::F64) {
            return Err(MoonliftError::new(format!(
                "function '{}' uses BackCmdVecSelect on float vector {:?}; Moonlift requires an explicit future float-vector select/blend command instead of integer mask lowering",
                self.func_name.as_str(),
                ty
            )));
        }
        let masked_then = self.builder.ins().band(mask_value, then_value);
        let not_mask = self.builder.ins().bnot(mask_value);
        let masked_else = self.builder.ins().band(not_mask, else_value);
        let out = self.builder.ins().bor(masked_then, masked_else);
        self.bind_value(dst, out)
    }

    fn bind_vec_mask_not(&mut self, dst: &BackValId, ty: BackVec, value: &BackValId) -> Result<(), MoonliftError> {
        let expected = ty.clif_type(self.ptr_ty)?;
        let value = self.value(value)?;
        self.require_value_type(dst, value, expected, "vector mask not")?;
        let out = self.builder.ins().bnot(value);
        self.bind_value(dst, out)
    }

    fn bind_icmp(&mut self, dst: &BackValId, cc: IntCC, lhs: &BackValId, rhs: &BackValId) -> Result<(), MoonliftError> {
        let lhs = self.value(lhs)?;
        let rhs = self.value(rhs)?;
        let cond = self.builder.ins().icmp(cc, lhs, rhs);
        let out = bool_value_from_cond(self.builder, cond);
        self.bind_value(dst, out)
    }

    fn bind_fcmp(&mut self, dst: &BackValId, cc: FloatCC, lhs: &BackValId, rhs: &BackValId) -> Result<(), MoonliftError> {
        let lhs = self.value(lhs)?;
        let rhs = self.value(rhs)?;
        let cond = self.builder.ins().fcmp(cc, lhs, rhs);
        let out = bool_value_from_cond(self.builder, cond);
        self.bind_value(dst, out)
    }

    fn call_direct(&mut self, func: &BackFuncId, sig: &BackSigId, args: &[BackValId]) -> Result<Value, MoonliftError> {
        let decl = self.funcs.get(func).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown direct callee '{}'",
                self.func_name.as_str(),
                func.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                func.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for direct callee '{}'", func.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        let call = self.builder.ins().call(func_ref, &args);
        self.take_single_result(call, func.as_str())
    }

    fn call_direct_stmt(&mut self, func: &BackFuncId, sig: &BackSigId, args: &[BackValId]) -> Result<(), MoonliftError> {
        let decl = self.funcs.get(func).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown direct callee '{}'",
                self.func_name.as_str(),
                func.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                func.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for direct callee '{}'", func.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        self.builder.ins().call(func_ref, &args);
        Ok(())
    }

    fn call_extern(&mut self, extern_id: &BackExternId, sig: &BackSigId, args: &[BackValId]) -> Result<Value, MoonliftError> {
        let decl = self.externs.get(extern_id).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown extern '{}'",
                self.func_name.as_str(),
                extern_id.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called extern '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                extern_id.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for extern '{}'", extern_id.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        let call = self.builder.ins().call(func_ref, &args);
        self.take_single_result(call, extern_id.as_str())
    }

    fn call_extern_stmt(&mut self, extern_id: &BackExternId, sig: &BackSigId, args: &[BackValId]) -> Result<(), MoonliftError> {
        let decl = self.externs.get(extern_id).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown extern '{}'",
                self.func_name.as_str(),
                extern_id.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called extern '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                extern_id.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for extern '{}'", extern_id.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        self.builder.ins().call(func_ref, &args);
        Ok(())
    }

    fn call_indirect(&mut self, callee: &BackValId, sig: &BackSigId, args: &[BackValId]) -> Result<Value, MoonliftError> {
        let signature = self.signatures.get(sig).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls indirect signature '{}' which was never created",
                self.func_name.as_str(),
                sig.as_str()
            ))
        })?;
        let sig_ref = self.builder.import_signature(signature.clone());
        let callee = self.value(callee)?;
        let args = self.values(args)?;
        let call = self.builder.ins().call_indirect(sig_ref, callee, &args);
        self.take_single_result(call, sig.as_str())
    }

    fn call_indirect_stmt(&mut self, callee: &BackValId, sig: &BackSigId, args: &[BackValId]) -> Result<(), MoonliftError> {
        let signature = self.signatures.get(sig).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls indirect signature '{}' which was never created",
                self.func_name.as_str(),
                sig.as_str()
            ))
        })?;
        let sig_ref = self.builder.import_signature(signature.clone());
        let callee = self.value(callee)?;
        let args = self.values(args)?;
        self.builder.ins().call_indirect(sig_ref, callee, &args);
        Ok(())
    }

    fn take_single_result(&mut self, inst: cranelift_codegen::ir::Inst, target: &str) -> Result<Value, MoonliftError> {
        let results = self.builder.inst_results(inst);
        if results.len() != 1 {
            return Err(MoonliftError::new(format!(
                "call target '{}' produced {} results; the current BackCmd value-call subset expects exactly one result",
                target,
                results.len()
            )));
        }
        Ok(results[0])
    }

    fn bind_value(&mut self, id: &BackValId, value: Value) -> Result<(), MoonliftError> {
        if self.values.insert(id.clone(), value).is_some() {
            return Err(MoonliftError::new(format!(
                "function '{}' bound value '{}' more than once",
                self.func_name.as_str(),
                id.as_str()
            )));
        }
        Ok(())
    }

    fn value(&self, id: &BackValId) -> Result<Value, MoonliftError> {
        self.values.get(id).copied().ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown value '{}'",
                self.func_name.as_str(),
                id.as_str()
            ))
        })
    }

    fn values(&self, ids: &[BackValId]) -> Result<Vec<Value>, MoonliftError> {
        ids.iter().map(|id| self.value(id)).collect()
    }

    fn require_value_type(
        &self,
        id: &BackValId,
        value: Value,
        expected: Type,
        role: &str,
    ) -> Result<(), MoonliftError> {
        let actual = self.builder.func.dfg.value_type(value);
        if actual != expected {
            return Err(MoonliftError::new(format!(
                "function '{}' uses {} '{}' with CLIF type {:?}, expected {:?}",
                self.func_name.as_str(),
                role,
                id.as_str(),
                actual,
                expected
            )));
        }
        Ok(())
    }

    fn byte_fill_value(&mut self, id: &BackValId) -> Result<Value, MoonliftError> {
        let value = self.value(id)?;
        let actual = self.builder.func.dfg.value_type(value);
        if !actual.is_int() {
            return Err(MoonliftError::new(format!(
                "function '{}' uses BackCmdMemset byte '{}' with non-integer CLIF type {:?}",
                self.func_name.as_str(),
                id.as_str(),
                actual
            )));
        }
        if actual == types::I8 {
            return Ok(value);
        }
        Ok(self.builder.ins().ireduce(types::I8, value))
    }

    fn block_args(&self, ids: &[BackValId]) -> Result<Vec<BlockArg>, MoonliftError> {
        ids.iter()
            .map(|id| self.value(id).map(BlockArg::Value))
            .collect()
    }

    fn cond_value(&mut self, id: &BackValId) -> Result<Value, MoonliftError> {
        let raw = self.value(id)?;
        Ok(self.builder.ins().icmp_imm(IntCC::NotEqual, raw, 0))
    }

    fn block(&self, id: &BackBlockId) -> Result<Block, MoonliftError> {
        self.blocks.get(id).copied().ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown block '{}'",
                self.func_name.as_str(),
                id.as_str()
            ))
        })
    }

    fn stack_slot(&self, id: &BackStackSlotId) -> Result<StackSlot, MoonliftError> {
        self.stack_slots.get(id).copied().ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown stack slot '{}'",
                self.func_name.as_str(),
                id.as_str()
            ))
        })
    }

    fn data(&self, id: &BackDataId) -> Result<DataId, MoonliftError> {
        self.datas
            .get(id)
            .and_then(|decl| decl.data_id)
            .ok_or_else(|| {
                MoonliftError::new(format!(
                    "function '{}' references unknown data object '{}'",
                    self.func_name.as_str(),
                    id.as_str()
                ))
            })
    }
}

fn bool_value_from_cond(builder: &mut FunctionBuilder<'_>, cond: Value) -> Value {
    let one = builder.ins().iconst(types::I8, 1);
    let zero = builder.ins().iconst(types::I8, 0);
    builder.ins().select(cond, one, zero)
}

fn make_signature<M: Module>(module: &M, params: &[BackScalar], results: &[BackScalar]) -> Signature {
    let ptr_ty = module.target_config().pointer_type();
    let mut sig = module.make_signature();
    for param in params {
        sig.params.push(AbiParam::new(param.clif_type(ptr_ty)));
    }
    for result in results {
        sig.returns.push(AbiParam::new(result.clif_type(ptr_ty)));
    }
    sig
}

fn lower_const_int(
    builder: &mut FunctionBuilder<'_>,
    ptr_ty: Type,
    ty: BackScalar,
    raw: &str,
) -> Result<Value, MoonliftError> {
    let clif_ty = ty.clif_type(ptr_ty);
    let imm = match ty {
        BackScalar::Bool => {
            return Err(MoonliftError::new(
                "BackCmdConstInt cannot build a bool; use BackCmdConstBool instead",
            ))
        }
        BackScalar::I8 | BackScalar::I16 | BackScalar::I32 | BackScalar::I64 => raw.parse::<i64>().map_err(|e| {
            MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw))
        })?,
        BackScalar::U8
        | BackScalar::U16
        | BackScalar::U32
        | BackScalar::U64
        | BackScalar::Ptr
        | BackScalar::Index => raw.parse::<u64>().map_err(|e| {
            MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw))
        })? as i64,
        BackScalar::F32 | BackScalar::F64 => {
            return Err(MoonliftError::new(
                "BackCmdConstInt cannot build a float; use BackCmdConstFloat instead",
            ))
        }
    };
    Ok(builder.ins().iconst(clif_ty, imm))
}

fn lower_const_float(
    builder: &mut FunctionBuilder<'_>,
    ty: BackScalar,
    raw: &str,
) -> Result<Value, MoonliftError> {
    match ty {
        BackScalar::F32 => {
            let value = raw.parse::<f32>().map_err(|e| {
                MoonliftError::new(format!("failed to parse f32 literal '{}': {e}", raw))
            })?;
            Ok(builder.ins().f32const(Ieee32::with_float(value)))
        }
        BackScalar::F64 => {
            let value = raw.parse::<f64>().map_err(|e| {
                MoonliftError::new(format!("failed to parse f64 literal '{}': {e}", raw))
            })?;
            Ok(builder.ins().f64const(Ieee64::with_float(value)))
        }
        _ => Err(MoonliftError::new(
            "BackCmdConstFloat requires BackF32 or BackF64",
        )),
    }
}

fn write_data_bytes(dst: &mut [u8], offset: usize, src: &[u8], what: &str) -> Result<(), MoonliftError> {
    let end = offset.checked_add(src.len()).ok_or_else(|| {
        MoonliftError::new(format!("{} write overflowed offset arithmetic", what))
    })?;
    if end > dst.len() {
        return Err(MoonliftError::new(format!(
            "{} write [{}..{}) exceeds data object size {}",
            what,
            offset,
            end,
            dst.len()
        )));
    }
    dst[offset..end].copy_from_slice(src);
    Ok(())
}

fn write_data_init(bytes: &mut [u8], ptr_ty: Type, init: &DataInit) -> Result<(), MoonliftError> {
    match init {
        DataInit::Zero { offset, size } => {
            let start = *offset as usize;
            let len = *size as usize;
            let end = start.checked_add(len).ok_or_else(|| {
                MoonliftError::new("data zero-init overflowed offset arithmetic")
            })?;
            if end > bytes.len() {
                return Err(MoonliftError::new(format!(
                    "data zero-init [{}..{}) exceeds data object size {}",
                    start,
                    end,
                    bytes.len()
                )));
            }
            for b in &mut bytes[start..end] {
                *b = 0;
            }
            Ok(())
        }
        DataInit::Int { offset, ty, raw } => {
            let data = match ty {
                BackScalar::Bool => {
                    return Err(MoonliftError::new(
                        "BackCmdDataInitInt cannot build a bool; use BackCmdDataInitBool instead",
                    ))
                }
                BackScalar::I8 => (raw.parse::<i8>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::I16 => (raw.parse::<i16>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::I32 => (raw.parse::<i32>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::I64 => (raw.parse::<i64>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U8 => (raw.parse::<u8>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U16 => (raw.parse::<u16>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U32 => (raw.parse::<u32>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U64 => (raw.parse::<u64>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::Ptr | BackScalar::Index => {
                    if ptr_ty.bytes() == 8 {
                        (raw.parse::<u64>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec()
                    } else {
                        (raw.parse::<u32>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec()
                    }
                }
                BackScalar::F32 | BackScalar::F64 => {
                    return Err(MoonliftError::new(
                        "BackCmdDataInitInt cannot build a float; use BackCmdDataInitFloat instead",
                    ))
                }
            };
            write_data_bytes(bytes, *offset as usize, &data, "data integer init")
        }
        DataInit::Float { offset, ty, raw } => {
            let data = match ty {
                BackScalar::F32 => (raw.parse::<f32>().map_err(|e| MoonliftError::new(format!("failed to parse f32 literal '{}': {e}", raw)))?).to_bits().to_le_bytes().to_vec(),
                BackScalar::F64 => (raw.parse::<f64>().map_err(|e| MoonliftError::new(format!("failed to parse f64 literal '{}': {e}", raw)))?).to_bits().to_le_bytes().to_vec(),
                _ => {
                    return Err(MoonliftError::new(
                        "BackCmdDataInitFloat requires BackF32 or BackF64",
                    ))
                }
            };
            write_data_bytes(bytes, *offset as usize, &data, "data float init")
        }
        DataInit::Bool { offset, value } => {
            write_data_bytes(bytes, *offset as usize, &[*value as u8], "data bool init")
        }
    }
}

fn align_to_shift(align: u32) -> Result<u8, MoonliftError> {
    if align == 0 {
        return Err(MoonliftError::new(
            "stack slot alignment must be >= 1 byte",
        ));
    }
    if !align.is_power_of_two() {
        return Err(MoonliftError::new(format!(
            "stack slot alignment {} is not a power of two",
            align
        )));
    }
    Ok(align.trailing_zeros() as u8)
}

fn local_symbol_name(id: &BackFuncId) -> String {
    let mut out = String::from("moonlift_fn_");
    for byte in id.as_str().as_bytes() {
        out.push(hex_digit(byte >> 4));
        out.push(hex_digit(byte & 0x0f));
    }
    out
}

fn local_data_symbol_name(id: &BackDataId) -> String {
    let mut out = String::from("moonlift_data_");
    for byte in id.as_str().as_bytes() {
        out.push(hex_digit(byte >> 4));
        out.push(hex_digit(byte & 0x0f));
    }
    out
}

fn hex_digit(n: u8) -> char {
    match n {
        0..=9 => (b'0' + n) as char,
        10..=15 => (b'a' + (n - 10)) as char,
        _ => unreachable!(),
    }
}

fn build_host_isa(is_pic: bool) -> Result<Arc<dyn cranelift_codegen::isa::TargetIsa>, MoonliftError> {
    let mut flag_builder = settings::builder();
    flag_builder
        .set("use_colocated_libcalls", "false")
        .map_err(|e| MoonliftError::new(format!("failed to set Cranelift flag use_colocated_libcalls: {e}")))?;
    flag_builder
        .set("is_pic", if is_pic { "true" } else { "false" })
        .map_err(|e| MoonliftError::new(format!("failed to set Cranelift flag is_pic: {e}")))?;
    flag_builder
        .set("opt_level", "speed")
        .map_err(|e| MoonliftError::new(format!("failed to set Cranelift flag opt_level: {e}")))?;

    let isa_builder = cranelift_native::builder()
        .map_err(|e| MoonliftError::new(format!("host machine is not supported by Cranelift: {e}")))?;
    isa_builder
        .finish(settings::Flags::new(flag_builder))
        .map_err(|e| MoonliftError::new(format!("failed to finalize Cranelift ISA: {e}")))
}

fn host_isa(is_pic: bool) -> Result<Arc<dyn cranelift_codegen::isa::TargetIsa>, MoonliftError> {
    static JIT_ISA: OnceLock<Arc<dyn cranelift_codegen::isa::TargetIsa>> = OnceLock::new();
    static PIC_ISA: OnceLock<Arc<dyn cranelift_codegen::isa::TargetIsa>> = OnceLock::new();
    let slot = if is_pic { &PIC_ISA } else { &JIT_ISA };
    if let Some(isa) = slot.get() {
        return Ok(Arc::clone(isa));
    }
    let isa = build_host_isa(is_pic)?;
    let _ = slot.set(Arc::clone(&isa));
    Ok(isa)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem;

    fn int_wrap() -> BackIntSemantics { BackIntSemantics::wrapping() }

    fn test_mem(access: &str, mode: BackAccessMode) -> BackMemoryInfo {
        BackMemoryInfo::new(
            BackAccessId::from(access),
            BackAlignment::Known(4),
            BackDereference::Bytes(4),
            BackTrap::NonTrapping,
            BackMotion::MayNotMove,
            mode,
        )
    }

    #[test]
    fn back_memory_info_maps_only_exact_cranelift_flags() {
        let movable = BackMemoryInfo::new(
            BackAccessId::from("a"),
            BackAlignment::Known(4),
            BackDereference::Bytes(4),
            BackTrap::NonTrapping,
            BackMotion::CanMove,
            BackAccessMode::Read,
        );
        let flags = movable.memflags(4, 4);
        assert!(flags.notrap());
        assert!(flags.aligned());
        assert!(flags.can_move());
        assert!(flags.trap_code().is_none());
        assert!(!flags.readonly());

        let under_aligned = BackMemoryInfo::new(
            BackAccessId::from("b"),
            BackAlignment::Known(4),
            BackDereference::Bytes(8),
            BackTrap::MayTrap,
            BackMotion::MayNotMove,
            BackAccessMode::Read,
        );
        let flags = under_aligned.memflags(8, 8);
        assert!(flags.notrap());
        assert!(!flags.aligned());
        assert!(!flags.can_move());

        let checked = BackMemoryInfo::new(
            BackAccessId::from("c"),
            BackAlignment::Unknown,
            BackDereference::Unknown,
            BackTrap::Checked,
            BackMotion::MayNotMove,
            BackAccessMode::Write,
        );
        let flags = checked.memflags(4, 4);
        assert!(flags.trap_code().is_some());
        assert!(!flags.notrap());
    }

    #[test]
    fn compiles_and_calls_exported_function() {
        let jit = Jit::new();
        let program = BackProgram::partition(vec![
            BackCmd::CreateSig(BackSigId::from("sig:add1"), vec![BackScalar::I32], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("add1"), BackSigId::from("sig:add1")),
            BackCmd::BeginFunc(BackFuncId::from("add1")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::BindEntryParams(BackBlockId::from("entry"), vec![BackValId::from("arg")]),
            BackCmd::ConstInt(BackValId::from("one"), BackScalar::I32, "1".to_string()),
            BackCmd::Iadd(
                BackValId::from("sum"),
                BackScalar::I32,
                int_wrap(),
                BackValId::from("arg"),
                BackValId::from("one"),
            ),
            BackCmd::ReturnValue(BackValId::from("sum")),
            BackCmd::SealBlock(BackBlockId::from("entry")),
            BackCmd::FinishFunc(BackFuncId::from("add1")),
            BackCmd::FinalizeModule,
        ]).unwrap();

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("add1").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn(i32) -> i32>(ptr) };
        assert_eq!(f(41), 42);
    }

    extern "C" fn triple(x: i32) -> i32 {
        x * 3
    }

    #[test]
    fn compiles_and_calls_registered_extern() {
        let mut jit = Jit::new();
        jit.symbol("triple_host", triple as *const u8);

        let program = BackProgram::partition(vec![
            BackCmd::CreateSig(BackSigId::from("sig:triple"), vec![BackScalar::I32], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExtern(
                BackExternId::from("triple"),
                "triple_host".to_string(),
                BackSigId::from("sig:triple"),
            ),
            BackCmd::CreateSig(BackSigId::from("sig:caller"), vec![BackScalar::I32], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("caller"), BackSigId::from("sig:caller")),
            BackCmd::BeginFunc(BackFuncId::from("caller")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::BindEntryParams(BackBlockId::from("entry"), vec![BackValId::from("arg")]),
            BackCmd::CallValueExtern(
                BackValId::from("ret"),
                BackScalar::I32,
                BackExternId::from("triple"),
                BackSigId::from("sig:triple"),
                vec![BackValId::from("arg")],
            ),
            BackCmd::ReturnValue(BackValId::from("ret")),
            BackCmd::SealBlock(BackBlockId::from("entry")),
            BackCmd::FinishFunc(BackFuncId::from("caller")),
            BackCmd::FinalizeModule,
        ]).unwrap();

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("caller").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn(i32) -> i32>(ptr) };
        assert_eq!(f(14), 42);
    }

    #[test]
    fn compiles_and_reads_data_object() {
        let jit = Jit::new();
        let program = BackProgram::partition(vec![
            BackCmd::DeclareData(BackDataId::from("const:k"), 4, 4),
            BackCmd::DataInitInt(BackDataId::from("const:k"), 0, BackScalar::I32, "42".to_string()),
            BackCmd::CreateSig(BackSigId::from("sig:getk"), vec![], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("getk"), BackSigId::from("sig:getk")),
            BackCmd::BeginFunc(BackFuncId::from("getk")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::DataAddr(BackValId::from("addr"), BackDataId::from("const:k")),
            BackCmd::LoadInfo(BackValId::from("value"), BackScalar::I32, BackValId::from("addr"), test_mem("getk:load", BackAccessMode::Read)),
            BackCmd::ReturnValue(BackValId::from("value")),
            BackCmd::SealBlock(BackBlockId::from("entry")),
            BackCmd::FinishFunc(BackFuncId::from("getk")),
            BackCmd::FinalizeModule,
        ]).unwrap();

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("getk").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn() -> i32>(ptr) };
        assert_eq!(f(), 42);
    }

    #[test]
    fn compiles_block_param_loop_cfg() {
        let jit = Jit::new();
        let program = BackProgram::partition(vec![
            BackCmd::CreateSig(BackSigId::from("sig:count"), vec![], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("count"), BackSigId::from("sig:count")),
            BackCmd::BeginFunc(BackFuncId::from("count")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::CreateBlock(BackBlockId::from("header")),
            BackCmd::CreateBlock(BackBlockId::from("body")),
            BackCmd::CreateBlock(BackBlockId::from("exit")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::AppendBlockParam(BackBlockId::from("header"), BackValId::from("header.i"), BackScalar::I32),
            BackCmd::AppendBlockParam(BackBlockId::from("body"), BackValId::from("body.i"), BackScalar::I32),
            BackCmd::AppendBlockParam(BackBlockId::from("exit"), BackValId::from("exit.i"), BackScalar::I32),
            BackCmd::ConstInt(BackValId::from("zero"), BackScalar::I32, "0".to_string()),
            BackCmd::Jump(BackBlockId::from("header"), vec![BackValId::from("zero")]),
            BackCmd::SwitchToBlock(BackBlockId::from("header")),
            BackCmd::Alias(BackValId::from("i"), BackValId::from("header.i")),
            BackCmd::ConstInt(BackValId::from("limit"), BackScalar::I32, "4".to_string()),
            BackCmd::SIcmpLt(
                BackValId::from("cond"),
                BackScalar::Bool,
                BackValId::from("i"),
                BackValId::from("limit"),
            ),
            BackCmd::BrIf(
                BackValId::from("cond"),
                BackBlockId::from("body"),
                vec![BackValId::from("header.i")],
                BackBlockId::from("exit"),
                vec![BackValId::from("header.i")],
            ),
            BackCmd::SealBlock(BackBlockId::from("body")),
            BackCmd::SealBlock(BackBlockId::from("exit")),
            BackCmd::SwitchToBlock(BackBlockId::from("body")),
            BackCmd::Alias(BackValId::from("i"), BackValId::from("body.i")),
            BackCmd::ConstInt(BackValId::from("one"), BackScalar::I32, "1".to_string()),
            BackCmd::Iadd(
                BackValId::from("next"),
                BackScalar::I32,
                int_wrap(),
                BackValId::from("i"),
                BackValId::from("one"),
            ),
            BackCmd::Jump(BackBlockId::from("header"), vec![BackValId::from("next")]),
            BackCmd::SealBlock(BackBlockId::from("header")),
            BackCmd::SwitchToBlock(BackBlockId::from("exit")),
            BackCmd::Alias(BackValId::from("result"), BackValId::from("exit.i")),
            BackCmd::ReturnValue(BackValId::from("result")),
            BackCmd::FinishFunc(BackFuncId::from("count")),
            BackCmd::FinalizeModule,
        ]).unwrap();

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("count").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn() -> i32>(ptr) };
        assert_eq!(f(), 4);
    }

    #[test]
    fn compiles_memcpy_command() {
        let jit = Jit::new();
        let program = BackProgram::partition(vec![
            BackCmd::CreateSig(
                BackSigId::from("sig:copy_i32"),
                vec![BackScalar::Ptr, BackScalar::Ptr],
                vec![BackScalar::I32],
            ),
            BackCmd::DeclareFuncExport(BackFuncId::from("copy_i32"), BackSigId::from("sig:copy_i32")),
            BackCmd::BeginFunc(BackFuncId::from("copy_i32")),
            BackCmd::CreateBlock(BackBlockId::from("entry.copy_i32")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry.copy_i32")),
            BackCmd::BindEntryParams(
                BackBlockId::from("entry.copy_i32"),
                vec![BackValId::from("dst"), BackValId::from("src")],
            ),
            BackCmd::ConstInt(BackValId::from("len"), BackScalar::Index, "4".to_string()),
            BackCmd::Memcpy(
                BackValId::from("dst"),
                BackValId::from("src"),
                BackValId::from("len"),
            ),
            BackCmd::LoadInfo(BackValId::from("value"), BackScalar::I32, BackValId::from("dst"), test_mem("copy_i32:load", BackAccessMode::Read)),
            BackCmd::ReturnValue(BackValId::from("value")),
            BackCmd::SealBlock(BackBlockId::from("entry.copy_i32")),
            BackCmd::FinishFunc(BackFuncId::from("copy_i32")),
            BackCmd::FinalizeModule,
        ]).unwrap();

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("copy_i32").unwrap();
        let f = unsafe {
            mem::transmute::<*const c_void, extern "C" fn(*mut i32, *const i32) -> i32>(ptr)
        };

        let src = 42i32;
        let mut dst = 0i32;
        assert_eq!(f(&mut dst, &src), 42);
        assert_eq!(dst, 42);
    }

    #[test]
    fn compiles_memset_command() {
        let jit = Jit::new();
        let program = BackProgram::partition(vec![
            BackCmd::CreateSig(
                BackSigId::from("sig:zero_i32"),
                vec![BackScalar::Ptr],
                vec![BackScalar::I32],
            ),
            BackCmd::DeclareFuncExport(BackFuncId::from("zero_i32"), BackSigId::from("sig:zero_i32")),
            BackCmd::BeginFunc(BackFuncId::from("zero_i32")),
            BackCmd::CreateBlock(BackBlockId::from("entry.zero_i32")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry.zero_i32")),
            BackCmd::BindEntryParams(BackBlockId::from("entry.zero_i32"), vec![BackValId::from("dst")]),
            BackCmd::ConstInt(BackValId::from("byte"), BackScalar::U8, "0".to_string()),
            BackCmd::ConstInt(BackValId::from("len"), BackScalar::Index, "4".to_string()),
            BackCmd::Memset(
                BackValId::from("dst"),
                BackValId::from("byte"),
                BackValId::from("len"),
            ),
            BackCmd::LoadInfo(BackValId::from("value"), BackScalar::I32, BackValId::from("dst"), test_mem("zero_i32:load", BackAccessMode::Read)),
            BackCmd::ReturnValue(BackValId::from("value")),
            BackCmd::SealBlock(BackBlockId::from("entry.zero_i32")),
            BackCmd::FinishFunc(BackFuncId::from("zero_i32")),
            BackCmd::FinalizeModule,
        ]).unwrap();

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("zero_i32").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn(*mut i32) -> i32>(ptr) };

        let mut dst = 0x7f7f7f7fi32;
        assert_eq!(f(&mut dst), 0);
        assert_eq!(dst, 0);
    }
}
