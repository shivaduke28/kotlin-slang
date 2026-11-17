package com.shivaduke.kotlinslang

/** `SlangCompileTarget`: a code generation target format. */
enum class SlangCompileTarget(val raw: Int) {
    Unknown(0),
    None(1),
    Glsl(2),
    Hlsl(5),
    Spirv(6),
    SpirvAsm(7),
    Metal(24),
    Wgsl(28),
}

/** `SlangStage`: a pipeline stage. */
enum class SlangStage(val raw: Int) {
    None(0),
    Vertex(1),
    Hull(2),
    Domain(3),
    Geometry(4),
    Fragment(5),
    Compute(6),
    RayGeneration(7),
    Intersection(8),
    AnyHit(9),
    ClosestHit(10),
    Miss(11),
    Callable(12),
    Mesh(13),
    Amplification(14),
    Dispatch(15),
    Node(16);

    companion object {
        fun from(raw: Int): SlangStage = entries.firstOrNull { it.raw == raw } ?: None
    }
}

/** `slang::ParameterCategory` (`SlangParameterCategory`): a kind of resource a parameter consumes. */
enum class SlangParameterCategory(val raw: Int) {
    None(0),
    Mixed(1),
    ConstantBuffer(2),
    ShaderResource(3),
    UnorderedAccess(4),
    VaryingInput(5),
    VaryingOutput(6),
    SamplerState(7),
    Uniform(8),
    DescriptorTableSlot(9),
    SpecializationConstant(10),
    PushConstantBuffer(11),
    RegisterSpace(12),
    Generic(13),
    RayPayload(14),
    HitAttributes(15),
    CallablePayload(16),
    ShaderRecord(17),
    ExistentialTypeParam(18),
    ExistentialObjectParam(19),
    SubElementRegisterSpace(20);

    companion object {
        fun from(raw: Int): SlangParameterCategory = entries.firstOrNull { it.raw == raw } ?: None
    }
}

/** `slang::TypeReflection::Kind` (`SlangTypeKind`). */
enum class SlangTypeKind(val raw: Int) {
    None(0),
    Struct(1),
    Array(2),
    Matrix(3),
    Vector(4),
    Scalar(5),
    ConstantBuffer(6),
    Resource(7),
    SamplerState(8),
    TextureBuffer(9),
    ShaderStorageBuffer(10),
    ParameterBlock(11),
    GenericTypeParameter(12),
    Interface(13),
    OutputStream(14),
    MeshOutput(15),
    Specialized(16),
    Feedback(17),
    Pointer(18),
    DynamicResource(19),
    Enum(20);

    companion object {
        fun from(raw: Int): SlangTypeKind = entries.firstOrNull { it.raw == raw } ?: None
    }
}

/** `slang::TypeReflection::ScalarType` (`SlangScalarType`). */
enum class SlangScalarType(val raw: Int) {
    None(0),
    Void(1),
    Bool(2),
    Int32(3),
    UInt32(4),
    Int64(5),
    UInt64(6),
    Float16(7),
    Float32(8),
    Float64(9),
    Int8(10),
    UInt8(11),
    Int16(12),
    UInt16(13),
    IntPtr(14),
    UIntPtr(15);

    companion object {
        fun from(raw: Int): SlangScalarType = entries.firstOrNull { it.raw == raw } ?: None
    }
}

/** `SLANG_UNBOUNDED_SIZE`, as returned by the size and count getters of the reflection API. */
const val SLANG_UNBOUNDED_SIZE: Long = -1L

/** `SLANG_UNKNOWN_SIZE`, as returned by the size and count getters of the reflection API. */
const val SLANG_UNKNOWN_SIZE: Long = -2L
