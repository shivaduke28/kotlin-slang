// JNI boundary for kotlin-slang.
//
// The whole surface is a single call: compile Slang source to SPIR-V for all
// defined entry points and return reflection metadata as JSON plus the SPIR-V
// blobs. Everything richer (typed models, pass resolution) lives in Kotlin.
#include <jni.h>
#include <slang-com-ptr.h>
#include <slang.h>

#include <cstdint>
#include <string>
#include <vector>

namespace
{

void appendEscaped(std::string& out, const char* s)
{
    if (!s)
        return;
    for (const char* p = s; *p; p++)
    {
        const char c = *p;
        switch (c)
        {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (static_cast<unsigned char>(c) < 0x20)
            {
                char buf[8];
                snprintf(buf, sizeof(buf), "\\u%04x", c);
                out += buf;
            }
            else
            {
                out += c;
            }
        }
    }
}

void appendString(std::string& out, const char* key, const char* value)
{
    out += '"';
    out += key;
    out += "\":\"";
    appendEscaped(out, value);
    out += '"';
}

const char* categoryName(slang::ParameterCategory c)
{
    switch (c)
    {
    case slang::ParameterCategory::ConstantBuffer: return "constantBuffer";
    case slang::ParameterCategory::ShaderResource: return "shaderResource";
    case slang::ParameterCategory::UnorderedAccess: return "unorderedAccess";
    case slang::ParameterCategory::SamplerState: return "samplerState";
    case slang::ParameterCategory::Uniform: return "uniform";
    case slang::ParameterCategory::DescriptorTableSlot: return "descriptorTableSlot";
    case slang::ParameterCategory::Mixed: return "mixed";
    case slang::ParameterCategory::RegisterSpace: return "registerSpace";
    default: return "other";
    }
}

const char* kindName(slang::TypeReflection::Kind k)
{
    using Kind = slang::TypeReflection::Kind;
    switch (k)
    {
    case Kind::Scalar: return "scalar";
    case Kind::Vector: return "vector";
    case Kind::Matrix: return "matrix";
    case Kind::Resource: return "resource";
    case Kind::SamplerState: return "samplerState";
    case Kind::Struct: return "struct";
    case Kind::Array: return "array";
    case Kind::ConstantBuffer: return "constantBuffer";
    case Kind::ParameterBlock: return "parameterBlock";
    default: return "other";
    }
}

const char* scalarName(slang::TypeReflection::ScalarType s)
{
    using S = slang::TypeReflection::ScalarType;
    switch (s)
    {
    case S::Float32: return "float32";
    case S::Float16: return "float16";
    case S::Float64: return "float64";
    case S::Int32: return "int32";
    case S::UInt32: return "uint32";
    case S::Int64: return "int64";
    case S::UInt64: return "uint64";
    case S::Int16: return "int16";
    case S::UInt16: return "uint16";
    case S::Int8: return "int8";
    case S::UInt8: return "uint8";
    case S::Bool: return "bool";
    default: return "none";
    }
}

void appendUserAttributes(std::string& json, slang::VariableReflection* var)
{
    json += "\"attributes\":[";
    if (var)
    {
        const unsigned count = var->getUserAttributeCount();
        for (unsigned a = 0; a < count; a++)
        {
            slang::Attribute* attr = var->getUserAttributeByIndex(a);
            if (!attr)
                continue;
            if (a > 0)
                json += ',';
            json += '{';
            appendString(json, "name", attr->getName());
            json += ",\"args\":[";
            const uint32_t argCount = attr->getArgumentCount();
            for (uint32_t g = 0; g < argCount; g++)
            {
                if (g > 0)
                    json += ',';
                float f = 0;
                int i = 0;
                if (SLANG_SUCCEEDED(attr->getArgumentValueFloat(g, &f)))
                {
                    char buf[32];
                    snprintf(buf, sizeof(buf), "%g", f);
                    json += buf;
                }
                else if (SLANG_SUCCEEDED(attr->getArgumentValueInt(g, &i)))
                {
                    json += std::to_string(i);
                }
                else
                {
                    size_t len = 0;
                    const char* s = attr->getArgumentValueString(g, &len);
                    json += '"';
                    if (s)
                    {
                        std::string tmp(s, len);
                        appendEscaped(json, tmp.c_str());
                    }
                    json += '"';
                }
            }
            json += "]}";
        }
    }
    json += ']';
}

void appendParameter(std::string& json, slang::VariableLayoutReflection* param)
{
    slang::TypeLayoutReflection* typeLayout = param->getTypeLayout();

    json += '{';
    appendString(json, "name", param->getName() ? param->getName() : "");
    json += ',';
    appendString(json, "category", categoryName((slang::ParameterCategory)param->getCategory()));
    json += ",\"bindingIndex\":" + std::to_string(param->getBindingIndex());
    json += ",\"bindingSpace\":" + std::to_string(param->getBindingSpace());
    json += ",\"uniformOffset\":" +
        std::to_string(param->getOffset(SLANG_PARAMETER_CATEGORY_UNIFORM));

    if (typeLayout)
    {
        json += ',';
        appendString(json, "kind", kindName(typeLayout->getKind()));
        json += ",\"size\":" +
            std::to_string(typeLayout->getSize(SLANG_PARAMETER_CATEGORY_UNIFORM));
        json += ",\"alignment\":" +
            std::to_string(typeLayout->getAlignment(SLANG_PARAMETER_CATEGORY_UNIFORM));

        size_t elementSize = 0;
        if (slang::TypeLayoutReflection* element = typeLayout->getElementTypeLayout())
            elementSize = element->getSize(SLANG_PARAMETER_CATEGORY_UNIFORM);
        json += ",\"elementSize\":" + std::to_string(elementSize);

        if (typeLayout->getKind() == slang::TypeReflection::Kind::Resource)
        {
            if (slang::TypeReflection* result = typeLayout->getType()->getResourceResultType())
            {
                const bool isVector = result->getKind() == slang::TypeReflection::Kind::Vector;
                slang::TypeReflection* scalar =
                    isVector ? result->getElementType() : result;
                json += ",\"resourceResult\":{";
                appendString(json, "kind", kindName(result->getKind()));
                json += ",\"components\":" +
                    std::to_string(isVector ? (int)result->getElementCount() : 1);
                json += ',';
                appendString(
                    json, "scalar", scalar ? scalarName(scalar->getScalarType()) : "none");
                json += '}';
            }
        }
    }
    json += ',';
    appendUserAttributes(json, param->getVariable());
    json += '}';
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

jobject makeResult(JNIEnv* env, const std::string& json, const std::vector<Slang::ComPtr<ISlangBlob>>& blobs)
{
    jclass resultClass = env->FindClass("com/shivaduke/kotlinslang/NativeCompileResult");
    if (!resultClass)
        return nullptr;
    jmethodID ctor = env->GetMethodID(resultClass, "<init>", "(Ljava/lang/String;[[B)V");
    if (!ctor)
        return nullptr;

    jclass byteArrayClass = env->FindClass("[B");
    jobjectArray spirvArray =
        env->NewObjectArray((jsize)blobs.size(), byteArrayClass, nullptr);
    for (size_t i = 0; i < blobs.size(); i++)
    {
        const jsize size = (jsize)blobs[i]->getBufferSize();
        jbyteArray bytes = env->NewByteArray(size);
        env->SetByteArrayRegion(
            bytes, 0, size, static_cast<const jbyte*>(blobs[i]->getBufferPointer()));
        env->SetObjectArrayElement(spirvArray, (jsize)i, bytes);
        env->DeleteLocalRef(bytes);
    }

    jstring jsonString = env->NewStringUTF(json.c_str());
    return env->NewObject(resultClass, ctor, jsonString, spirvArray);
}

jobject makeError(JNIEnv* env, const char* stage, const char* diagnostics)
{
    std::string json = "{\"ok\":false,";
    appendString(json, "errorStage", stage);
    json += ',';
    appendString(json, "diagnostics", diagnostics ? diagnostics : "");
    json += '}';
    return makeResult(env, json, {});
}

// Slang global session is not thread-safe; Kotlin側で単一スレッドから呼ぶ前提。
slang::IGlobalSession* globalSession()
{
    static Slang::ComPtr<slang::IGlobalSession> session = [] {
        Slang::ComPtr<slang::IGlobalSession> s;
        slang_createGlobalSession(SLANG_API_VERSION, s.writeRef());
        return s;
    }();
    return session.get();
}

} // namespace

extern "C" JNIEXPORT jobject JNICALL
Java_com_shivaduke_kotlinslang_SlangCompiler_nativeCompile(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring jSource,
    jobjectArray jMacroKeys,
    jobjectArray jMacroValues)
{
    using namespace slang;

    IGlobalSession* global = globalSession();
    if (!global)
        return makeError(env, "globalSession", nullptr);

    const std::string source = toStdString(env, jSource);

    std::vector<std::string> macroKeys;
    std::vector<std::string> macroValues;
    std::vector<PreprocessorMacroDesc> macros;
    const jsize macroCount = jMacroKeys ? env->GetArrayLength(jMacroKeys) : 0;
    macroKeys.reserve(macroCount);
    macroValues.reserve(macroCount);
    for (jsize i = 0; i < macroCount; i++)
    {
        auto key = (jstring)env->GetObjectArrayElement(jMacroKeys, i);
        auto value = (jstring)env->GetObjectArrayElement(jMacroValues, i);
        macroKeys.push_back(toStdString(env, key));
        macroValues.push_back(toStdString(env, value));
        env->DeleteLocalRef(key);
        env->DeleteLocalRef(value);
    }
    for (jsize i = 0; i < macroCount; i++)
        macros.push_back({macroKeys[i].c_str(), macroValues[i].c_str()});

    TargetDesc target = {};
    target.format = SLANG_SPIRV;
    target.profile = global->findProfile("spirv_1_5");

    SessionDesc sessionDesc = {};
    sessionDesc.targets = &target;
    sessionDesc.targetCount = 1;
    sessionDesc.preprocessorMacros = macros.empty() ? nullptr : macros.data();
    sessionDesc.preprocessorMacroCount = (SlangInt)macros.size();

    Slang::ComPtr<ISession> session;
    if (SLANG_FAILED(global->createSession(sessionDesc, session.writeRef())))
        return makeError(env, "session", nullptr);

    Slang::ComPtr<ISlangBlob> loadDiag;
    IModule* module = session->loadModuleFromSourceString(
        "shader", "shader.slang", source.c_str(), loadDiag.writeRef());
    const char* loadDiagText =
        loadDiag ? static_cast<const char*>(loadDiag->getBufferPointer()) : nullptr;
    if (!module)
        return makeError(env, "load", loadDiagText);

    const SlangInt32 entryPointCount = module->getDefinedEntryPointCount();
    std::vector<Slang::ComPtr<IEntryPoint>> entryPoints;
    std::vector<IComponentType*> components = {module};
    for (SlangInt32 e = 0; e < entryPointCount; e++)
    {
        Slang::ComPtr<IEntryPoint> ep;
        if (SLANG_FAILED(module->getDefinedEntryPoint(e, ep.writeRef())))
            continue;
        components.push_back(ep.get());
        entryPoints.push_back(ep);
    }

    Slang::ComPtr<IComponentType> program;
    if (SLANG_FAILED(session->createCompositeComponentType(
            components.data(), (SlangInt)components.size(), program.writeRef())))
        return makeError(env, "compose", nullptr);

    Slang::ComPtr<IComponentType> linked;
    Slang::ComPtr<ISlangBlob> linkDiag;
    if (SLANG_FAILED(program->link(linked.writeRef(), linkDiag.writeRef())))
        return makeError(
            env,
            "link",
            linkDiag ? static_cast<const char*>(linkDiag->getBufferPointer()) : nullptr);

    Slang::ComPtr<ISlangBlob> layoutDiag;
    ProgramLayout* layout = linked->getLayout(0, layoutDiag.writeRef());
    if (!layout)
        return makeError(
            env,
            "layout",
            layoutDiag ? static_cast<const char*>(layoutDiag->getBufferPointer()) : nullptr);

    std::string json = "{\"ok\":true,";
    appendString(json, "diagnostics", loadDiagText ? loadDiagText : "");

    json += ",\"entryPoints\":[";
    std::vector<Slang::ComPtr<ISlangBlob>> blobs;
    for (size_t e = 0; e < entryPoints.size(); e++)
    {
        Slang::ComPtr<ISlangBlob> code;
        Slang::ComPtr<ISlangBlob> emitDiag;
        if (SLANG_FAILED(
                linked->getEntryPointCode((SlangInt)e, 0, code.writeRef(), emitDiag.writeRef())))
            return makeError(
                env,
                "emit",
                emitDiag ? static_cast<const char*>(emitDiag->getBufferPointer()) : nullptr);

        EntryPointReflection* ep = layout->getEntryPointByIndex((SlangUInt)e);
        if (e > 0)
            json += ',';
        json += '{';
        appendString(json, "name", ep ? ep->getName() : "");
        json += ",\"stage\":" + std::to_string(ep ? (int)ep->getStage() : 0);
        json += ",\"spirvIndex\":" + std::to_string(blobs.size());
        json += '}';
        blobs.push_back(code);
    }
    json += ']';

    json += ",\"parameters\":[";
    const unsigned paramCount = layout->getParameterCount();
    for (unsigned p = 0; p < paramCount; p++)
    {
        if (p > 0)
            json += ',';
        appendParameter(json, layout->getParameterByIndex(p));
    }
    json += "]}";

    return makeResult(env, json, blobs);
}
