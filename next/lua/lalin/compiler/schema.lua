local asdl = require("asdl")

local Compiler = asdl.NewContext()

Compiler:Define [[
module Source {
  Name = (string text) unique
  QualifiedName = (Name* parts) unique
  Path = (string text) unique
  Ordinal = (number value)
  ByteOffset = (number value) unique
  ByteLength = (number value) unique
  Range = (ByteOffset start, ByteLength length) unique
  File = (Path path, string bytes)

  Origin = Written(File file, Range range)
         | Built(string source, Ordinal ordinal)
         | Generated(Origin parent, GenerationCause cause, Ordinal ordinal)

  GenerationCause = MetaGeneration(MetaQuery query)
                  | ClosureGeneration(ClosureExpression closure)
                  | RegionExpansion(RegionEmitStatement invocation)
                  | RegionCallGeneration(RegionCallStatement invocation)
                  | CodeGeneration() unique
                  | AnalysisGeneration() unique
                  | BackendGeneration() unique
                  | HostEvalGeneration(Origin host_site)
  Visibility = LocalVisibility() unique
             | ExportVisibility() unique

  Linkage = InternalLinkage() unique
          | ExportLinkage() unique
          | ExternalLinkage() unique

  Symbol = (string name, Linkage linkage) unique

  Program = DocumentProgram(File file, Declaration* declarations, Provenance.Generation generation)
          | BuilderProgram(string source, Declaration* declarations, Provenance.Generation generation)
          | DerivedProgram(Program parent, GenerationCause cause, Declaration* declarations, Provenance.Generation generation)
  DeclarationHeader = (QualifiedName name, Visibility visibility, Origin origin)
  Binding = (Name name, Origin origin)
  Parameter = (Binding binding, TypeForm type, Origin origin)
  Field = (Name name, TypeForm type, Origin origin)
  Variant = (Name name, Field* fields, Origin origin)
  Continuation = (Name name, Parameter* parameters, Origin origin)
  UniqueIdentityAuthority = StorageIdentity(TypeForm storage)
                          | HandleIdentity(TypeUse handle)
                          | AllocatorIdentity(ValueUse allocator)

  Initializer = NoInitializer() unique
              | InitialValue(Expression value)

  HandleInvalid = NoInvalidHandleValue() unique
                | InvalidHandleValue(Expression value)

  HandleAuthority = ScalarHandle() unique
                  | DomainHandle(TypeForm domain, TypeForm target)

  Declaration = FunctionDeclaration(DeclarationHeader header, Parameter* parameters, TypeForm result, Contract* contracts, Body body)
              | ExternDeclaration(DeclarationHeader header, Symbol symbol, Parameter* parameters, TypeForm result, Contract* contracts, DeclaredEffectAtom* effects)
              | StructDeclaration(DeclarationHeader header, Field* fields)
              | UniqueStructDeclaration(DeclarationHeader header, Field* fields, UniqueIdentityAuthority identity_authority)
              | UnionDeclaration(DeclarationHeader header, Variant* variants)
              | HandleDeclaration(DeclarationHeader header, TypeForm representation, HandleInvalid invalid, HandleAuthority authority)
              | RegionDeclaration(DeclarationHeader header, Parameter* parameters, Continuation* continuations, BlockBody body)
              | ConstantDeclaration(DeclarationHeader header, TypeForm type, Expression value)
              | StaticDeclaration(DeclarationHeader header, TypeForm type, Initializer initializer)


  ValueUse = (QualifiedName name, Origin origin)
  TypeUse = (QualifiedName name, Origin origin)
  FieldUse = (Name name, Origin origin)
  VariantUse = (QualifiedName name, Origin origin)
  RegionUse = (QualifiedName name, Origin origin)
  ContinuationUse = (Name name, Origin origin)
  BlockUse = (Name name, Origin origin)

  LeaseOriginForm = AnonymousLease() unique
                  | ParameterLease(ValueUse parameter)

  TypeForm = VoidType()
           | BoolType()
           | SignedIntegerType(number bits)
           | UnsignedIntegerType(number bits)
           | FloatType(number bits)
           | IndexType()
           | RawPointerType()
           | PointerType(TypeForm element)
           | ArrayType(TypeForm element, Expression extent)
           | SliceType(TypeForm element)
           | ViewType(TypeForm element, number rank)
           | LeaseType(LeaseOriginForm lease_origin, TypeForm value_type)
           | OwnedType(TypeForm value_type)
           | ReadonlyType(TypeForm value_type)
           | WriteonlyType(TypeForm value_type)
           | NoaliasType(TypeForm value_type)
           | NoescapeType(TypeForm value_type)
           | InvalidateType(TypeForm value_type)
           | PreserveType(TypeForm value_type)
           | FunctionType(TypeForm* parameters, TypeForm result)
           | ClosureType(TypeForm* parameters, TypeForm result)
           | NamedType(TypeUse name)
           | ImportedCType(string spelling)
           | ImportedFunctionPointerType(string spelling, TypeForm* parameters, TypeForm result)
             attributes (Origin origin)

  UnaryOperator = Negate() unique
                | LogicalNot() unique
                | BitwiseNot() unique

  BinaryOperator = Add() unique
                 | Subtract() unique
                 | Multiply() unique
                 | Divide() unique
                 | IntegerDivide() unique
                 | Remainder() unique
                 | BitwiseAnd() unique
                 | BitwiseOr() unique
                 | BitwiseXor() unique
                 | ShiftLeft() unique
                 | LogicalShiftRight() unique
                 | ArithmeticShiftRight() unique

  BuiltinReducer = AddReducer() unique
                 | MultiplyReducer() unique
                 | BitAndReducer() unique
                 | BitOrReducer() unique
                 | BitXorReducer() unique
                 | MinReducer() unique
                 | MaxReducer() unique


  ComparisonOperator = Equal() unique
                     | NotEqual() unique
                     | Less() unique
                     | LessEqual() unique
                     | Greater() unique
                     | GreaterEqual() unique

  LogicOperator = LogicalAnd() unique
                | LogicalOr() unique


  Intrinsic = Popcount() unique
            | CountLeadingZeros() unique
            | CountTrailingZeros() unique
            | RotateLeft() unique
            | RotateRight() unique
            | ByteSwap() unique
            | FusedMultiplyAdd() unique
            | SquareRoot() unique
            | AbsoluteValue() unique
            | Floor() unique
            | Ceil() unique
            | TruncateFloat() unique
            | Round() unique
            | TrapIntrinsic() unique
            | Assume() unique

  AtomicOperator = AtomicAdd() unique
                 | AtomicSubtract() unique
                 | AtomicAnd() unique
                 | AtomicOr() unique
                 | AtomicXor() unique
                 | AtomicExchange() unique


  Overflow = ExactOverflow() unique
           | WrappingOverflow() unique
           | UndefinedOverflow() unique
           | SaturatingOverflow() unique

  FloatMode = ExactFloat() unique
            | IeeeFloat() unique
            | FastFloat() unique

  TrapMode = Nontrapping() unique
           | MayTrap() unique
           | MustTrap() unique

  Volatility = Nonvolatile() unique
             | Volatile() unique



  Expression = IntegerLiteral(string raw)
             | FloatLiteral(string raw)
             | BooleanLiteral(boolean value)
             | StringLiteral(string bytes)
             | NilLiteral()
             | ValueReference(ValueUse use)
             | UnaryExpression(UnaryOperator operator, Expression operand)
             | BinaryExpression(BinaryOperator operator, Expression left, Expression right)
             | CompareExpression(ComparisonOperator operator, Expression left, Expression right)
             | LogicExpression(LogicOperator operator, Expression left, Expression right)
             | CastExpression(TypeForm target, Expression value)
             | IntrinsicExpression(Intrinsic intrinsic, Expression* arguments)
             | AddressOfExpression(Place place)
             | DereferenceExpression(Expression pointer)
             | CallExpression(Expression callee, CallArgument* arguments)
             | MethodCallExpression(Expression receiver, Name method, CallArgument* arguments)
             | LengthExpression(Expression value)
             | FieldExpression(Expression base, FieldUse field)
             | IndexExpression(Expression base, Expression index)
             | LoadExpression(Place place)
             | AtomicLoadExpression(Place place)
             | AtomicRmwExpression(AtomicOperator operation, Place place, Expression value)
             | AtomicCompareExchangeExpression(Place place, Expression expected, Expression replacement)
             | AggregateExpression(AggregateField* fields)
             | ArrayExpression(Expression* elements)
             | SelectExpression(Expression condition, Expression true_value, Expression false_value)
             | ClosureExpression(Parameter* parameters, TypeForm result, Body body)
             | ViewExpression(Expression data, Expression length, Expression stride)
             | ConstructorExpression(VariantUse constructor, Expression* arguments)
             | NullExpression(TypeForm target)
             | SizeOfExpression(TypeForm target)
             | AlignOfExpression(TypeForm target)
             | IsNullExpression(Expression value)
             | ReprExpression(Expression handle)
             | FromReprExpression(TypeForm handle_type, Expression raw)
               attributes (Origin origin)

  AggregateField = (FieldUse field, Expression value)

  Place = BindingPlace(ValueUse use)
        | DereferencePlace(Expression pointer)
        | FieldPlace(Place base, FieldUse field)
        | IndexPlace(Place base, Expression index)
          attributes (Origin origin)

  Pattern = BindingPattern(Binding binding)
          | VariantPattern(VariantUse variant, Pattern* fields)
          | WildcardPattern()
            attributes (Origin origin)

  Argument = PositionalArgument(Expression value)
           | NamedArgument(Name name, Expression value)

  CallArgument = (Argument argument, Contract* requires)

  ContinuationWire = (ContinuationUse exit, ControlApplication target)
  ControlApplication = (ControlTarget target, Argument* arguments)
  ControlTarget = BlockTarget(BlockUse block)
                | ContinuationTarget(ContinuationUse continuation)

  RegionInvocation = (RegionUse region, Expression* arguments, ContinuationWire* continuations)

  LoopAxis = (Binding binding, Expression start, Expression stop, Expression step)
  TileAxis = (Binding outer, Binding inner, Expression start, Expression stop, Expression tile)
  WindowBoundary = ClampBoundary() unique
                 | WrapBoundary() unique
                 | ZeroBoundary() unique
                 | RejectBoundary() unique

  ScanMode = InclusiveScan() unique
           | ExclusiveScan() unique

  WindowAxis = (Binding binding, Expression start, Expression stop, Expression before, Expression after, WindowBoundary boundary)

  LoopDomain = RangeDomain(LoopAxis axis)
             | GridDomain(LoopAxis* axes)
             | TiledDomain(TileAxis* axes)
             | WindowDomain(WindowAxis* axes)
             | TraversalDomain(Expression source)

  Statement = LetStatement(Binding binding, TypeForm type, Initializer initializer)
            | VarStatement(Binding binding, TypeForm type, Initializer initializer)
            | AssignmentStatement(Place place, Expression value)
            | AtomicStoreStatement(Place place, Expression value)
            | AtomicFenceStatement()
            | ExpressionStatement(Expression expression)
            | AssertStatement(Expression condition)
            | IfStatement(Expression condition, Statement* then_body, Statement* else_body)
            | SwitchStatement(Expression selector, StatementSwitchArm* arms, Statement* default_body)
            | VariantSwitchStatement(Expression selector, VariantSwitchArm* arms, Statement* default_body)
            | LoopStatement(LoopDomain domain, Statement* body)
            | FoldStatement(Binding accumulator, TypeForm type, Expression initial, BuiltinReducer reducer, Expression step)
            | ScanStatement(Binding accumulator, TypeForm type, Expression initial, BuiltinReducer reducer, ScanMode mode, Expression axis, Expression step, Place destination)
            | ReturnVoidStatement()
            | ReturnValueStatement(Expression value)
            | YieldVoidStatement()
            | YieldValueStatement(Expression value)
            | JumpStatement(ControlApplication target)
            | ConditionalJumpStatement(Expression condition, ControlApplication true_target, ControlApplication false_target)
            | ContractStatement(Contract* contracts)
            | RegionEmitStatement(RegionInvocation invocation)
            | RegionCallStatement(RegionInvocation invocation)
            | TrapStatement()
              attributes (Origin origin)

  StatementSwitchArm = (Expression match_value, Statement* body)
  VariantSwitchArm = (Pattern pattern, Statement* body)

  Body = StatementBody(Statement* statements)
       | ExplicitBlockBody(BlockBody body)

  BlockBody = (Block entry, Block* blocks)
  Block = (Name name, Parameter* parameters, Statement* statements, Origin origin)

  Contract = BoundsContract(Place subject, Expression lower, Expression upper)
           | WindowBoundsContract(Place subject, Expression lower, Expression upper)
           | DisjointContract(Place left, Place right)
           | SameLengthContract(Place left, Place right)
           | SoAComponentContract(Place aggregate, Place component)
           | PairNoaliasContract(Place left, Place right)
           | UnaryNoaliasContract(Place subject)
           | ReadonlyContract(Place subject)
           | WriteonlyContract(Place subject)
           | InvalidateContract(Place subject)
           | PreserveContract(Place subject)
           | NoescapeContract(Expression subject)
             attributes (Origin origin)

  DeclaredEffectAtom = ReadEffect() unique
                     | WriteEffect() unique
                     | PreserveEffect() unique
                     | InvalidateEffect() unique
                     | NoescapeEffect() unique
                     | RetainEffect() unique
                     | TrapEffect() unique
                     | VolatileEffect() unique
                     | AtomicEffect() unique
                     | AllocateEffect() unique
                     | ExternalEffect() unique

  MetaQuery = TypeNameQuery(Program program, TypeForm subject, Name requested)
            | EntriesQuery(Program program, TypeForm subject)
            | DeclarationsQuery(Program program, TypeForm subject)
            | MethodQuery(Program program, TypeForm subject, Name method)
            | MissingMethodQuery(Program program, TypeForm subject, Name method)
            | MissingEntryQuery(Program program, TypeForm subject, Name entry)
            | ApplyQuery(Program program, TypeForm subject, MetaArgument* arguments)
            | CastQuery(Program program, TypeForm subject, TypeForm target)
              attributes (Origin origin)

  MetaArgument = MetaType(TypeForm type)
               | MetaDeclaration(Declaration declaration)
               | MetaInteger(string raw)
               | MetaFloat(string raw)
               | MetaBoolean(boolean value)
               | MetaString(string value)
}

module Provenance {
  Generation = (string key) unique

  Expectation = GenerationExpectation(Generation expected, Generation actual)
              | TargetExpectation(Target.Spec expected, Target.Spec actual)
}

module Target {
  Endianness = LittleEndian() unique
             | BigEndian() unique

  PointerWidth = Pointer32() unique
               | Pointer64() unique

  IndexWidth = Index32() unique
             | Index64() unique

  IntegerModel = Ilp32() unique
               | Lp64() unique
               | Llp64() unique

  Spec = (string triple, PointerWidth pointer_width, IndexWidth index_width, Endianness endianness, IntegerModel integer_model) unique

  Optimization = (boolean prefer_baseline, boolean permit_closed_form, boolean permit_fusion) unique


  TailPermission = ExactTailOnly() unique
                 | PermitScalarRemainder() unique

  LayoutPolicy = NaturalLayout() unique
               | PackedLayout(number alignment) unique

  Policy = (Optimization optimization, TailPermission tail, LayoutPolicy layout) unique

  EmitterFeature = BaselineControl() unique
                 | Aggregates() unique
                 | Closures() unique
                 | Variants() unique
                 | Atomics() unique
                 | FusedRegions() unique

  EmitterCapability = (Spec target, EmitterFeature* features) unique
}

module Types {
  Access = Readonly() unique
         | Writeonly() unique
         | Noalias() unique
         | Noescape() unique
         | Invalidate() unique
         | Preserve() unique


  Type = Void() unique
       | Bool() unique
       | SignedInteger(number bits) unique
       | UnsignedInteger(number bits) unique
       | Float(number bits) unique
       | Index() unique
       | RawPointer() unique
       | Pointer(Type element) unique
       | Array(Type element, number extent) unique
       | Slice(Type element) unique
       | View(Type element, number rank) unique
       | Lease(Type value_type, Semantic.LeaseOrigin origin) unique
       | Owned(Type value_type) unique
       | Qualified(Access access, Type value_type) unique
       | Function(Type* parameters, Type result) unique
       | Closure(Type* parameters, Type result) unique
       | Struct(Source.StructDeclaration declaration) unique
       | UniqueStruct(Source.UniqueStructDeclaration declaration) unique
       | Union(Source.UnionDeclaration declaration) unique
       | Handle(Source.HandleDeclaration declaration) unique
       | ImportedC(string spelling) unique
       | ImportedFunctionPointer(string spelling, Type* parameters, Type result) unique

  Constant = IntegerConstant(string raw, string value, Type type) unique
           | FloatConstant(string raw, string value, Type type) unique
           | BooleanConstant(boolean value) unique
           | StringConstant(string bytes) unique
           | NullConstant(Type type) unique
           | AggregateConstant(Constant* fields) unique
           | ArrayConstant(Constant* elements) unique
           | ReferenceConstant(Semantic.ReferenceTarget target, Type type) unique

  Layout = ScalarLayout(Type type, Target.Spec target, Target.LayoutPolicy policy, number size, number alignment)
         | PointerLayout(Type type, Target.Spec target, Target.LayoutPolicy policy, number size, number alignment)
         | ArrayLayout(Type type, Target.Spec target, Target.LayoutPolicy policy, number size, number alignment, number stride, number extent)
         | AggregateLayout(Type type, Target.Spec target, Target.LayoutPolicy policy, number size, number alignment, FieldLayout* fields)
         | UnionLayout(Type type, Target.Spec target, Target.LayoutPolicy policy, number size, number alignment, TagLayout tag, VariantLayout* variants)
         | HandleLayout(Type type, Target.Spec target, Target.LayoutPolicy policy, number size, number alignment)
         | ImportedLayout(Type type, Target.Spec target, Target.LayoutPolicy policy, number size, number alignment)

  FieldLayout = (Semantic.Field field, number offset, Layout layout)
  VariantLayout = (Semantic.Variant variant, number discriminant, number payload_offset, PayloadLayout payload)
  PayloadLayout = EmptyPayload() unique
                | PresentPayload(Layout layout)
  TagLayout = (number offset, number size, number alignment)

  Passing = Direct(Type type)
          | IndirectParameter(Type type, number alignment)

  AbiResult = VoidResult() unique
            | DirectResult(Type type)
            | IndirectResult(Type type, number alignment)

  CallingConvention = Cdecl() unique
                    | StdCall() unique
                    | FastCall() unique
                    | SysV64() unique
                    | Win64() unique

  CallableABI = (Semantic.Callable callable, Target.Spec target, CallingConvention convention, Passing* parameters, AbiResult result, Semantic.Erasure erasure)
}

module Semantic {
  Program = (Source.Program source, Declaration* declarations, Provenance.Generation generation)
  Mutability = Immutable() unique
             | Mutable() unique
  Binding = (Source.Binding source, Types.Type type, Mutability mutability) unique
  LeaseOrigin = AnonymousLease() unique
              | ParameterLease(Binding parameter)
  Parameter = (Source.Parameter source, Binding binding)
  Field = (Source.Field source, Types.Type type)
  Variant = (Source.Variant source, Field* fields)
  Continuation = (Source.Continuation source, Parameter* parameters)

  HandleAuthority = ScalarHandle() unique
                  | DomainHandle(Types.Type domain, Types.Type target, Region resolver)

  HandleInvalid = NoInvalidHandleValue() unique
                | InvalidHandleConstant(Types.Constant value)

  Declaration = Function(Source.FunctionDeclaration source, Parameter* parameters, Types.Type result, Contract* contracts, Body body)
              | Extern(Source.ExternDeclaration source, Parameter* parameters, Types.Type result, Contract* contracts, Source.DeclaredEffectAtom* effects)
              | Struct(Source.StructDeclaration source, Field* fields)
              | UniqueStruct(Source.UniqueStructDeclaration source, Field* fields, UniqueIdentityAuthority identity_authority)
              | Union(Source.UnionDeclaration source, Variant* variants)
              | Handle(Source.HandleDeclaration source, Types.Type representation, HandleInvalid invalid, HandleAuthority authority)
              | Region(Source.RegionDeclaration source, Parameter* parameters, Continuation* continuations, Body body)
              | ConstantDeclaration(Source.ConstantDeclaration source, Types.Type type, Types.Constant value)
              | Static(Source.StaticDeclaration source, Types.Type type, StaticInitializer initializer)

  UniqueIdentityAuthority = StorageIdentity(Types.Type storage)
                          | HandleIdentity(Types.Type handle)
                          | AllocatorIdentity(Callable allocator)

  Callable = FunctionCallable(Function fn)
           | ExternCallable(Extern extern)
           | RegionCallable(Region region)
           | ClosureCallable(ClosureExpression closure)
           | FunctionPointerCallable(Types.Type type)

  ReferenceTarget = FunctionReference(Function fn)
                  | ExternReference(Extern extern)
                  | StaticReference(Static static)
                  | ConstantReference(ConstantDeclaration constant)
                  | StringReference(Source.StringLiteral literal)

  Reducer = (Source.BuiltinReducer reducer, ScalarMeaning meaning)

  StaticInitializer = StaticZeroInitializer() unique
                    | StaticConstantInitializer(Types.Constant value)
                    | StaticRelocatableInitializer(Relocation* relocations)

  Relocation = (ReferenceTarget target, number offset, Source.Origin origin)

  OwnershipAction = Copy() unique
                  | Move() unique
                  | Borrow() unique
                  | Mutate() unique
                  | Discharge() unique
                  | TrustedCrossing() unique


  ArgumentSource = AuthoredArgument(Source.Argument argument)
                 | SyntheticArgument(Source.Origin origin)

  Argument = (ArgumentSource source, Expression value, OwnershipAction action)
  CallArgument = (Argument argument, Contract* requires)

  MachineCast = IdentityCast() unique
              | MachineBitcast() unique
              | IntegerReduce() unique
              | SignedExtend() unique
              | UnsignedExtend() unique
              | FloatPromote() unique
              | FloatDemote() unique
              | SignedToFloat() unique
              | UnsignedToFloat() unique
              | FloatToSigned() unique
              | FloatToUnsigned() unique
              | HandleToRaw() unique
              | RawToHandle() unique

  Expression = ConstantExpression(Types.Constant value)
             | BindingExpression(Binding binding, OwnershipAction action)
             | UnaryExpression(Source.UnaryOperator operator, Expression operand)
             | BinaryExpression(Source.BinaryOperator operator, Expression left, Expression right, ScalarMeaning meaning)
             | CompareExpression(Source.ComparisonOperator operator, Expression left, Expression right)
             | LogicExpression(Source.LogicOperator operator, Expression left, Expression right)
             | CastExpression(Types.Type target, Expression value, ScalarMeaning meaning)
             | MachineCastExpression(MachineCast operation, Types.Type target, Expression value, ScalarMeaning meaning)
             | IntrinsicExpression(Source.Intrinsic intrinsic, Expression* arguments, ScalarMeaning meaning)
             | ReferenceExpression(ReferenceTarget target)
             | AddressOfExpression(Place place)
             | DereferenceExpression(Expression pointer)
             | CallExpression(Callable callee, CallArgument* arguments)
             | MethodCallExpression(Callable callee, Expression receiver, Source.Name method, CallArgument* arguments)
             | LengthExpression(Expression value)
             | FieldExpression(Expression base, Field field)
             | IndexExpression(Expression base, Expression index)
             | LoadExpression(Place place)
             | AtomicLoadExpression(Place place)
             | AtomicRmwExpression(Source.AtomicOperator operation, Place place, Expression value)
             | AtomicCompareExchangeExpression(Place place, Expression expected, Expression replacement)
             | AggregateExpression(AggregateField* fields)
             | ArrayExpression(Expression* elements)
             | SelectExpression(Expression condition, Expression true_value, Expression false_value)
             | ClosureExpression(Source.ClosureExpression source, Parameter* parameters, Types.Type result, Capture* captures, Body body)
             | ViewExpression(Expression data, Expression length, Expression stride)
             | ConstructorExpression(Variant variant, Expression* arguments)
             | NullExpression()
             | SizeOfExpression(Types.Type target)
             | AlignOfExpression(Types.Type target)
             | IsNullExpression(Expression value)
             | ReprExpression(Expression handle, OwnershipAction action)
             | FromReprExpression(Types.Type handle_type, Expression raw, OwnershipAction action)
               attributes (Source.Expression source, Types.Type type)

  ScalarMeaning = (Types.Type* operands, Types.Type result, Source.Overflow overflow, Source.FloatMode float_mode, Source.TrapMode trap)
  AggregateField = (Field field, Expression value)

  PlaceAccess = Readable() unique
              | Writable() unique
              | ReadWrite() unique

  Place = BindingPlace(Binding binding)
        | StaticPlace(Static static)
        | DereferencePlace(Expression pointer)
        | FieldPlace(Place base, Field field)
        | IndexPlace(Place base, Expression index)
          attributes (Source.Place source, Types.Type type, PlaceAccess access)


  Capture = ReadCapture(Binding binding)
          | WriteCapture(Binding binding)
          | AddressCapture(Binding binding)
          | MoveCapture(Binding binding)

  Contract = BoundsContract(Source.BoundsContract source, Place subject, Expression lower, Expression upper)
           | WindowBoundsContract(Source.WindowBoundsContract source, Place subject, Expression lower, Expression upper)
           | DisjointContract(Source.DisjointContract source, Place left, Place right)
           | SameLengthContract(Source.SameLengthContract source, Place left, Place right)
           | SoAComponentContract(Source.SoAComponentContract source, Place aggregate, Place component)
           | PairNoaliasContract(Source.PairNoaliasContract source, Place left, Place right)
           | UnaryNoaliasContract(Source.UnaryNoaliasContract source, Place subject)
           | ReadonlyContract(Source.ReadonlyContract source, Place subject)
           | WriteonlyContract(Source.WriteonlyContract source, Place subject)
           | InvalidateContract(Source.InvalidateContract source, Place subject)
           | PreserveContract(Source.PreserveContract source, Place subject)
           | NoescapeContract(Source.NoescapeContract source, Expression subject)

  Statement = BindStatement(Source.Statement source, Binding binding, SemanticInitializer initializer)
            | AssignmentStatement(Source.AssignmentStatement source, Place place, Expression value)
            | AtomicStoreStatement(Source.AtomicStoreStatement source, Place place, Expression value)
            | AtomicFenceStatement(Source.AtomicFenceStatement source)
            | ExpressionStatement(Source.ExpressionStatement source, Expression expression)
            | AssertStatement(Source.AssertStatement source, Expression condition)
            | ContractStatement(Source.ContractStatement source, Contract* contracts)
            | LoopStatement(Source.LoopStatement source, LoopDomain domain, Body body)
            | FoldStatement(Source.FoldStatement source, Binding accumulator, Expression initial, Reducer reducer, Expression step)
            | ScanStatement(Source.ScanStatement source, Binding accumulator, Expression initial, Reducer reducer, Source.ScanMode mode, Binding axis, Expression step, Place destination)

  SemanticInitializer = OmittedZeroInitializer(Types.Constant zero)
                      | ExpressionInitializer(Expression value)

  LoopAxis = (Binding binding, Expression start, Expression stop, Expression step)
  TiledAxis = (Binding outer, Binding inner, Expression start, Expression stop, Expression tile)
  WindowAxis = (Binding binding, Expression start, Expression stop, Expression before, Expression after, Source.WindowBoundary boundary)

  LoopDomain = RangeDomain(LoopAxis axis)
             | GridDomain(LoopAxis* axes)
             | TiledDomain(TiledAxis* axes)
             | WindowDomain(WindowAxis* axes)
             | TraversalDomain(Expression source)

  BlockLabel = (Source.Name name, Source.Origin origin)
  Block = (BlockLabel label, Parameter* parameters, Statement* statements, Terminator terminator)
  Body = (BlockLabel entry, Block* blocks)

  ControlTarget = BlockTarget(BlockLabel block)
                | ContinuationTarget(Continuation continuation)

  SwitchArm = (Types.Constant match_value, BlockLabel target, Expression* arguments)
  VariantSwitchArm = (Variant variant, BlockLabel target, Expression* arguments)
  ContinuationRoute = (Continuation exit, ControlTarget target, Argument* arguments)

  TerminatorSource = AuthoredTerminator(Source.Statement source)
                   | GeneratedTerminator(Source.Origin origin)

  Terminator = Jump(ControlTarget target, Argument* arguments)
             | Branch(Expression condition, BlockLabel true_target, Argument* true_arguments, BlockLabel false_target, Argument* false_arguments)
             | Switch(Expression selector, SwitchArm* arms, BlockLabel default_target, Argument* default_arguments)
             | VariantSwitch(Expression selector, VariantSwitchArm* arms, BlockLabel default_target, Argument* default_arguments)
             | ReturnVoid()
             | ReturnValue(Argument value)
             | YieldVoid()
             | YieldValue(Argument value)
             | RegionCall(Region region, Argument* arguments, ContinuationRoute* routes)
             | Trap()
             | Unreachable()
               attributes (TerminatorSource source, Source.Origin origin)


  ErasureEntry = (Binding binding, Source.Origin origin)
  Erasure = (Callable callable, ErasureEntry* entries)
}

module Code {
  Ordinal = (number value)
  Signature = (Types.Type* parameters, Types.Type result) unique
  Function = (Semantic.Function source, Signature signature)
  Extern = (Semantic.Extern source, Signature signature)
  Global = (Semantic.Static source, Types.Type type)
  Data = (DataSource source, string bytes, number alignment)
  Block = (Function fn, Semantic.BlockLabel source, Ordinal ordinal)
  ParameterSource = SemanticParameter(Semantic.Parameter parameter)
                  | GeneratedParameter(Source.Origin origin)
  Parameter = (Function fn, ParameterSource source, Types.Type type, Ordinal ordinal)
  Local = (Function fn, LocalSource source, Types.Type type, Ordinal ordinal)

  LocalSource = BindingLocal(Semantic.Binding binding)
              | ExpressionLocal(Semantic.Expression expression)
              | GeneratedLocal(Source.Origin origin)

  DataSource = StringData(Source.StringLiteral literal)
             | ConstantData(Semantic.ConstantDeclaration declaration)
             | StaticData(Semantic.Static declaration)
             | GeneratedData(Source.Origin origin)

  Value = ParameterValue(Parameter parameter) unique
        | LocalValue(Local local) unique
        | ConstantValue(Constant constant) unique

  Constant = SemanticConstant(Types.Constant value) unique
           | UndefinedConstant(Types.Type type) unique

  Place = LocalPlace(Local local) unique
        | GlobalPlace(Global global) unique
        | DataPlace(Data data) unique
        | DereferencePlace(Value pointer) unique
        | FieldPlace(Place base, Semantic.Field field) unique
        | IndexPlace(Place base, Value index) unique
        | ByteRangePlace(Place base, Value offset, Value length) unique

  CallResult = VoidCall() unique
             | ValueCall(Local result)

  Callee = DirectCallee(Function fn)
         | ExternalCallee(Extern extern)
         | IndirectCallee(Value pointer)
         | ClosureCallee(Value closure)

  VariantPayload = EmptyPayload() unique
                 | PayloadValue(Value value)

  Instruction = ConstantInstruction(Local result, Constant constant)
              | AliasInstruction(Local result, Value value)
              | UnaryInstruction(Local result, Source.UnaryOperator operator, Value operand, Semantic.ScalarMeaning meaning)
              | BinaryInstruction(Local result, Source.BinaryOperator operator, Value left, Value right, Semantic.ScalarMeaning meaning)
              | CompareInstruction(Local result, Source.ComparisonOperator operator, Value left, Value right)
              | CastInstruction(Local result, Semantic.MachineCast operation, Value value, Semantic.ScalarMeaning meaning)
              | SelectInstruction(Local result, Value condition, Value true_value, Value false_value)
              | IntrinsicInstruction(CallResult result, Source.Intrinsic intrinsic, Value* arguments, Semantic.ScalarMeaning meaning)
              | AddressOfInstruction(Local result, Place place)
              | GlobalReferenceInstruction(Local result, GlobalTarget target)
              | PointerOffsetInstruction(Local result, Value pointer, Value offset)
              | LoadInstruction(Local result, Place place, Source.Volatility volatility)
              | StoreInstruction(Place place, Value value, Source.Volatility volatility)
              | AggregateInstruction(Local result, Value* fields)
              | ArrayInstruction(Local result, Value* elements)
              | ViewMakeInstruction(Local result, Value data, Value length, Value stride)
              | ViewDataInstruction(Local result, Value view)
              | ViewLengthInstruction(Local result, Value view)
              | ViewStrideInstruction(Local result, Value view)
              | SliceMakeInstruction(Local result, Value data, Value length)
              | SliceDataInstruction(Local result, Value slice)
              | SliceLengthInstruction(Local result, Value slice)
              | ClosureInstruction(Local result, Function callable, Value environment)
              | VariantConstructorInstruction(Local result, Semantic.Variant variant, VariantPayload payload)
              | VariantTagInstruction(Local result, Value value)
              | VariantPayloadInstruction(Local result, Value value, Semantic.Variant variant)
              | CallInstruction(CallResult result, Callee callee, Value* arguments, Semantic.Contract* requires)
              | AtomicLoadInstruction(Local result, Place place, Source.Volatility volatility)
              | AtomicStoreInstruction(Place place, Value value, Source.Volatility volatility)
              | AtomicRmwInstruction(Local result, Source.AtomicOperator operation, Place place, Value value, Source.Volatility volatility)
              | AtomicCompareExchangeInstruction(Local result, Place place, Value expected, Value replacement, Source.Volatility volatility)
              | AtomicFenceInstruction()
                attributes (Block block, Ordinal ordinal, Source.Origin origin)

  GlobalTarget = FunctionTarget(Function fn)
               | ExternTarget(Extern extern)
               | GlobalTargetValue(Global global)
               | DataTarget(Data data)

  SwitchArm = (Constant match_value, Block target, Value* arguments)
  VariantSwitchArm = (Semantic.Variant variant, Block target, Value* arguments)

  Terminator = Jump(Block target, Value* arguments)
             | Branch(Value condition, Block true_target, Value* true_arguments, Block false_target, Value* false_arguments)
             | Switch(Value selector, SwitchArm* arms, Block default_target, Value* default_arguments)
             | VariantSwitch(Value selector, VariantSwitchArm* arms, Block default_target, Value* default_arguments)
             | ReturnVoid()
             | ReturnValue(Value value)
             | Trap()
             | Unreachable()
               attributes (Block block, Ordinal ordinal, Source.Origin origin)

  BlockDefinition = (Block block, Parameter* parameters, Instruction* instructions, Terminator terminator)
  FunctionDefinition = (Function fn, Parameter* parameters, Local* locals, Block entry, BlockDefinition* blocks)

  Initializer = ZeroInitializer() unique
              | ConstantInitializer(Constant value)
              | RelocatableInitializer(Relocation* relocations)

  Relocation = (RelocationSource source, RelocationTarget target, number offset, Source.Origin origin)
  RelocationSource = GlobalRelocation(Global global)
                   | DataRelocation(Data data)
  RelocationTarget = FunctionRelocation(Function fn)
                   | ExternRelocation(Extern extern)
                   | GlobalRelocationTarget(Global global)
                   | DataRelocationTarget(Data data)

  GlobalDefinition = (Global global, Initializer initializer)
  Module = (Semantic.Program source, FunctionDefinition* functions, Extern* externs, GlobalDefinition* globals, Data* data, Relocation* relocations, Provenance.Generation generation)
}

module Control {

  Edge = JumpEdge(Code.Function fn, Code.Block source, Code.Block target, Code.Ordinal ordinal)
       | TrueEdge(Code.Function fn, Code.Block source, Code.Block target, Code.Ordinal ordinal)
       | FalseEdge(Code.Function fn, Code.Block source, Code.Block target, Code.Ordinal ordinal)
       | SwitchArmEdge(Code.Function fn, Code.Block source, Code.Block target, Code.Ordinal arm, Code.Ordinal ordinal)
       | SwitchDefaultEdge(Code.Function fn, Code.Block source, Code.Block target, Code.Ordinal ordinal)
       | VariantArmEdge(Code.Function fn, Code.Block source, Code.Block target, Code.Ordinal arm, Code.Ordinal ordinal)
       | VariantDefaultEdge(Code.Function fn, Code.Block source, Code.Block target, Code.Ordinal ordinal)
  EdgeArgument = (Edge edge, Code.Value argument, Code.Parameter parameter, Code.Ordinal ordinal)

  Definition = ParameterDefinition(Code.Parameter parameter)
             | LocalDefinition(Code.Local local)
             | InstructionDefinition(Code.Instruction instruction)

  UseOwner = InstructionUse(Code.Instruction instruction)
           | TerminatorUse(Code.Terminator terminator)

  Use = (Code.Value value, UseOwner owner, Code.Ordinal operand_slot, Code.Ordinal ordinal)

  LoopParent = RootLoop() unique
             | NestedLoop(Loop loop)

  Loop = (Code.Function fn, Code.Block header, Code.Block* body, Code.Block* latches, Edge* exits, LoopParent parent, Code.Ordinal ordinal)
  FunctionGraph = (Code.Function fn, Edge* edges, EdgeArgument* arguments, Definition* definitions, Use* uses, Loop* loops, LoopFlow* flows, Induction* inductions, ValueFact* value_facts, ReductionAlgebra* reductions, LoopArithmetic* arithmetic)
  Graph = (Code.Module code, FunctionGraph* functions, Provenance.Generation generation)

  Bound = ExclusiveStop() unique
        | InclusiveStop() unique
  Direction = Increasing() unique
            | Decreasing() unique

  AffineExpression = AffineConstant(string raw) unique
                   | AffineValue(Code.Value value) unique
                   | AffineAdd(AffineExpression left, AffineExpression right) unique
                   | AffineScale(string scale, AffineExpression value) unique

  IntegerBound = FiniteBound(string raw)
               | NegativeInfinity() unique
               | PositiveInfinity() unique
  IntegerRange = (IntegerBound lower, IntegerBound upper)

  TripForm = ZeroTrip() unique
           | AffineTrip(AffineExpression expression)
           | CeilDivTrip(AffineExpression numerator, AffineExpression denominator)
  LoopAxis = (Code.Value counter, Code.Value start, Code.Value stop, Code.Value step)
  TiledAxis = (Code.Value outer, Code.Value inner, Code.Value start, Code.Value stop, Code.Value tile)
  WindowAxis = (Code.Value counter, Code.Value start, Code.Value stop, Code.Value before, Code.Value after, Source.WindowBoundary boundary)

  GridAxisTrip = (LoopAxis axis, TripForm trip)
  TiledAxisTrip = (TiledAxis axis, TripForm trip)
  WindowAxisTrip = (WindowAxis axis, TripForm trip)

  LoopFlow = RangeLoop(Loop loop, LoopAxis axis, Bound bound, Direction direction, TripForm trip)
           | GridLoop(Loop loop, GridAxisTrip* axes)
           | TiledLoop(Loop loop, TiledAxisTrip* axes)
           | WindowLoop(Loop loop, WindowAxisTrip* axes)
           | TraversalLoop(Loop loop, Code.Value source)
           | UncountedLoop(Loop loop, UncountedReason reason)

  UncountedReason = NonCountedControl() unique
                  | MissingLatch() unique
                  | MissingHeader() unique
                  | MissingCondition() unique
                  | AmbiguousInduction() unique
                  | UnsupportedRecurrence() unique
                  | ContradictoryDirection() unique
                  | InvalidDomain() unique
                  | UnprovableTrip() unique


  Induction = PrimaryInduction(Loop loop, Code.Value value, LoopFlow flow)
            | SecondaryInduction(Loop loop, Code.Value value, Code.Value initial, Code.Value step, Direction direction, IntegerRange range, LoopFlow flow)
            | RecurrenceInduction(Loop loop, Code.Value value, Code.Value initial, Code.Value step, Direction direction, IntegerRange range, LoopFlow flow)
            | DerivedInduction(Loop loop, Code.Value value, Code.Value initial, Code.Value step, Direction direction, IntegerRange range, LoopFlow flow)

  ValueFact = ConstantRange(Code.Value value, IntegerRange range)
            | CopyOf(Code.Value value, Code.Value canonical)
            | AffineValueFact(Code.Value value, AffineExpression expression)
            | NoWrap(Code.Value value, ValueProof proof)
            | FiniteFloat(Code.Value value)
            | NonNanFloat(Code.Value value)
            | ExactFloat(Code.Value value)

  ValueProof = PriorValueFact(ValueFact fact)
             | FlowValueProof(LoopFlow flow)
             | InductionValueProof(Induction induction)

  ReducerIdentity = (Types.Constant identity)

  ReductionAlgebra = Reduction(Loop loop, Code.Value value, Semantic.Reducer reducer, ReducerIdentity identity, AssociativityEvidence associativity)
                   | Scan(Loop loop, Code.Value value, Semantic.Reducer reducer, ReducerIdentity identity, AssociativityEvidence associativity, Source.ScanMode mode)

  LoopArithmetic = Recurrence(Loop loop, Code.Value value, AffineExpression expression)
                 | ClosedForm(Loop loop, Code.Value value, AffineExpression expression)
                 | AffineLoopValue(Loop loop, Code.Value value, AffineExpression expression)

  Associativity = ExactAssociativity() unique
                | ReassociationPermitted() unique

  AssociativityEvidence = (Semantic.Reducer reducer, Associativity associativity)


}

module Memory {
  StorageRoot = ParameterRoot(Code.Parameter parameter)
              | LocalRoot(Code.Local local)
              | GlobalRoot(Code.Global global)
              | DataRoot(Code.Data data)
              | ViewRoot(Code.Value value)
              | SliceRoot(Code.Value value)
              | UniqueRoot(Code.Value value)
              | IndirectRoot(Code.Value pointer)

  PathStep = FieldStep(Semantic.Field field)
           | IndexStep(Code.Value index)
           | ByteRangeStep(Code.Value offset, Code.Value length)

  ObjectParent = RootObject() unique
               | Subobject(Object parent, PathStep step)


  Extent = StaticExtent(number extent)
         | DynamicExtent(Code.Value value)
         | UnknownExtent() unique

  Stride = StaticStride(number bytes)
         | DynamicStride(Code.Value value)
         | UnknownStride() unique

  ObjectShape = KnownObject(Types.Type element, Extent extent, Stride stride, Types.Layout layout)
              | UnknownObject() unique

  Object = (StorageRoot root, ObjectParent parent, ObjectShape shape, Code.Ordinal ordinal)


  AccessIndex = ScalarIndex(Code.Value value)
              | AffineIndex(Control.AffineExpression expression)
              | FieldIndex(Semantic.Field field)
              | ByteIndex(Code.Value offset)
              | IndexSequence(Code.Value* indices)

  BoundsEvidence = DeclaredBounds(Semantic.BoundsContract contract)
                 | DeclaredWindowBounds(Semantic.WindowBoundsContract contract)
                 | FlowBounds(Control.LoopFlow flow)
                 | InductionBounds(Control.Induction induction)
                 | ValueBounds(Control.ValueFact fact)

  TrapEvidence = ScalarTrapEvidence(Semantic.ScalarMeaning meaning)
               | ValueTrapEvidence(Control.ValueFact fact)
               | BoundsTrapEvidence(BoundsEvidence bounds)

  AlignmentEvidence = LayoutAlignment(Types.Layout layout)
                    | DeclaredAlignment(Semantic.Contract contract)

  MovementEvidence = FlowMovement(Control.LoopFlow flow)
                   | InductionMovement(Control.Induction induction)
                   | ValueMovement(Control.ValueFact fact)

  RelationEvidence = DeclaredDisjoint(Semantic.DisjointContract contract)
                   | SharedStorageRoot(StorageRoot root)
                   | AccessRelationEvidence(Access access)
                   | FlowRelationEvidence(Control.LoopFlow flow)
                   | InductionRelationEvidence(Control.Induction induction)
                   | LayoutRelationEvidence(Types.Layout layout)

  Bounds = BoundsProven(BoundsEvidence evidence)
         | BoundsUnproven() unique
         | BoundsUnknown() unique

  Trap = Nontrapping(TrapEvidence evidence)
       | MayTrap() unique
       | MustTrap() unique

  Alignment = Aligned(number alignment, AlignmentEvidence evidence)
            | Unaligned() unique

  Movement = Movable(MovementEvidence evidence)
           | Immovable() unique
           | Pinned() unique

  Access = LoadAccess(Code.Instruction instruction, Object object, AccessIndex index, number width, Bounds bounds, Trap trap, Alignment alignment, Movement movement, Source.Volatility volatility, Code.Ordinal ordinal, Source.Origin origin)
         | StoreAccess(Code.Instruction instruction, Object object, AccessIndex index, number width, Bounds bounds, Trap trap, Alignment alignment, Movement movement, Source.Volatility volatility, Code.Ordinal ordinal, Source.Origin origin)
         | ReadModifyWriteAccess(Code.Instruction instruction, Object object, AccessIndex index, number width, Bounds bounds, Trap trap, Alignment alignment, Movement movement, Source.Volatility volatility, Code.Ordinal ordinal, Source.Origin origin)
         | AddressAccess(Code.Instruction instruction, Object object, AccessIndex index, number width, Bounds bounds, Trap trap, Alignment alignment, Movement movement, Source.Volatility volatility, Code.Ordinal ordinal, Source.Origin origin)

  Relation = SameStore(Object left, Object right, RelationEvidence proof)
           | Overlap(Object left, Object right, RelationEvidence proof)
           | Disjoint(Object left, Object right, RelationEvidence proof)
           | ExactNoalias(Object left, Object right)
           | ProvenAlias(Object left, Object right, RelationEvidence proof)
           | Dependence(Access source, Access sink, RelationEvidence proof, Control.AffineExpression distance)
           | LoopDependence(Control.Loop loop, Access source, Access sink, RelationEvidence proof, Control.AffineExpression distance)
           | MayAlias(Object left, Object right)
           | Incomparable(Object left, Object right)
           | UnknownDependence(Access source, Access sink)

  ContractSubject = ContractObject(Object object)
                  | ContractAccess(Access access)
                  | ContractPair(Object left, Object right)
                  | ContractExpression(Semantic.Expression expression)
  ContractRealization = (Semantic.Contract contract, ContractSubject subject, Source.Origin origin)
  CallRequireRealization = (Code.CallInstruction call, Semantic.Contract contract, ContractSubject subject, Source.Origin origin)

  Model = (Control.FunctionGraph control, Object* objects, Access* accesses, Relation* relations, ContractRealization* contracts, CallRequireRealization* call_requires, Provenance.Generation generation)

}

module Effect {
  Atom = ReadEffect(Memory.Access access)
       | WriteEffect(Memory.Access access)
       | PreserveEffect(Memory.Object object)
       | InvalidateEffect(Memory.Object object)
       | NoescapeEffect(Memory.Object object)
       | RetainEffect(Memory.Object object)
       | FenceEffect() unique
       | AllocateEffect(Memory.Object object)
       | UnknownCallEffect(Code.Callee callee)
       | KnownCallEffect(Code.Callee callee)

  OperationSubject = InstructionOperation(Code.Instruction instruction)
                   | TerminatorOperation(Code.Terminator terminator)

  OperationEffect = PureOperation(OperationSubject subject)
                  | EffectfulOperation(OperationSubject subject, Atom* effects)

  CallableEffect = PureCallable(Code.Function fn)
                 | EffectfulCallable(Code.Function fn, Atom* effects)
                 | ExternalCallable(Code.Extern extern, Atom* effects)
  CallableEffectEntry = (Code.Callee callee, CallableEffect effect)

  Summary = (Control.FunctionGraph control, OperationEffect* operations, CallableEffectEntry* callables, Provenance.Generation generation)
}

module Ownership {
  LeaseOrigin = (Memory.Object object, Semantic.Binding source)
  State = LeaseLive(Memory.Object object, Source.Origin use)
        | Invalidated(Memory.Object object, Effect.OperationEffect cause)
        | Discharged(Memory.Object object, Source.Origin cause)
        | Noescape(Memory.Object object, Code.Instruction call, Effect.CallableEffect effect)

  Model = (Memory.Model memory, LeaseOrigin* origins, State* states, Provenance.Generation generation)
}

module Kernel {

  LaneSource = InductionLane(Control.Induction induction)
             | MemoryLane(Memory.Access access)
             | ResultLane(Code.Value value)

  Lane = CounterLane(LaneSource source, Control.AffineExpression position, Code.Ordinal ordinal)
       | InputLane(LaneSource source, Control.AffineExpression position, Code.Ordinal ordinal)
       | OutputLane(LaneSource source, Control.AffineExpression position, Code.Ordinal ordinal)
       | AccumulatorLane(LaneSource source, Control.AffineExpression position, Code.Ordinal ordinal)

  ResultTarget = RegisterTarget() unique
               | StoredTarget(Memory.Access destination)

  Result = (Code.Value source, ResultTarget target, Code.Ordinal ordinal)




  Kernel = (Control.Loop source, Control.LoopFlow shape, Control.FunctionGraph graph, Memory.Model memory, Effect.Summary effects, Ownership.Model ownership, Lane* lanes, Result* results, Provenance.Generation generation)



  TailDecision = ExactTail() unique
               | ScalarRemainder() unique
  Schedule = (Kernel kernel, TailDecision tail, Target.Policy policy, Target.EmitterCapability capability)

  Baseline = (Code.Function fn, Code.Block* covered_blocks, Target.EmitterCapability capability)

  RejectedOptimization = KernelRejected(Diagnostic.KernelUnavailable reason)
                       | ScheduleRejected(Diagnostic.ScheduleUnavailable reason)
                       | FusionRejected(Diagnostic.FusionUnavailable reason)
                       | MaterializationRejected(Diagnostic.MaterializationUnavailable reason)
                       | FragmentRejected(Diagnostic.FragmentUnavailable reason)

  OptimizationChoice = BaselineChoice(Baseline baseline, RejectedOptimization* rejected)
                     | FragmentChoice(CMat.Fragment fragment, RejectedOptimization* rejected)
}

module CMat {
  Axis = (Kernel.Lane source, Code.Ordinal ordinal)
  StreamInput = LaneInput(Kernel.Lane lane)
              | ValueInput(StreamSource source)
  Stream = (Code.Instruction operation, StreamInput* inputs, Code.Ordinal ordinal)

  StreamSource = StreamValue(Stream stream)
               | SinkValue(Sink sink)
               | AccessValue(Access access)

  Access = LoadAccess(Memory.Access source, Code.Ordinal ordinal)
         | StoreAccess(Memory.Access source, Code.Ordinal ordinal)
         | WindowAccess(Memory.Access source, Code.Ordinal ordinal)

  Sink = (Kernel.Result source, StreamSource producer, Stream* inputs, Code.Ordinal ordinal)

  Computation = (Kernel.Schedule schedule, Axis* axes, Stream* streams, Access* accesses, Sink* sinks, Provenance.Generation generation)



  Basis = ObjectBasis(Memory.Object object)

  Coordinate = AbsoluteCoordinate(Control.AffineExpression byte_offset)
             | IterationCoordinate(Basis basis, Control.AffineExpression expression)
             | WindowCoordinate(Basis basis, number displacement, number scale, Source.WindowBoundary boundary)
             | DynamicWindowCoordinate(Basis basis, Code.Value displacement, number scale, Source.WindowBoundary boundary)
             | ScatterCoordinate(Basis basis, Code.Value index)


  PointerAccess = OrdinaryPointer() unique
               | RestrictPointer(Memory.Relation* relations)


  AddressBinding = (Code.Value source, FragmentValue value)

  MemoryUse = (Access source, Coordinate coordinate, PointerAccess pointer_access, AddressBinding* bindings, Ownership.State* live_states, Code.Ordinal ordinal)
  Materialization = (Computation computation, MemoryUse* uses, Provenance.Generation generation)


  Cursor = (MemoryUse use, Control.AffineExpression initial_offset, Code.Ordinal ordinal)
  CursorStep = (Cursor cursor, Control.Loop loop, Control.AffineExpression step_offset, Code.Ordinal ordinal)
  CursorRealization = (Materialization materialization, Cursor* cursors, CursorStep* steps, Provenance.Generation generation)
  FragmentSubject = ClosedFormSubject(Control.Loop loop, Control.LoopArithmetic arithmetic)
                  | FusedSubject(CursorRealization realization)

  FragmentValueSource = CodeValueSource(Code.Value value)
                      | MemoryUseSource(MemoryUse use)
                      | CursorSource(Cursor cursor)
                      | GeneratedValueSource(Source.Origin origin)

  FragmentValue = (FragmentValueSource source, Types.Type type, Code.Ordinal ordinal)
  FragmentLocal = (Types.Type type, Code.Ordinal ordinal, Source.Origin origin)
  FragmentLabel = (FragmentValue* parameters, Code.Ordinal ordinal, Source.Origin origin)

  FragmentExpression = ConstantExpression(Types.Constant value)
                     | UnaryExpression(Source.UnaryOperator operator, FragmentValue operand)
                     | BinaryExpression(Source.BinaryOperator operator, FragmentValue left, FragmentValue right, Semantic.ScalarMeaning meaning)
                     | CompareExpression(Source.ComparisonOperator operator, FragmentValue left, FragmentValue right)
                     | LogicExpression(Source.LogicOperator operator, FragmentValue left, FragmentValue right)
                     | SelectExpression(FragmentValue condition, FragmentValue true_value, FragmentValue false_value, Types.Type result)
                     | CastExpression(Semantic.MachineCast operation, FragmentValue value, Semantic.ScalarMeaning meaning)

  FragmentCallTarget = HelperCall(Helper helper)
                     | FunctionCall(Code.Function fn)

  FragmentCallResult = VoidCall() unique
                     | ValueCall(FragmentValue result)

  FragmentOperation = Assign(FragmentValue target, FragmentExpression value, Code.Ordinal ordinal, Source.Origin origin)
                    | Load(FragmentValue target, MemoryUse use, Code.Ordinal ordinal, Source.Origin origin)
                    | Store(MemoryUse use, FragmentValue value, Code.Ordinal ordinal, Source.Origin origin)
                    | Call(FragmentCallTarget target, FragmentValue* arguments, FragmentCallResult result, Code.Ordinal ordinal, Source.Origin origin)

  FragmentTerminatorArgument = (FragmentValue value, FragmentValue parameter, Code.Ordinal ordinal)
  FragmentTerminator = Branch(FragmentValue condition, FragmentLabel true_label, FragmentTerminatorArgument* true_arguments, FragmentLabel false_label, FragmentTerminatorArgument* false_arguments, Code.Ordinal ordinal, Source.Origin origin)
                     | Jump(FragmentLabel label, FragmentTerminatorArgument* arguments, Code.Ordinal ordinal, Source.Origin origin)
                     | Exit(FragmentExit exit, Code.Ordinal ordinal, Source.Origin origin)

  FragmentBlock = (FragmentLabel label, FragmentOperation* operations, FragmentTerminator terminator)

  FragmentEntryArgument = (Code.Parameter parameter, FragmentValue value, Code.Ordinal ordinal)
  FragmentEntry = (FragmentLabel label, Code.Block source, FragmentEntryArgument* arguments)
  FragmentExitArgument = (FragmentValue value, Code.Parameter parameter, Code.Ordinal ordinal)
  FragmentExit = (FragmentLabel label, Code.Block target, FragmentExitArgument* arguments)
  Helper = (Source.Symbol symbol, Code.Signature signature)
  FragmentBinding = (Code.Value source, FragmentValue value, Code.Ordinal ordinal)
  FragmentLocalBinding = (FragmentValue value, FragmentLocal local, Code.Ordinal ordinal)
  Fragment = (FragmentSubject subject, FragmentEntry entry, Code.Block* covered_blocks, FragmentBinding* bindings, FragmentLocalBinding* local_bindings, FragmentValue* values, FragmentLocal* locals, FragmentBlock* blocks, FragmentExit* exits, Helper* helpers, Provenance.Generation generation)
}

module C {
  Type = (Types.Type semantic, Types.Layout layout)
  Signature = (Code.Signature code, Types.CallableABI abi)

  FunctionPart = BaselinePart(Code.Block* blocks)
               | FragmentPart(CMat.Fragment fragment, FragmentEntryParameter* entry_parameters)

  Function = (Code.Function source, Signature signature, Source.Symbol symbol, FunctionPart* parts)
  Extern = (Code.Extern source, Signature signature, Source.Symbol symbol)
  Global = (Code.Global source, Type type, Source.Symbol symbol)
  Data = (Code.Data source, Source.Symbol symbol)
  Helper = (HelperSource source, Source.Symbol symbol)

  HelperSource = FragmentHelper(CMat.Helper helper)
               | IntrinsicHelper(Source.Intrinsic intrinsic, Signature signature)

  Parameter = (ParameterSource source, Type type, CMat.PointerAccess pointer_access, Code.Ordinal ordinal)
  FunctionParameter = (Parameter parameter, Types.Passing passing)
  AbiResultSlot = VoidSlot() unique
                | DirectSlot(Local local)
                | IndirectSlot(Local local, Parameter parameter)
  FragmentEntryParameter = (CMat.FragmentEntryArgument argument, Parameter parameter)
  ParameterSource = CodeParameter(Code.Parameter parameter)
                  | FragmentParameter(CMat.FragmentValue value)
                  | GeneratedParameter(Source.Origin origin)

  Local = (LocalSource source, Type type, Code.Ordinal ordinal)
  LocalSource = CodeLocal(Code.Local local)
              | FragmentLocal(CMat.FragmentLocal local)
              | CursorLocal(CMat.Cursor cursor)
              | MemoryUseLocal(CMat.MemoryUse use)

  Label = (LabelSource source, Code.Ordinal ordinal)
  LabelSource = CodeLabel(Code.Block block)
              | FragmentLabel(CMat.FragmentLabel label)

  Value = ParameterValue(Parameter parameter)
        | LocalValue(Local local)
        | ConstantValue(Code.Constant constant)
        | GlobalValue(Global global)
        | DataValue(Data data)
        | FunctionValue(Function fn)
        | ExternValue(Extern extern)

  Place = LocalPlace(Local local)
        | GlobalPlace(Global global)
        | DataPlace(Data data)
        | DereferencePlace(Value pointer)
        | FieldPlace(Place base, number offset)
        | IndexPlace(Place base, Value index, number stride)
        | ByteRangePlace(Place base, Value offset, Value length)

  CallResult = VoidCall() unique
             | ValueCall(Local result)

  Operation = ConstantOp(Local target, Code.Constant constant)
            | AliasOp(Local target, Value value)
            | UnaryOp(Local target, Source.UnaryOperator operator, Value operand, Semantic.ScalarMeaning meaning)
            | BinaryOp(Local target, Source.BinaryOperator operator, Value left, Value right, Semantic.ScalarMeaning meaning)
            | CompareOp(Local target, Source.ComparisonOperator operator, Value left, Value right)
            | CastOp(Local target, Semantic.MachineCast operation, Value value, Semantic.ScalarMeaning meaning)
            | SelectOp(Local target, Value condition, Value true_value, Value false_value, Types.Type result)
            | AddressOp(Local target, Place place)
            | PointerOffsetOp(Local target, Value pointer, Value offset)
            | LoadOp(Local target, Place place, Source.Volatility volatility)
            | StoreOp(Place place, Value value, Source.Volatility volatility)
            | AggregateOp(Local target, Value* values)
            | ArrayOp(Local target, Value* values)
            | ViewMakeOp(Local target, Value data, Value length, Value stride)
            | ViewDataOp(Local target, Value view)
            | ViewLengthOp(Local target, Value view)
            | ViewStrideOp(Local target, Value view)
            | SliceMakeOp(Local target, Value data, Value length)
            | SliceDataOp(Local target, Value slice)
            | SliceLengthOp(Local target, Value slice)
            | ClosureOp(Local target, Function fn, Value environment)
            | VariantConstructOp(Local target, Semantic.Variant variant, Value payload)
            | VariantTagOp(Local target, Value value)
            | VariantPayloadOp(Local target, Value value, Semantic.Variant variant)
            | DirectCallOp(CallResult result, Function fn, Value* arguments)
            | ExternalCallOp(CallResult result, Extern extern, Value* arguments)
            | IndirectCallOp(CallResult result, Value pointer, Value* arguments)
            | ClosureCallOp(CallResult result, Value closure, Value* arguments)
            | HelperCallOp(CallResult result, Helper helper, Value* arguments)
            | IntrinsicOp(CallResult result, Source.Intrinsic intrinsic, Value* arguments, Semantic.ScalarMeaning meaning)
            | AtomicLoadOp(Local target, Place place, Source.Volatility volatility)
            | AtomicStoreOp(Place place, Value value, Source.Volatility volatility)
            | AtomicRmwOp(Local target, Source.AtomicOperator operation, Place place, Value value, Source.Volatility volatility)
            | AtomicCompareExchangeOp(Local target, Place place, Value expected, Value replacement, Source.Volatility volatility)
            | AtomicFenceOp()


  SwitchArm = (Code.Constant match_value, Label target, Value* arguments)
  VariantSwitchArm = (Semantic.Variant variant, Label target, Value* arguments)

  Terminator = Jump(Label target, Value* arguments)
             | Branch(Value condition, Label true_target, Value* true_arguments, Label false_target, Value* false_arguments)
             | Switch(Value selector, SwitchArm* arms, Label default_target, Value* default_arguments)
             | VariantSwitch(Value selector, VariantSwitchArm* arms, Label default_target, Value* default_arguments)
             | ReturnVoid() unique
             | ReturnValue(Value value)
             | Trap() unique
             | Unreachable() unique
               attributes (Source.Origin origin)

  Statement = (Operation operation, Code.Ordinal ordinal, Source.Origin origin)
  Block = (Label label, Parameter* parameters, Statement* statements, Terminator terminator)
  FunctionDefinition = (Function fn, FunctionParameter* parameters, AbiResultSlot* abi_result_slots, Local* locals, Label entry, Block* blocks)
  HelperDefinition = (Helper helper, Parameter* parameters, Local* locals, Label entry, Block* blocks)

  Initializer = ZeroInitializer() unique
              | ConstantInitializer(Code.Constant constant)
              | BytesInitializer(string bytes)
              | RelocatableInitializer(Relocation* relocations)

  Relocation = (RelocationSource source, RelocationTarget target, number offset)
  RelocationSource = GlobalRelocation(Global global)
                   | DataRelocation(Data data)
  RelocationTarget = FunctionRelocation(Function fn)
                   | ExternRelocation(Extern extern)
                   | GlobalRelocationTarget(Global global)
                   | DataRelocationTarget(Data data)

  GlobalDefinition = (Global global, Initializer initializer)
  Unit = (Code.Module code, Target.Spec target, Type* types, Signature* signatures, FunctionDefinition* functions, Extern* externs, GlobalDefinition* globals, Data* data, HelperDefinition* helpers, Relocation* relocations, Provenance.Generation generation)


  Artifact = (Unit unit, string source, string header)
}

module Host {
  OptimizationLevel = O0() unique
                    | O1() unique
                    | O2() unique
                    | O3() unique

  FloatCompilerMode = StrictFloat() unique
                    | FastMath() unique

  CookPolicy = (Source.Path compiler, Source.Path output_directory, OptimizationLevel optimization, FloatCompilerMode float_mode)
  CookRequest = (C.Artifact artifact, CookPolicy policy)
  LiveSession = (C.Artifact artifact, Source.Path library)
  FfiType = CallableFfiType(Types.CallableABI abi) unique
          | ImportedFfiType(Types.Type type, string declaration) unique
  SymbolRequest = (LiveSession session, Source.Symbol symbol, FfiType ffi_type)

  CookFailure = CompilerUnavailable(CookRequest request)
              | FileWriteFailure(CookRequest request, Source.Path path)
              | ProcessSpawnFailure(CookRequest request)
              | CompilationFailure(CookRequest request, number exit_code, string stderr_text)
              | DynamicLoadFailure(CookRequest request, Source.Path library)
              | FastMathRefused(CookRequest request)

  SymbolFailure = MissingSymbol(SymbolRequest request)
                | IncompatibleFfiType(SymbolRequest request)


  CookResult = Cooked(LiveSession session)
             | CookFailed(CookFailure failure)

  SymbolResult = SymbolResolved(SymbolRequest request)
               | SymbolFailed(SymbolFailure failure)
}

module Diagnostic {
  SourceError = InvalidDocumentRoot(Source.Origin origin)
              | InvalidDeclaration(Source.Origin origin)
              | InvalidBody(Source.Origin origin)
              | InvalidHostValue(Source.Origin origin)
              | InvalidSplice(Source.Origin origin)

  SynthesisError = UnknownMetaProperty(Source.MetaQuery query)
                 | InvalidMetaRole(Source.MetaQuery query)
                 | UnsupportedMetaResult(Source.MetaQuery query)
                 | RecursiveSynthesis(Source.MetaQuery query)
                 | UnboundedSynthesis(Source.MetaQuery query)
                 | DynamicFallbackRejected(Source.MetaQuery query)

  ResolutionError = DuplicateDeclaration(Source.Declaration first, Source.Declaration duplicate)
                  | MissingValue(Source.ValueUse use)
                  | MissingType(Source.TypeUse use)
                  | MissingRegion(Source.RegionUse use)
                  | MissingBlock(Source.BlockUse use)
                  | MissingContinuation(Source.ContinuationUse use)
                  | WrongNamespace(Source.Origin origin)
                  | IllegalShadowing(Source.Binding binding)
                  | InvalidQualification(Source.Origin origin)
                  | MissingField(Source.FieldUse use)
                  | MissingVariant(Source.VariantUse use)

  TypeError = UnknownType(Source.TypeForm type)
            | RecursiveType(Source.TypeForm type)
            | InvalidArrayExtent(Source.ArrayType type)
            | InvalidTypeComposition(Source.TypeForm type)
            | TypeMismatch(Source.Origin origin, Types.Type expected, Types.Type actual)
            | IllegalCast(Source.CastExpression expression)
            | IllegalOperandTypes(Source.Expression expression)
            | DuplicateMember(Source.Origin origin)
            | UnsupportedTypeOperation(Source.TypeForm type)

  CheckError = UnboundValue(Source.ValueUse use)
             | InvalidPlace(Source.Origin origin)
             | InvalidCall(Source.Expression expression)
             | InvalidReturnValue(Source.Origin origin)
             | InvalidIndex(Source.Expression expression)
             | InvalidNominalUse(Source.Origin origin)
             | MalformedVariantUse(Source.Origin origin)
             | UnsupportedOperation(Source.Expression expression)

  ControlError = MissingTerminator(Source.Origin origin)
               | MissingSwitchDefault(Source.Origin origin)
               | InvalidControlTarget(Source.Origin origin)
               | InvalidControlArgument(Source.Origin origin)
               | InvalidReturn(Source.Origin origin)
               | IllegalFallthrough(Source.Origin origin)
               | ForbiddenControl(Source.Origin origin)
               | UnreachableControl(Source.Origin origin)
               | IncompleteVariantSwitch(Source.Origin origin)
               | EntryParameterWithoutSource(Source.Origin origin)
               | BadContinuationArgument(Source.Origin origin)
               | BadPassthrough(Source.Origin origin)
               | InvalidLoopStep(Source.LoopAxis axis)
               | InvalidTileExtent(Source.TileAxis axis)
               | InvalidWindowExtent(Source.WindowAxis axis)
               | InvalidTraversalSource(Source.LoopStatement loop)
               | UnsupportedLoopBody(Source.Origin origin)
               | NestedPatternUnsupported(Source.Pattern pattern)

  ContractError = InvalidContract(Source.Contract contract)
                | NonMemorySubject(Source.Contract contract)
                | InvalidBound(Source.Contract contract)
                | ContradictoryContract(Source.Contract contract)
                | MissingContractSubject(Source.Contract contract)
                | UnsupportedContract(Source.Contract contract)
                | UnsatisfiedRequires(Source.CallArgument argument)
  ReducerError = UnsupportedReducer(Source.BuiltinReducer reducer)
               | NonAssociativeReducer(Source.BuiltinReducer reducer, Source.Origin origin)
               | ReducerTypeMismatch(Source.BuiltinReducer reducer, Types.Type accumulator, Types.Type step)
               | MultipleReducersInLoop(Source.Origin origin)
               | MisplacedReducer(Source.Origin origin)
               | InvalidScanAxis(Source.ScanStatement scan)

  OwnershipError = IllegalCopy(Source.Origin origin)
                 | IllegalDrop(Source.Origin origin)
                 | DoubleDischarge(Source.Origin origin)
                 | MutableOwnedBinding(Source.Binding binding)
                 | DurableLease(Source.Origin origin)
                 | LeaseEscape(Source.Origin origin)
                 | RetainingCall(Source.Origin origin)
                 | ConflictingInvalidation(Source.Origin origin)
                 | UseOutsideLifetime(Source.Origin origin)
                 | InvalidResolver(Source.HandleDeclaration handle)
                 | MissingLeaseGrant(Source.HandleDeclaration handle)
                 | HandleTargetMismatch(Source.HandleDeclaration handle)
                 | UnsafeHandleCast(Source.Origin origin)
                 | UntrustedCrossing(Source.Origin origin)
                 | InvalidUniqueUse(Source.Origin origin)
                 | UniqueWithoutIdentityAuthority(Source.UniqueStructDeclaration declaration)
                 | UniqueCopyEqualityViolation(Source.Origin origin)
                 | InvalidRepresentationWidth(Source.HandleDeclaration handle)
                 | PrematureErasure(Source.Origin origin)
                 | InvalidRepr(Source.ReprExpression expression)
                 | InvalidFromRepr(Source.FromReprExpression expression)

  ConstantError = NonConstant(Source.Expression expression)
                | RecursiveConstant(Source.ConstantDeclaration declaration)
                | UnsupportedConstantOperation(Source.Expression expression)

  ClosureError = UnresolvedCapture(Source.ClosureExpression closure)
               | IllegalCapture(Source.ClosureExpression closure)
               | UnsupportedClosure(Source.ClosureExpression closure)

  RegionError = RegionArgumentMismatch(Source.RegionInvocation invocation)
              | RegionWiringMismatch(Source.RegionInvocation invocation)
              | MissingRegionContinuation(Source.RegionInvocation invocation)
              | UnsupportedRegionBody(Source.RegionDeclaration region)
              | CaptureAdmissionFailed(Source.RegionInvocation invocation)
              | DuplicateGeneratedIdentity(Source.RegionInvocation invocation)
              | ContinuationSignatureMismatch(Source.RegionInvocation invocation)

  CodeError = UnsupportedSemanticNode(Source.Origin origin)
            | MissingCodeValue(Source.Origin origin)
            | InvalidCodeReference(Source.Origin origin)
            | InvalidCodeSignature(Code.Function fn)
            | InvalidCodeTransfer(Code.Block block)
            | UnterminatedCodeBlock(Code.Block block)
            | InvalidInitializer(Source.Origin origin)
            | InvalidRelocation(Code.Relocation relocation)

  AnalysisError = InvalidControlGraph(Code.Module code)
                | ContradictoryValueEvidence(Code.Value value)
                | ContradictoryEffect(Code.Instruction instruction)
                | GenerationMismatch(Provenance.Expectation expectation)
                | TargetMismatch(Provenance.Expectation expectation)

  MemoryError = UnknownStorageProvenance(Code.Place place)
              | InvalidMemoryAccess(Code.Instruction instruction)
              | ContradictoryMemoryContract(Semantic.Contract contract)
              | RequiredBoundsUnproven(Memory.Access access)
              | RequiredNoaliasUnproven(Memory.Object left, Memory.Object right)

  KernelUnavailable = UnsupportedKernelControl(Control.Loop loop)
                    | UnsafeKernelMemory(Control.Loop loop)
                    | MissingKernelEvidence(Control.Loop loop)
                    | UnsupportedKernelExpression(Control.Loop loop)
                    | UnsupportedKernelEffect(Control.Loop loop)
                    | InvalidKernelTrip(Control.Loop loop)
                    | ReductionIdentityMismatch(Control.Loop loop, Control.ReductionAlgebra algebra)

  ScheduleUnavailable = UnsupportedScheduleTarget(Kernel.Kernel kernel, Target.Spec target)
                      | MissingEmitterCapability(Kernel.Kernel kernel)
                      | IllegalTailSchedule(Kernel.Kernel kernel)
                      | SchedulePolicyRejected(Kernel.Kernel kernel)

  FusionUnavailable = UnsupportedFusedDomain(Kernel.Kernel kernel)
                    | UnsupportedFusedOperator(Kernel.Kernel kernel)
                    | UnsupportedFusedWindow(Kernel.Kernel kernel)
                    | UnsupportedFusedTail(Kernel.Kernel kernel)
                    | UnsafeFusedAccess(Kernel.Kernel kernel)
                    | VolatileFusedAccess(Kernel.Kernel kernel)
                    | MissingFusedBounds(Kernel.Kernel kernel)
                    | MissingFusedNoalias(Kernel.Kernel kernel)
                    | UnsupportedFusedResult(Kernel.Kernel kernel)
                    | IncompatibleFusedSchedule(Kernel.Kernel kernel)
                    | FusedShapeContradiction(Kernel.Kernel kernel)

  MaterializationUnavailable = UnsupportedUseTopology(CMat.Computation computation)
                             | AmbiguousUseOrder(CMat.Computation computation)
                             | CoordinateUnavailable(CMat.Access access)
                             | PointerQualificationUnavailable(CMat.Access access)
                             | AddressUnavailable(CMat.Access access)
                             | UnsupportedUseMeaning(CMat.Access access)
                             | UnsupportedRmwAccess(CMat.Access access)
                             | WindowBoundaryUnavailable(CMat.Access access)
                             | CursorUnavailable(CMat.MemoryUse use)

  FragmentUnavailable = UnsupportedFragment(CMat.FragmentSubject subject)
                      | InvalidFragmentCoverage(CMat.FragmentSubject subject)
                      | DominanceFailure(CMat.FragmentSubject subject)
                      | InvalidFragmentExit(CMat.FragmentSubject subject)
                      | MissingFragmentValue(CMat.FragmentSubject subject)
                      | HelperConflict(CMat.FragmentSubject subject)
                      | UnsupportedFragmentValue(CMat.FragmentSubject subject)
                      | UnsupportedFragmentCarry(CMat.FragmentSubject subject)
                      | MissingFragmentCoordinate(CMat.FragmentSubject subject)
                      | MissingFragmentAccess(CMat.FragmentSubject subject)

  BackendError = UnrepresentableType(Types.Type type)
               | UnrepresentableOperation(Code.Instruction instruction)
               | UnrepresentableStorage(Memory.Object object)
               | MissingBackendSymbol(Source.Symbol symbol)
               | MissingBackendHelper(CMat.Helper helper)
               | InvalidFragmentLowering(CMat.Fragment fragment)
               | IllegalLinkage(Source.Origin origin)
               | BackendTargetMismatch(Target.Spec expected, Target.Spec actual)

  LayoutError = IncompleteRecursiveLayout(Types.Type type)
              | UnrepresentableField(Semantic.Field field)
              | UnrepresentablePayload(Semantic.Variant variant)
              | InvalidAlignment(Types.Type type)
              | TargetWidthMismatch(Target.Spec target, Types.Type type)
              | LayoutOverflow(Types.Type type)

  AbiError = UnrepresentableParameter(Types.CallableABI abi, Code.Ordinal ordinal)
           | UnrepresentableResult(Types.CallableABI abi)
           | UnsupportedConvention(Types.CallableABI abi)
           | IncompatibleRedeclaration(Types.CallableABI abi)
           | SignatureCollision(Source.Symbol symbol)
           | MissingSymbolPolicy(Types.CallableABI abi)
           | InvalidVisibility(Source.Origin origin)
           | AbiTargetMismatch(Target.Spec expected, Target.Spec actual)
           | MissingAbiResultSlot(Types.CallableABI abi)

  CEmissionError = InvalidCReference(Source.Origin origin)
                 | InvalidCType(C.Type type)
                 | InvalidCControl(C.Block block)
                 | InvalidCAbiParameter(C.Parameter parameter)
                 | InconsistentRestrictQualification(C.Operation operation)
                 | OverlappingFunctionParts(C.Function fn)
                 | IncompleteRestrictQualification(C.Parameter parameter)
                 | InvalidCMemoryAccess(C.Operation operation)
                 | UnsupportedCEntity(Source.Origin origin)
                 | EmitterCapabilityMismatch(Target.EmitterCapability capability)

  CompilerError = SourceRejected(SourceError reason)
                | SynthesisRejected(SynthesisError reason)
                | ResolutionRejected(ResolutionError reason)
                | TypeRejected(TypeError reason)
                | CheckRejected(CheckError reason)
                | ControlRejected(ControlError reason)
                | ContractRejected(ContractError reason)
                | ReducerRejected(ReducerError reason)
                | OwnershipRejected(OwnershipError reason)
                | ConstantRejected(ConstantError reason)
                | ClosureRejected(ClosureError reason)
                | RegionRejected(RegionError reason)
                | CodeRejected(CodeError reason)
                | AnalysisRejected(AnalysisError reason)
                | MemoryRejected(MemoryError reason)
                | LayoutRejected(LayoutError reason)
                | AbiRejected(AbiError reason)
                | BackendRejected(BackendError reason)
                | CEmissionRejected(CEmissionError reason)
                | OptimizationRejected(Kernel.RejectedOptimization reason)
}
]]

return Compiler
