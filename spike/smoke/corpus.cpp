// Corpus compile test: compile Arshes test shaders to SPIR-V on-device.
// Usage: corpus_run <prelude.slang> <shader.slang>...
// Mirrors ArshesのSlangCompiler: prelude prepended to user source, resolution
// macros defined on the session, all defined entry points linked and emitted.
#include <slang-com-ptr.h>
#include <slang.h>

#include <cstdio>
#include <ctime>
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

static double nowMs()
{
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
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
    if (prelude.empty())
    {
        std::printf("FATAL: empty prelude at %s\n", argv[1]);
        return 1;
    }

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
        const double start = nowMs();
        const std::string source = prelude + "\n" + readFile(argv[i]);

        SessionDesc sessionDesc = {};
        sessionDesc.targets = &target;
        sessionDesc.targetCount = 1;
        sessionDesc.preprocessorMacros = macros;
        sessionDesc.preprocessorMacroCount = sizeof(macros) / sizeof(macros[0]);

        Slang::ComPtr<ISession> session;
        if (SLANG_FAILED(globalSession->createSession(sessionDesc, session.writeRef())))
        {
            std::printf("FAIL %-24s (session creation)\n", argv[i]);
            failures++;
            continue;
        }

        Slang::ComPtr<ISlangBlob> diagnostics;
        IModule* module = session->loadModuleFromSourceString(
            "shader", "shader.slang", source.c_str(), diagnostics.writeRef());
        if (!module)
        {
            std::printf("FAIL %-24s (load)\n", argv[i]);
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
            std::printf("FAIL %-24s (compose)\n", argv[i]);
            failures++;
            continue;
        }

        Slang::ComPtr<IComponentType> linked;
        Slang::ComPtr<ISlangBlob> linkDiag;
        if (SLANG_FAILED(program->link(linked.writeRef(), linkDiag.writeRef())))
        {
            std::printf("FAIL %-24s (link)\n", argv[i]);
            if (linkDiag)
                std::printf("%s\n", static_cast<const char*>(linkDiag->getBufferPointer()));
            failures++;
            continue;
        }

        size_t totalSpirv = 0;
        bool emitFailed = false;
        for (size_t e = 0; e < entryPoints.size(); e++)
        {
            Slang::ComPtr<ISlangBlob> code;
            Slang::ComPtr<ISlangBlob> emitDiag;
            if (SLANG_FAILED(
                    linked->getEntryPointCode((SlangInt)e, 0, code.writeRef(), emitDiag.writeRef())))
            {
                std::printf("FAIL %-24s (emit entry %zu)\n", argv[i], e);
                if (emitDiag)
                    std::printf("%s\n", static_cast<const char*>(emitDiag->getBufferPointer()));
                emitFailed = true;
                break;
            }
            totalSpirv += code->getBufferSize();
        }
        if (emitFailed)
        {
            failures++;
            continue;
        }

        std::printf(
            "OK   %-24s entries=%d spirv=%zuB %.0fms\n",
            argv[i],
            (int)entryPointCount,
            totalSpirv,
            nowMs() - start);
    }

    std::printf("\n%s (%d failures)\n", failures == 0 ? "ALL OK" : "FAILED", failures);
    return failures == 0 ? 0 : 1;
}
