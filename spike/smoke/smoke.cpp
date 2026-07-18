// Minimal link/size smoke test: create a Slang global session and compile a
// trivial fragment shader to SPIR-V. Exercises the same entry points the real
// JNI wrapper will use, so the resulting .so size approximates the app impact.
#include <slang-com-ptr.h>
#include <slang.h>

#include <cstring>

extern "C" __attribute__((visibility("default"))) int ks_smoke_compile(
    char* outLog, int outLogSize, int* outSpirvSize)
{
    using namespace slang;

    Slang::ComPtr<IGlobalSession> globalSession;
    if (SLANG_FAILED(slang_createGlobalSession(SLANG_API_VERSION, globalSession.writeRef())))
        return 1;

    TargetDesc target = {};
    target.format = SLANG_SPIRV;
    target.profile = globalSession->findProfile("spirv_1_5");

    SessionDesc sessionDesc = {};
    sessionDesc.targets = &target;
    sessionDesc.targetCount = 1;

    Slang::ComPtr<ISession> session;
    if (SLANG_FAILED(globalSession->createSession(sessionDesc, session.writeRef())))
        return 2;

    static const char* kSource = R"(
[shader("fragment")]
float4 fragmentMain() : SV_Target
{
    return float4(1.0, 0.0, 1.0, 1.0);
}
)";

    Slang::ComPtr<ISlangBlob> diagnostics;
    IModule* module =
        session->loadModuleFromSourceString("smoke", "smoke.slang", kSource, diagnostics.writeRef());
    if (diagnostics && outLog && outLogSize > 0)
    {
        const char* text = static_cast<const char*>(diagnostics->getBufferPointer());
        std::strncpy(outLog, text, outLogSize - 1);
        outLog[outLogSize - 1] = '\0';
    }
    if (!module)
        return 3;

    Slang::ComPtr<IEntryPoint> entryPoint;
    if (SLANG_FAILED(module->findEntryPointByName("fragmentMain", entryPoint.writeRef())))
        return 4;

    IComponentType* components[] = {module, entryPoint.get()};
    Slang::ComPtr<IComponentType> program;
    if (SLANG_FAILED(session->createCompositeComponentType(components, 2, program.writeRef())))
        return 5;

    Slang::ComPtr<IComponentType> linked;
    if (SLANG_FAILED(program->link(linked.writeRef(), nullptr)))
        return 6;

    Slang::ComPtr<ISlangBlob> code;
    if (SLANG_FAILED(linked->getEntryPointCode(0, 0, code.writeRef(), nullptr)))
        return 7;

    if (outSpirvSize)
        *outSpirvSize = static_cast<int>(code->getBufferSize());
    return 0;
}
