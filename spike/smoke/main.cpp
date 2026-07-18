#include <cstdio>

extern "C" int ks_smoke_compile(char* outLog, int outLogSize, int* outSpirvSize);

int main()
{
    char log[4096] = {};
    int spirvSize = 0;
    int result = ks_smoke_compile(log, sizeof(log), &spirvSize);
    if (log[0] != '\0')
        std::printf("diagnostics:\n%s\n", log);
    if (result != 0)
    {
        std::printf("FAILED: step %d\n", result);
        return result;
    }
    std::printf("OK: compiled fragment shader to SPIR-V (%d bytes)\n", spirvSize);
    return 0;
}
