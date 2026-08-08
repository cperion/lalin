local schema = require("cdefschema")

local S = schema.context {
    name = "retained-compiler",
    version = 1,
    prefix = "RetainedCompilerV1_",
}

S:cdef [[
enum {
    RetainedCompilerV1_SourceCapacity = 65536,
    RetainedCompilerV1_ExpressionCapacity = 4096,
    RetainedCompilerV1_BindingCapacity = 1024,
    RetainedCompilerV1_SymbolCapacity = 2048,
    RetainedCompilerV1_SymbolBucketCount = 4096,
    RetainedCompilerV1_SymbolTextCapacity = 65536,
    RetainedCompilerV1_OperatorCapacity = 128,
    RetainedCompilerV1_InstructionCapacity = 8192,
    RetainedCompilerV1_ArtifactCapacity = 262144
};

typedef struct {
    uint32_t start;
    uint32_t length;
} RetainedCompilerV1_Span;

typedef struct {
    uint32_t length;
    uint8_t bytes[RetainedCompilerV1_SourceCapacity];
} RetainedCompilerV1_Source;

typedef uint32_t RetainedCompilerV1_SymbolId;

typedef struct {
    uint64_t hash;
    uint32_t text_offset;
    uint32_t text_length;
    uint32_t next_in_bucket;
    uint32_t reserved;
} RetainedCompilerV1_SymbolEntry;

typedef struct {
    uint32_t head;
    uint32_t generation;
} RetainedCompilerV1_SymbolBucket;

typedef struct {
    uint8_t text[RetainedCompilerV1_SymbolTextCapacity];
    RetainedCompilerV1_SymbolEntry entries[RetainedCompilerV1_SymbolCapacity];
    RetainedCompilerV1_SymbolBucket buckets[RetainedCompilerV1_SymbolBucketCount];
    uint32_t text_count;
    uint32_t entry_count;
} RetainedCompilerV1_SymbolStore;

typedef struct {
    uint32_t kind;
    uint32_t index;
    uint32_t id;
    uint32_t reserved;
} RetainedCompilerV1_ExprRef;

typedef struct {
    int64_t value;
    uint32_t id;
    uint32_t offset;
} RetainedCompilerV1_IntegerExpr;

typedef struct {
    RetainedCompilerV1_SymbolId symbol;
    uint32_t reserved;
    uint32_t id;
    uint32_t offset;
} RetainedCompilerV1_NameExpr;

typedef struct {
    RetainedCompilerV1_ExprRef left;
    RetainedCompilerV1_ExprRef right;
    uint32_t id;
    uint32_t operator_kind;
    uint32_t offset;
    uint32_t reserved;
} RetainedCompilerV1_BinaryExpr;

typedef struct {
    RetainedCompilerV1_IntegerExpr integers[RetainedCompilerV1_ExpressionCapacity];
    RetainedCompilerV1_NameExpr names[RetainedCompilerV1_ExpressionCapacity];
    RetainedCompilerV1_BinaryExpr binaries[RetainedCompilerV1_ExpressionCapacity];
    RetainedCompilerV1_ExprRef order[RetainedCompilerV1_ExpressionCapacity];
    uint32_t integer_count;
    uint32_t name_count;
    uint32_t binary_count;
    uint32_t order_count;
} RetainedCompilerV1_ExpressionStore;

typedef struct {
    RetainedCompilerV1_SymbolId symbol;
    uint32_t reserved;
    RetainedCompilerV1_ExprRef value;
    uint32_t offset;
    uint32_t declaration_order;
} RetainedCompilerV1_Binding;

typedef struct {
    RetainedCompilerV1_Binding bindings[RetainedCompilerV1_BindingCapacity];
    RetainedCompilerV1_ExprRef returned;
    uint32_t binding_count;
    uint32_t has_return;
} RetainedCompilerV1_Program;

typedef struct {
    uint32_t binding;
    uint32_t generation;
} RetainedCompilerV1_ResolutionEntry;

typedef struct {
    uint32_t binding;
    uint32_t generation;
} RetainedCompilerV1_SymbolBindingEntry;

typedef struct {
    RetainedCompilerV1_ResolutionEntry by_expression[RetainedCompilerV1_ExpressionCapacity];
    RetainedCompilerV1_SymbolBindingEntry by_symbol[RetainedCompilerV1_SymbolCapacity];
    uint64_t revision;
} RetainedCompilerV1_ResolutionFacet;

typedef struct {
    uint32_t type_kind;
    uint32_t generation;
} RetainedCompilerV1_TypeEntry;

typedef struct {
    RetainedCompilerV1_TypeEntry by_expression[RetainedCompilerV1_ExpressionCapacity];
    uint64_t revision;
} RetainedCompilerV1_TypeFacet;

typedef struct {
    uint32_t register_index;
    uint32_t generation;
} RetainedCompilerV1_LowerEntry;

typedef struct {
    RetainedCompilerV1_LowerEntry by_expression[RetainedCompilerV1_ExpressionCapacity];
    uint64_t revision;
} RetainedCompilerV1_LowerFacet;

typedef struct {
    uint32_t target;
    uint32_t reserved;
    int64_t value;
} RetainedCompilerV1_ConstInstruction;

typedef struct {
    uint32_t target;
    uint32_t left;
    uint32_t right;
    uint32_t operator_kind;
} RetainedCompilerV1_BinaryInstruction;

typedef struct {
    uint32_t value;
    uint32_t reserved;
} RetainedCompilerV1_ReturnInstruction;

typedef union {
    RetainedCompilerV1_ConstInstruction constant;
    RetainedCompilerV1_BinaryInstruction binary;
    RetainedCompilerV1_ReturnInstruction returned;
} RetainedCompilerV1_InstructionPayload;

typedef struct {
    uint32_t kind;
    uint32_t reserved;
    RetainedCompilerV1_InstructionPayload payload;
} RetainedCompilerV1_Instruction;

typedef struct {
    RetainedCompilerV1_Instruction items[RetainedCompilerV1_InstructionCapacity];
    uint32_t count;
    uint32_t reserved;
    uint64_t revision;
} RetainedCompilerV1_InstructionStore;

typedef struct {
    uint32_t length;
    uint32_t revision;
    uint8_t bytes[RetainedCompilerV1_ArtifactCapacity];
} RetainedCompilerV1_Artifact;

typedef struct {
    uint32_t code;
    uint32_t offset;
} RetainedCompilerV1_Diagnostic;

typedef struct {
    uint32_t position;
    uint32_t token_kind;
    RetainedCompilerV1_Span token_span;
    int64_t integer_value;
    uint64_t token_count;
} RetainedCompilerV1_Scanner;

typedef struct {
    RetainedCompilerV1_ExprRef operands[RetainedCompilerV1_OperatorCapacity];
    uint32_t operators[RetainedCompilerV1_OperatorCapacity];
    RetainedCompilerV1_SymbolId current_symbol;
    uint32_t current_name_offset;
    uint32_t operand_count;
    uint32_t operator_count;
    uint64_t statement_count;
} RetainedCompilerV1_Parser;

typedef struct {
    uint32_t cursor;
    uint32_t reserved;
    uint64_t resolved_count;
} RetainedCompilerV1_Resolver;

typedef struct {
    uint32_t cursor;
    uint32_t reserved;
    uint64_t typed_count;
} RetainedCompilerV1_Typechecker;

typedef struct {
    uint32_t cursor;
    uint32_t next_register;
    uint64_t lowered_count;
} RetainedCompilerV1_Lowerer;

typedef struct {
    uint32_t cursor;
    uint32_t reserved;
    uint64_t emitted_count;
} RetainedCompilerV1_Emitter;

typedef struct {
    RetainedCompilerV1_Source source;
    RetainedCompilerV1_SymbolStore symbols;
    RetainedCompilerV1_ExpressionStore expressions;
    RetainedCompilerV1_Program program;
    RetainedCompilerV1_ResolutionFacet resolutions;
    RetainedCompilerV1_TypeFacet types;
    RetainedCompilerV1_LowerFacet lower;
    RetainedCompilerV1_InstructionStore instructions;
    RetainedCompilerV1_Artifact artifact;
    RetainedCompilerV1_Diagnostic diagnostic;
    RetainedCompilerV1_Scanner scanner;
    RetainedCompilerV1_Parser parser;
    RetainedCompilerV1_Resolver resolver;
    RetainedCompilerV1_Typechecker typechecker;
    RetainedCompilerV1_Lowerer lowerer;
    RetainedCompilerV1_Emitter emitter;
    uint64_t revision;
    uint32_t generation;
    uint32_t status;
    uint32_t reserved;
    uint32_t reserved2;
} RetainedCompilerV1_Compiler;
 ]]

local types = {
    Context = S,
    Span = S:product("RetainedCompilerV1_Span"),
    Source = S:product("RetainedCompilerV1_Source"),
    SymbolEntry = S:product("RetainedCompilerV1_SymbolEntry"),
    SymbolBucket = S:product("RetainedCompilerV1_SymbolBucket"),
    SymbolStore = S:product("RetainedCompilerV1_SymbolStore"),
    ExprRef = S:product("RetainedCompilerV1_ExprRef"),
    IntegerExpr = S:product("RetainedCompilerV1_IntegerExpr"),
    NameExpr = S:product("RetainedCompilerV1_NameExpr"),
    BinaryExpr = S:product("RetainedCompilerV1_BinaryExpr"),
    ExpressionStore = S:product("RetainedCompilerV1_ExpressionStore"),
    Binding = S:product("RetainedCompilerV1_Binding"),
    Program = S:product("RetainedCompilerV1_Program"),
    ResolutionEntry = S:product("RetainedCompilerV1_ResolutionEntry"),
    SymbolBindingEntry = S:product("RetainedCompilerV1_SymbolBindingEntry"),
    ResolutionFacet = S:product("RetainedCompilerV1_ResolutionFacet"),
    TypeEntry = S:product("RetainedCompilerV1_TypeEntry"),
    TypeFacet = S:product("RetainedCompilerV1_TypeFacet"),
    LowerEntry = S:product("RetainedCompilerV1_LowerEntry"),
    LowerFacet = S:product("RetainedCompilerV1_LowerFacet"),
    ConstInstruction = S:product("RetainedCompilerV1_ConstInstruction"),
    BinaryInstruction = S:product("RetainedCompilerV1_BinaryInstruction"),
    ReturnInstruction = S:product("RetainedCompilerV1_ReturnInstruction"),
    InstructionPayload = S:union("RetainedCompilerV1_InstructionPayload"),
    Instruction = S:product("RetainedCompilerV1_Instruction"),
    InstructionStore = S:product("RetainedCompilerV1_InstructionStore"),
    Artifact = S:product("RetainedCompilerV1_Artifact"),
    Diagnostic = S:product("RetainedCompilerV1_Diagnostic"),
    Scanner = S:product("RetainedCompilerV1_Scanner"),
    Parser = S:product("RetainedCompilerV1_Parser"),
    Resolver = S:product("RetainedCompilerV1_Resolver"),
    Typechecker = S:product("RetainedCompilerV1_Typechecker"),
    Lowerer = S:product("RetainedCompilerV1_Lowerer"),
    Emitter = S:product("RetainedCompilerV1_Emitter"),
    Compiler = S:product("RetainedCompilerV1_Compiler"),
}

types.capacity = { source = 65536, expressions = 4096, bindings = 1024, operators = 128,
    symbols = 2048, symbol_buckets = 4096, symbol_text = 65536,
    instructions = 8192, artifact = 262144 }

return types
