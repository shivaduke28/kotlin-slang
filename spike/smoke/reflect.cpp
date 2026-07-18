// Reflection dump: compile Arshes test shaders to SPIR-V and dump the same
// parameter information Arshes' extractParameters reads on iOS (name,
// category, binding index, user attributes, type/size/alignment, resource
// element type) plus bindingSpace, which matters for Vulkan descriptor sets.
// Usage: reflect_run <prelude.slang> <shader.slang>...
#include <slang-com-ptr.h>
#include <slang.h>

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

static std::string readFile(const char* path)
{
    std::ifstream in(path);
    std::stringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

static const char* categoryName(slang::ParameterCategory c)
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
    case slang::ParameterCategory::SubElementRegisterSpace: return "subElementRegisterSpace";
    case slang::ParameterCategory::RegisterSpace: return "registerSpace";
    default: return "other";
    }
}

static const char* kindName(slang::TypeReflection::Kind k)
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

static void dumpUserAttributes(slang::VariableReflection* var, const char* indent)
{
    if (!var)
        return;
    const unsigned count = var->getUserAttributeCount();
    for (unsigned a = 0; a < count; a++)
    {
        slang::Attribute* attr = var->getUserAttributeByIndex(a);
        if (!attr)
            continue;
        std::printf("%s[%s(", indent, attr->getName());
        const uint32_t argCount = attr->getArgumentCount();
        for (uint32_t g = 0; g < argCount; g++)
        {
            float f = 0;
            int i = 0;
            if (SLANG_SUCCEEDED(attr->getArgumentValueFloat(g, &f)))
                std::printf("%s%g", g ? ", " : "", f);
            else if (SLANG_SUCCEEDED(attr->getArgumentValueInt(g, &i)))
                std::printf("%s%d", g ? ", " : "", i);
            else
            {
                size_t len = 0;
                const char* s = attr->getArgumentValueString(g, &len);
                std::printf("%s\"%.*s\"", g ? ", " : "", (int)len, s ? s : "");
            }
        }
        std::printf(")]\n");
    }
}

static void dumpParameter(slang::VariableLayoutReflection* param, const char* indent)
{
    if (!param)
        return;
    slang::TypeLayoutReflection* typeLayout = param->getTypeLayout();

    std::printf(
        "%s%-16s category=%-19s index=%u space=%u offset=%zu",
        indent,
        param->getName() ? param->getName() : "(anon)",
        categoryName((slang::ParameterCategory)param->getCategory()),
        (unsigned)param->getBindingIndex(),
        (unsigned)param->getBindingSpace(),
        param->getOffset(SLANG_PARAMETER_CATEGORY_UNIFORM));

    if (typeLayout)
    {
        std::printf(
            " kind=%s size=%zu align=%zu",
            kindName(typeLayout->getKind()),
            typeLayout->getSize(SLANG_PARAMETER_CATEGORY_UNIFORM),
            typeLayout->getAlignment(SLANG_PARAMETER_CATEGORY_UNIFORM));

        if (slang::TypeLayoutReflection* element = typeLayout->getElementTypeLayout())
        {
            const size_t elementSize = element->getSize(SLANG_PARAMETER_CATEGORY_UNIFORM);
            if (elementSize > 0)
                std::printf(" elemSize=%zu", elementSize);
        }

        // RWTexture2D<T> / Texture2D<T> の T
        if (typeLayout->getKind() == slang::TypeReflection::Kind::Resource)
        {
            if (slang::TypeReflection* result = typeLayout->getType()->getResourceResultType())
            {
                const int components =
                    result->getKind() == slang::TypeReflection::Kind::Vector
                        ? (int)result->getElementCount()
                        : 1;
                std::printf(" resultKind=%s components=%d", kindName(result->getKind()), components);
            }
        }
    }
    std::printf("\n");
    dumpUserAttributes(param->getVariable(), "                     ");
}

int main(int argc, char** argv)
{
    using namespace slang;

    if (argc < 3)
    {
        std::printf("usage: %s <prelude.slang> <shader.slang>...\n", argv[0]);
        return 64;
    }

    Slang::ComPtr<IGlobalSession> globalSession;
    if (SLANG_FAILED(slang_createGlobalSession(SLANG_API_VERSION, globalSession.writeRef())))
    {
        std::printf("FATAL: failed to create global session\n");
        return 1;
    }

    const std::string prelude = readFile(argv[1]);

    TargetDesc target = {};
    target.format = SLANG_SPIRV;
    target.profile = globalSession->findProfile("spirv_1_5");

    PreprocessorMacroDesc macros[] = {
        {"RESOLUTION_X", "1920"},
        {"RESOLUTION_Y", "1080"},
        {"DEPTH_RESOLUTION_X", "256"},
        {"DEPTH_RESOLUTION_Y", "192"},
    };

    int failures = 0;
    for (int i = 2; i < argc; i++)
    {
        std::printf("=== %s ===\n", argv[i]);
        const std::string source = prelude + "\n" + readFile(argv[i]);

        SessionDesc sessionDesc = {};
        sessionDesc.targets = &target;
        sessionDesc.targetCount = 1;
        sessionDesc.preprocessorMacros = macros;
        sessionDesc.preprocessorMacroCount = sizeof(macros) / sizeof(macros[0]);

        Slang::ComPtr<ISession> session;
        if (SLANG_FAILED(globalSession->createSession(sessionDesc, session.writeRef())))
        {
            std::printf("FAIL (session)\n");
            failures++;
            continue;
        }

        Slang::ComPtr<ISlangBlob> diagnostics;
        IModule* module = session->loadModuleFromSourceString(
            "shader", "shader.slang", source.c_str(), diagnostics.writeRef());
        if (!module)
        {
            std::printf("FAIL (load)\n");
            if (diagnostics)
                std::printf("%s\n", static_cast<const char*>(diagnostics->getBufferPointer()));
            failures++;
            continue;
        }

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
        {
            std::printf("FAIL (compose)\n");
            failures++;
            continue;
        }

        Slang::ComPtr<IComponentType> linked;
        if (SLANG_FAILED(program->link(linked.writeRef(), nullptr)))
        {
            std::printf("FAIL (link)\n");
            failures++;
            continue;
        }

        Slang::ComPtr<ISlangBlob> layoutDiag;
        ProgramLayout* layout = linked->getLayout(0, layoutDiag.writeRef());
        if (!layout)
        {
            std::printf("FAIL (layout)\n");
            if (layoutDiag)
                std::printf("%s\n", static_cast<const char*>(layoutDiag->getBufferPointer()));
            failures++;
            continue;
        }

        // Arshes extractParameters相当: グローバルパラメータの一覧
        const unsigned paramCount = layout->getParameterCount();
        std::printf("global parameters: %u\n", paramCount);
        for (unsigned p = 0; p < paramCount; p++)
            dumpParameter(layout->getParameterByIndex(p), "  ");

        // グローバルuniformをまとめたバッファのレイアウト
        if (slang::TypeLayoutReflection* globals = layout->getGlobalParamsTypeLayout())
        {
            std::printf(
                "globals: kind=%s size=%zu\n",
                kindName(globals->getKind()),
                globals->getSize(SLANG_PARAMETER_CATEGORY_UNIFORM));
        }

        // エントリポイント一覧
        const SlangUInt epCount = layout->getEntryPointCount();
        for (SlangUInt e = 0; e < epCount; e++)
        {
            EntryPointReflection* ep = layout->getEntryPointByIndex(e);
            if (!ep)
                continue;
            std::printf("entry: %s stage=%d\n", ep->getName(), (int)ep->getStage());
        }
        std::printf("\n");
    }

    std::printf("%s (%d failures)\n", failures == 0 ? "ALL OK" : "FAILED", failures);
    return failures == 0 ? 0 : 1;
}
