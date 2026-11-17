// JNI boundary for kotlin-slang.
//
// Each function here forwards to exactly one method of the Slang C++ API
// (slang.h) and is named after the interface and method it forwards to. The
// Kotlin classes in com.shivaduke.kotlinslang mirror the Slang interfaces on top
// of these; anything that combines several Slang calls lives in Kotlin.
//
// Handles passed across the boundary are raw pointers:
//   - global sessions: slang::IGlobalSession*, owning one reference
//   - sessions: SessionState*, owned by the Kotlin SlangSession
//   - component types (modules, entry points, composites, linked programs):
//     slang::IComponentType*, kept alive by their SessionState
//   - reflection objects: the slang reflection pointers themselves, which are
//     owned by the component type they were obtained from
// so every handle derived from a session is valid until that session is released.
//
// All functions are static natives of the Kotlin object SlangNative and resolve
// no Java classes or members by name, so no R8 keep rules are needed beyond
// keeping the native method names.
#include <jni.h>
#include <slang-com-ptr.h>
#include <slang.h>

#include <cstdint>
#include <string>
#include <vector>

namespace
{

// The Kotlin enums carry these values as their `raw`; fail the build if Slang
// renumbers them.
static_assert(SLANG_SPIRV == 6, "SlangCompileTarget");
static_assert(SLANG_STAGE_FRAGMENT == 5 && SLANG_STAGE_COMPUTE == 6, "SlangStage");
static_assert(SLANG_PARAMETER_CATEGORY_UNIFORM == 8, "SlangParameterCategory");
static_assert(SLANG_PARAMETER_CATEGORY_DESCRIPTOR_TABLE_SLOT == 9, "SlangParameterCategory");
static_assert(SLANG_PARAMETER_CATEGORY_SUB_ELEMENT_REGISTER_SPACE == 20, "SlangParameterCategory");
static_assert(SLANG_TYPE_KIND_RESOURCE == 7 && SLANG_TYPE_KIND_ENUM == 20, "SlangTypeKind");
static_assert(SLANG_SCALAR_TYPE_FLOAT32 == 8 && SLANG_SCALAR_TYPE_UINT16 == 13, "SlangScalarType");

// Native side of a Kotlin SlangSession.
struct SessionState
{
    Slang::ComPtr<slang::IGlobalSession> global;
    Slang::ComPtr<slang::ISession> session;
    // Component types handed out to Kotlin. Modules are owned by the ISession itself.
    std::vector<Slang::ComPtr<slang::IComponentType>> owned;

    jlong keep(slang::IComponentType* component)
    {
        owned.emplace_back(component);
        return reinterpret_cast<jlong>(component);
    }
};

template<typename T>
T* ptr(jlong handle)
{
    return reinterpret_cast<T*>(handle);
}

jlong handle(const void* p)
{
    return reinterpret_cast<jlong>(p);
}

slang::IModule* modulePtr(jlong h)
{
    return static_cast<slang::IModule*>(ptr<slang::IComponentType>(h));
}

slang::IEntryPoint* entryPointPtr(jlong h)
{
    return static_cast<slang::IEntryPoint*>(ptr<slang::IComponentType>(h));
}

std::string toStdString(JNIEnv* env, jstring s)
{
    if (!s)
        return {};
    const char* chars = env->GetStringUTFChars(s, nullptr);
    std::string result(chars ? chars : "");
    if (chars)
        env->ReleaseStringUTFChars(s, chars);
    return result;
}

std::vector<std::string> toStdStrings(JNIEnv* env, jobjectArray array)
{
    std::vector<std::string> result;
    const jsize count = array ? env->GetArrayLength(array) : 0;
    result.reserve(count);
    for (jsize i = 0; i < count; i++)
    {
        auto element = (jstring)env->GetObjectArrayElement(array, i);
        result.push_back(toStdString(env, element));
        env->DeleteLocalRef(element);
    }
    return result;
}

jstring toJString(JNIEnv* env, const char* s)
{
    return s ? env->NewStringUTF(s) : nullptr;
}

// Stores the text of a diagnostics blob in out[0]. `out` is the Kotlin stand-in for
// an `IBlob** outDiagnostics` parameter and may be null.
void setDiagnostics(JNIEnv* env, jobjectArray out, ISlangBlob* blob)
{
    if (!out || !blob)
        return;
    const std::string text(
        static_cast<const char*>(blob->getBufferPointer()), blob->getBufferSize());
    jstring jText = env->NewStringUTF(text.c_str());
    env->SetObjectArrayElement(out, 0, jText);
    env->DeleteLocalRef(jText);
}

jbyteArray toByteArray(JNIEnv* env, ISlangBlob* blob)
{
    if (!blob)
        return nullptr;
    const jsize size = (jsize)blob->getBufferSize();
    jbyteArray bytes = env->NewByteArray(size);
    if (bytes)
        env->SetByteArrayRegion(
            bytes, 0, size, static_cast<const jbyte*>(blob->getBufferPointer()));
    return bytes;
}

} // namespace

#define JNI_FN(ret, name) \
    extern "C" JNIEXPORT ret JNICALL Java_com_shivaduke_kotlinslang_SlangNative_##name

// Getters taking only the object handle, or the handle and one int argument `i`.
// `self` is the object, typed as T.
#define GET(ret, name, T, expr)                        \
    JNI_FN(ret, name)(JNIEnv* env, jclass, jlong h)    \
    {                                                  \
        (void)env;                                     \
        auto* self = ptr<T>(h);                        \
        return expr;                                   \
    }
#define GET_I(ret, name, T, expr)                              \
    JNI_FN(ret, name)(JNIEnv* env, jclass, jlong h, jint i)    \
    {                                                          \
        (void)env;                                             \
        auto* self = ptr<T>(h);                                \
        return expr;                                           \
    }

using namespace slang;

// ---------------------------------------------------------------------------
// IGlobalSession
// ---------------------------------------------------------------------------

JNI_FN(jlong, createGlobalSession)(JNIEnv*, jclass)
{
    Slang::ComPtr<IGlobalSession> global;
    if (SLANG_FAILED(slang_createGlobalSession(SLANG_API_VERSION, global.writeRef())))
        return 0;
    return handle(global.detach());
}

JNI_FN(void, globalSessionRelease)(JNIEnv*, jclass, jlong h)
{
    ptr<IGlobalSession>(h)->release();
}

JNI_FN(jint, globalSessionFindProfile)(JNIEnv* env, jclass, jlong h, jstring jName)
{
    return (jint)ptr<IGlobalSession>(h)->findProfile(toStdString(env, jName).c_str());
}

GET(jstring, globalSessionGetBuildTagString, IGlobalSession, toJString(env, self->getBuildTagString()))

// Targets are passed as parallel arrays of TargetDesc::format and TargetDesc::profile,
// preprocessor macros as parallel arrays of names and values.
JNI_FN(jlong, globalSessionCreateSession)(
    JNIEnv* env,
    jclass,
    jlong h,
    jintArray jTargetFormats,
    jintArray jTargetProfiles,
    jobjectArray jSearchPaths,
    jobjectArray jMacroNames,
    jobjectArray jMacroValues)
{
    IGlobalSession* global = ptr<IGlobalSession>(h);

    const jsize targetCount = env->GetArrayLength(jTargetFormats);
    std::vector<jint> formats(targetCount);
    std::vector<jint> profiles(targetCount);
    env->GetIntArrayRegion(jTargetFormats, 0, targetCount, formats.data());
    env->GetIntArrayRegion(jTargetProfiles, 0, targetCount, profiles.data());
    std::vector<TargetDesc> targets(targetCount);
    for (jsize i = 0; i < targetCount; i++)
    {
        targets[i].format = (SlangCompileTarget)formats[i];
        targets[i].profile = (SlangProfileID)profiles[i];
    }

    const std::vector<std::string> searchPaths = toStdStrings(env, jSearchPaths);
    std::vector<const char*> searchPathPtrs;
    for (const std::string& path : searchPaths)
        searchPathPtrs.push_back(path.c_str());

    const std::vector<std::string> macroNames = toStdStrings(env, jMacroNames);
    const std::vector<std::string> macroValues = toStdStrings(env, jMacroValues);
    std::vector<PreprocessorMacroDesc> macros;
    for (size_t i = 0; i < macroNames.size(); i++)
        macros.push_back({macroNames[i].c_str(), macroValues[i].c_str()});

    SessionDesc desc = {};
    desc.targets = targets.data();
    desc.targetCount = (SlangInt)targets.size();
    desc.searchPaths = searchPathPtrs.data();
    desc.searchPathCount = (SlangInt)searchPathPtrs.size();
    desc.preprocessorMacros = macros.data();
    desc.preprocessorMacroCount = (SlangInt)macros.size();

    auto* state = new SessionState();
    state->global = global;
    if (SLANG_FAILED(global->createSession(desc, state->session.writeRef())))
    {
        delete state;
        return 0;
    }
    return handle(state);
}

// ---------------------------------------------------------------------------
// ISession
// ---------------------------------------------------------------------------

JNI_FN(void, sessionRelease)(JNIEnv*, jclass, jlong h)
{
    delete ptr<SessionState>(h);
}

JNI_FN(jlong, sessionLoadModule)(
    JNIEnv* env, jclass, jlong h, jstring jModuleName, jobjectArray outDiagnostics)
{
    Slang::ComPtr<ISlangBlob> diagnostics;
    IModule* module = ptr<SessionState>(h)->session->loadModule(
        toStdString(env, jModuleName).c_str(), diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    return handle(static_cast<IComponentType*>(module));
}

JNI_FN(jlong, sessionLoadModuleFromSourceString)(
    JNIEnv* env,
    jclass,
    jlong h,
    jstring jModuleName,
    jstring jPath,
    jstring jString,
    jobjectArray outDiagnostics)
{
    Slang::ComPtr<ISlangBlob> diagnostics;
    IModule* module = ptr<SessionState>(h)->session->loadModuleFromSourceString(
        toStdString(env, jModuleName).c_str(),
        toStdString(env, jPath).c_str(),
        toStdString(env, jString).c_str(),
        diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    return handle(static_cast<IComponentType*>(module));
}

JNI_FN(jlong, sessionCreateCompositeComponentType)(
    JNIEnv* env, jclass, jlong h, jlongArray jComponentTypes, jobjectArray outDiagnostics)
{
    SessionState* state = ptr<SessionState>(h);

    const jsize count = env->GetArrayLength(jComponentTypes);
    std::vector<jlong> handles(count);
    env->GetLongArrayRegion(jComponentTypes, 0, count, handles.data());
    std::vector<IComponentType*> components(count);
    for (jsize i = 0; i < count; i++)
        components[i] = ptr<IComponentType>(handles[i]);

    Slang::ComPtr<IComponentType> composite;
    Slang::ComPtr<ISlangBlob> diagnostics;
    const SlangResult result = state->session->createCompositeComponentType(
        components.data(), (SlangInt)components.size(), composite.writeRef(), diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    if (SLANG_FAILED(result) || !composite)
        return 0;
    return state->keep(composite);
}

JNI_FN(jlong, sessionGetLoadedModuleCount)(JNIEnv*, jclass, jlong h)
{
    return (jlong)ptr<SessionState>(h)->session->getLoadedModuleCount();
}

JNI_FN(jlong, sessionGetLoadedModule)(JNIEnv*, jclass, jlong h, jlong index)
{
    IModule* module = ptr<SessionState>(h)->session->getLoadedModule((SlangInt)index);
    return handle(static_cast<IComponentType*>(module));
}

// ---------------------------------------------------------------------------
// IComponentType
// ---------------------------------------------------------------------------

JNI_FN(jlong, componentTypeGetLayout)(
    JNIEnv* env, jclass, jlong h, jlong targetIndex, jobjectArray outDiagnostics)
{
    Slang::ComPtr<ISlangBlob> diagnostics;
    ProgramLayout* layout =
        ptr<IComponentType>(h)->getLayout((SlangInt)targetIndex, diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    return handle(layout);
}

JNI_FN(jbyteArray, componentTypeGetEntryPointCode)(
    JNIEnv* env,
    jclass,
    jlong h,
    jlong entryPointIndex,
    jlong targetIndex,
    jobjectArray outDiagnostics)
{
    Slang::ComPtr<ISlangBlob> code;
    Slang::ComPtr<ISlangBlob> diagnostics;
    const SlangResult result = ptr<IComponentType>(h)->getEntryPointCode(
        (SlangInt)entryPointIndex, (SlangInt)targetIndex, code.writeRef(), diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    return SLANG_FAILED(result) ? nullptr : toByteArray(env, code);
}

JNI_FN(jbyteArray, componentTypeGetTargetCode)(
    JNIEnv* env, jclass, jlong h, jlong targetIndex, jobjectArray outDiagnostics)
{
    Slang::ComPtr<ISlangBlob> code;
    Slang::ComPtr<ISlangBlob> diagnostics;
    const SlangResult result = ptr<IComponentType>(h)->getTargetCode(
        (SlangInt)targetIndex, code.writeRef(), diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    return SLANG_FAILED(result) ? nullptr : toByteArray(env, code);
}

JNI_FN(jlong, componentTypeLink)(
    JNIEnv* env, jclass, jlong session, jlong h, jobjectArray outDiagnostics)
{
    Slang::ComPtr<IComponentType> linked;
    Slang::ComPtr<ISlangBlob> diagnostics;
    const SlangResult result =
        ptr<IComponentType>(h)->link(linked.writeRef(), diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    if (SLANG_FAILED(result) || !linked)
        return 0;
    return ptr<SessionState>(session)->keep(linked);
}

// ---------------------------------------------------------------------------
// IModule
// ---------------------------------------------------------------------------

JNI_FN(jlong, moduleFindEntryPointByName)(
    JNIEnv* env, jclass, jlong session, jlong h, jstring jName)
{
    Slang::ComPtr<IEntryPoint> entryPoint;
    const SlangResult result = modulePtr(h)->findEntryPointByName(
        toStdString(env, jName).c_str(), entryPoint.writeRef());
    if (SLANG_FAILED(result) || !entryPoint)
        return 0;
    return ptr<SessionState>(session)->keep(entryPoint);
}

JNI_FN(jint, moduleGetDefinedEntryPointCount)(JNIEnv*, jclass, jlong h)
{
    return (jint)modulePtr(h)->getDefinedEntryPointCount();
}

JNI_FN(jlong, moduleGetDefinedEntryPoint)(JNIEnv*, jclass, jlong session, jlong h, jint index)
{
    Slang::ComPtr<IEntryPoint> entryPoint;
    const SlangResult result =
        modulePtr(h)->getDefinedEntryPoint((SlangInt32)index, entryPoint.writeRef());
    if (SLANG_FAILED(result) || !entryPoint)
        return 0;
    return ptr<SessionState>(session)->keep(entryPoint);
}

JNI_FN(jstring, moduleGetName)(JNIEnv* env, jclass, jlong h)
{
    return toJString(env, modulePtr(h)->getName());
}

JNI_FN(jstring, moduleGetFilePath)(JNIEnv* env, jclass, jlong h)
{
    return toJString(env, modulePtr(h)->getFilePath());
}

JNI_FN(jlong, moduleFindAndCheckEntryPoint)(
    JNIEnv* env,
    jclass,
    jlong session,
    jlong h,
    jstring jName,
    jint stage,
    jobjectArray outDiagnostics)
{
    Slang::ComPtr<IEntryPoint> entryPoint;
    Slang::ComPtr<ISlangBlob> diagnostics;
    const SlangResult result = modulePtr(h)->findAndCheckEntryPoint(
        toStdString(env, jName).c_str(),
        (SlangStage)stage,
        entryPoint.writeRef(),
        diagnostics.writeRef());
    setDiagnostics(env, outDiagnostics, diagnostics);
    if (SLANG_FAILED(result) || !entryPoint)
        return 0;
    return ptr<SessionState>(session)->keep(entryPoint);
}

// ---------------------------------------------------------------------------
// IEntryPoint
// ---------------------------------------------------------------------------

JNI_FN(jlong, entryPointGetFunctionReflection)(JNIEnv*, jclass, jlong h)
{
    return handle(entryPointPtr(h)->getFunctionReflection());
}

// ---------------------------------------------------------------------------
// ProgramLayout (ShaderReflection)
// ---------------------------------------------------------------------------

GET(jint, programLayoutGetParameterCount, ProgramLayout, (jint)self->getParameterCount())
GET_I(jlong, programLayoutGetParameterByIndex, ProgramLayout, handle(self->getParameterByIndex((unsigned)i)))
GET(jlong, programLayoutGetEntryPointCount, ProgramLayout, (jlong)self->getEntryPointCount())
GET_I(jlong, programLayoutGetEntryPointByIndex, ProgramLayout, handle(self->getEntryPointByIndex((SlangUInt)i)))
GET(jlong, programLayoutGetGlobalConstantBufferBinding, ProgramLayout, (jlong)self->getGlobalConstantBufferBinding())
GET(jlong, programLayoutGetGlobalConstantBufferSize, ProgramLayout, (jlong)self->getGlobalConstantBufferSize())
GET(jlong, programLayoutGetGlobalParamsTypeLayout, ProgramLayout, handle(self->getGlobalParamsTypeLayout()))
GET(jlong, programLayoutGetGlobalParamsVarLayout, ProgramLayout, handle(self->getGlobalParamsVarLayout()))

JNI_FN(jlong, programLayoutFindEntryPointByName)(JNIEnv* env, jclass, jlong h, jstring jName)
{
    return handle(ptr<ProgramLayout>(h)->findEntryPointByName(toStdString(env, jName).c_str()));
}

// ---------------------------------------------------------------------------
// EntryPointReflection
// ---------------------------------------------------------------------------

GET(jstring, entryPointReflectionGetName, EntryPointReflection, toJString(env, self->getName()))
GET(jstring, entryPointReflectionGetNameOverride, EntryPointReflection, toJString(env, self->getNameOverride()))
GET(jint, entryPointReflectionGetParameterCount, EntryPointReflection, (jint)self->getParameterCount())
GET(jlong, entryPointReflectionGetFunction, EntryPointReflection, handle(self->getFunction()))
GET_I(jlong, entryPointReflectionGetParameterByIndex, EntryPointReflection, handle(self->getParameterByIndex((unsigned)i)))
GET(jint, entryPointReflectionGetStage, EntryPointReflection, (jint)self->getStage())
GET(jlong, entryPointReflectionGetVarLayout, EntryPointReflection, handle(self->getVarLayout()))
GET(jlong, entryPointReflectionGetTypeLayout, EntryPointReflection, handle(self->getTypeLayout()))
GET(jlong, entryPointReflectionGetResultVarLayout, EntryPointReflection, handle(self->getResultVarLayout()))
GET(jboolean, entryPointReflectionHasDefaultConstantBuffer, EntryPointReflection, (jboolean)self->hasDefaultConstantBuffer())

// Fills outSizeAlongAxis, whose length is the axis count.
JNI_FN(void, entryPointReflectionGetComputeThreadGroupSize)(
    JNIEnv* env, jclass, jlong h, jlongArray outSizeAlongAxis)
{
    const jsize axisCount = env->GetArrayLength(outSizeAlongAxis);
    std::vector<SlangUInt> sizes(axisCount, 0);
    ptr<EntryPointReflection>(h)->getComputeThreadGroupSize((SlangUInt)axisCount, sizes.data());
    std::vector<jlong> out(sizes.begin(), sizes.end());
    env->SetLongArrayRegion(outSizeAlongAxis, 0, axisCount, out.data());
}

// ---------------------------------------------------------------------------
// FunctionReflection
// ---------------------------------------------------------------------------

GET(jstring, functionReflectionGetName, FunctionReflection, toJString(env, self->getName()))
GET(jlong, functionReflectionGetReturnType, FunctionReflection, handle(self->getReturnType()))
GET(jint, functionReflectionGetParameterCount, FunctionReflection, (jint)self->getParameterCount())
GET_I(jlong, functionReflectionGetParameterByIndex, FunctionReflection, handle(self->getParameterByIndex((unsigned)i)))
GET(jint, functionReflectionGetUserAttributeCount, FunctionReflection, (jint)self->getUserAttributeCount())
GET_I(jlong, functionReflectionGetUserAttributeByIndex, FunctionReflection, handle(self->getUserAttributeByIndex((unsigned)i)))

// ---------------------------------------------------------------------------
// VariableReflection
// ---------------------------------------------------------------------------

GET(jstring, variableReflectionGetName, VariableReflection, toJString(env, self->getName()))
GET(jlong, variableReflectionGetType, VariableReflection, handle(self->getType()))
GET(jint, variableReflectionGetUserAttributeCount, VariableReflection, (jint)self->getUserAttributeCount())
GET_I(jlong, variableReflectionGetUserAttributeByIndex, VariableReflection, handle(self->getUserAttributeByIndex((unsigned)i)))

// ---------------------------------------------------------------------------
// VariableLayoutReflection
// ---------------------------------------------------------------------------

GET(jlong, variableLayoutReflectionGetVariable, VariableLayoutReflection, handle(self->getVariable()))
GET(jstring, variableLayoutReflectionGetName, VariableLayoutReflection, toJString(env, self->getName()))
GET(jlong, variableLayoutReflectionGetTypeLayout, VariableLayoutReflection, handle(self->getTypeLayout()))
GET(jint, variableLayoutReflectionGetCategory, VariableLayoutReflection, (jint)self->getCategory())
GET(jint, variableLayoutReflectionGetCategoryCount, VariableLayoutReflection, (jint)self->getCategoryCount())
GET_I(jint, variableLayoutReflectionGetCategoryByIndex, VariableLayoutReflection, (jint)self->getCategoryByIndex((unsigned)i))
GET_I(jlong, variableLayoutReflectionGetOffset, VariableLayoutReflection, (jlong)self->getOffset((SlangParameterCategory)i))
GET(jlong, variableLayoutReflectionGetType, VariableLayoutReflection, handle(self->getType()))
GET(jint, variableLayoutReflectionGetBindingIndex, VariableLayoutReflection, (jint)self->getBindingIndex())
GET(jint, variableLayoutReflectionGetBindingSpace, VariableLayoutReflection, (jint)self->getBindingSpace())
GET_I(jlong, variableLayoutReflectionGetBindingSpaceForCategory, VariableLayoutReflection, (jlong)self->getBindingSpace((SlangParameterCategory)i))
GET(jstring, variableLayoutReflectionGetSemanticName, VariableLayoutReflection, toJString(env, self->getSemanticName()))
GET(jlong, variableLayoutReflectionGetSemanticIndex, VariableLayoutReflection, (jlong)self->getSemanticIndex())
GET(jint, variableLayoutReflectionGetStage, VariableLayoutReflection, (jint)self->getStage())

// ---------------------------------------------------------------------------
// TypeReflection
// ---------------------------------------------------------------------------

GET(jint, typeReflectionGetKind, TypeReflection, (jint)self->getKind())
GET(jint, typeReflectionGetFieldCount, TypeReflection, (jint)self->getFieldCount())
GET_I(jlong, typeReflectionGetFieldByIndex, TypeReflection, handle(self->getFieldByIndex((unsigned)i)))
GET(jboolean, typeReflectionIsArray, TypeReflection, (jboolean)self->isArray())
GET(jlong, typeReflectionUnwrapArray, TypeReflection, handle(self->unwrapArray()))
GET(jlong, typeReflectionGetElementCount, TypeReflection, (jlong)self->getElementCount())
GET(jlong, typeReflectionGetElementType, TypeReflection, handle(self->getElementType()))
GET(jint, typeReflectionGetRowCount, TypeReflection, (jint)self->getRowCount())
GET(jint, typeReflectionGetColumnCount, TypeReflection, (jint)self->getColumnCount())
GET(jint, typeReflectionGetScalarType, TypeReflection, (jint)self->getScalarType())
GET(jlong, typeReflectionGetResourceResultType, TypeReflection, handle(self->getResourceResultType()))
GET(jstring, typeReflectionGetName, TypeReflection, toJString(env, self->getName()))
GET(jint, typeReflectionGetUserAttributeCount, TypeReflection, (jint)self->getUserAttributeCount())
GET_I(jlong, typeReflectionGetUserAttributeByIndex, TypeReflection, handle(self->getUserAttributeByIndex((unsigned)i)))

// ---------------------------------------------------------------------------
// TypeLayoutReflection
// ---------------------------------------------------------------------------

GET(jlong, typeLayoutReflectionGetType, TypeLayoutReflection, handle(self->getType()))
GET(jint, typeLayoutReflectionGetKind, TypeLayoutReflection, (jint)self->getKind())
GET_I(jlong, typeLayoutReflectionGetSize, TypeLayoutReflection, (jlong)self->getSize((SlangParameterCategory)i))
GET_I(jlong, typeLayoutReflectionGetStride, TypeLayoutReflection, (jlong)self->getStride((SlangParameterCategory)i))
GET_I(jint, typeLayoutReflectionGetAlignment, TypeLayoutReflection, (jint)self->getAlignment((SlangParameterCategory)i))
GET(jint, typeLayoutReflectionGetFieldCount, TypeLayoutReflection, (jint)self->getFieldCount())
GET_I(jlong, typeLayoutReflectionGetFieldByIndex, TypeLayoutReflection, handle(self->getFieldByIndex((unsigned)i)))
GET(jboolean, typeLayoutReflectionIsArray, TypeLayoutReflection, (jboolean)self->isArray())
GET(jlong, typeLayoutReflectionUnwrapArray, TypeLayoutReflection, handle(self->unwrapArray()))
GET(jlong, typeLayoutReflectionGetElementCount, TypeLayoutReflection, (jlong)self->getElementCount())
GET_I(jlong, typeLayoutReflectionGetElementStride, TypeLayoutReflection, (jlong)self->getElementStride((SlangParameterCategory)i))
GET(jlong, typeLayoutReflectionGetElementTypeLayout, TypeLayoutReflection, handle(self->getElementTypeLayout()))
GET(jlong, typeLayoutReflectionGetElementVarLayout, TypeLayoutReflection, handle(self->getElementVarLayout()))
GET(jlong, typeLayoutReflectionGetContainerVarLayout, TypeLayoutReflection, handle(self->getContainerVarLayout()))
GET(jint, typeLayoutReflectionGetParameterCategory, TypeLayoutReflection, (jint)self->getParameterCategory())
GET(jint, typeLayoutReflectionGetCategoryCount, TypeLayoutReflection, (jint)self->getCategoryCount())
GET_I(jint, typeLayoutReflectionGetCategoryByIndex, TypeLayoutReflection, (jint)self->getCategoryByIndex((unsigned)i))
GET(jint, typeLayoutReflectionGetRowCount, TypeLayoutReflection, (jint)self->getRowCount())
GET(jint, typeLayoutReflectionGetColumnCount, TypeLayoutReflection, (jint)self->getColumnCount())
GET(jint, typeLayoutReflectionGetScalarType, TypeLayoutReflection, (jint)self->getScalarType())
GET(jlong, typeLayoutReflectionGetResourceResultType, TypeLayoutReflection, handle(self->getResourceResultType()))
GET(jstring, typeLayoutReflectionGetName, TypeLayoutReflection, toJString(env, self->getName()))

JNI_FN(jlong, typeLayoutReflectionFindFieldIndexByName)(JNIEnv* env, jclass, jlong h, jstring jName)
{
    return (jlong)ptr<TypeLayoutReflection>(h)->findFieldIndexByName(
        toStdString(env, jName).c_str());
}

// ---------------------------------------------------------------------------
// Attribute (UserAttribute)
// ---------------------------------------------------------------------------

GET(jstring, attributeGetName, Attribute, toJString(env, self->getName()))
GET(jint, attributeGetArgumentCount, Attribute, (jint)self->getArgumentCount())
GET_I(jlong, attributeGetArgumentType, Attribute, handle(self->getArgumentType((uint32_t)i)))

// The getArgumentValue* functions return whether the SlangResult succeeded and store
// the value in out[0].
JNI_FN(jboolean, attributeGetArgumentValueInt)(
    JNIEnv* env, jclass, jlong h, jint index, jintArray out)
{
    int value = 0;
    if (SLANG_FAILED(ptr<Attribute>(h)->getArgumentValueInt((uint32_t)index, &value)))
        return JNI_FALSE;
    const jint jValue = value;
    env->SetIntArrayRegion(out, 0, 1, &jValue);
    return JNI_TRUE;
}

JNI_FN(jboolean, attributeGetArgumentValueFloat)(
    JNIEnv* env, jclass, jlong h, jint index, jfloatArray out)
{
    float value = 0;
    if (SLANG_FAILED(ptr<Attribute>(h)->getArgumentValueFloat((uint32_t)index, &value)))
        return JNI_FALSE;
    env->SetFloatArrayRegion(out, 0, 1, &value);
    return JNI_TRUE;
}

JNI_FN(jstring, attributeGetArgumentValueString)(JNIEnv* env, jclass, jlong h, jint index)
{
    size_t size = 0;
    const char* value = ptr<Attribute>(h)->getArgumentValueString((uint32_t)index, &size);
    if (!value)
        return nullptr;
    return env->NewStringUTF(std::string(value, size).c_str());
}
