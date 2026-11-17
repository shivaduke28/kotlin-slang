package com.shivaduke.kotlinslang

/**
 * The JNI functions in kotlinslang_jni.cpp, one per Slang API method. Handles are raw
 * native pointers; 0 stands for null. See the header comment of that file for what each
 * kind of handle points to and how long it stays valid.
 */
internal object SlangNative {
    init {
        System.loadLibrary("kotlinslang")
    }

    @JvmStatic external fun createGlobalSession(): Long
    @JvmStatic external fun globalSessionRelease(h: Long)
    @JvmStatic external fun globalSessionFindProfile(h: Long, name: String): Int
    @JvmStatic external fun globalSessionGetBuildTagString(h: Long): String?
    @JvmStatic external fun globalSessionCreateSession(h: Long, targetFormats: IntArray, targetProfiles: IntArray, searchPaths: Array<String>, macroNames: Array<String>, macroValues: Array<String>): Long
    @JvmStatic external fun sessionRelease(h: Long)
    @JvmStatic external fun sessionLoadModule(h: Long, moduleName: String, outDiagnostics: Array<String?>?): Long
    @JvmStatic external fun sessionLoadModuleFromSourceString(h: Long, moduleName: String, path: String, string: String, outDiagnostics: Array<String?>?): Long
    @JvmStatic external fun sessionCreateCompositeComponentType(h: Long, componentTypes: LongArray, outDiagnostics: Array<String?>?): Long
    @JvmStatic external fun sessionGetLoadedModuleCount(h: Long): Long
    @JvmStatic external fun sessionGetLoadedModule(h: Long, index: Long): Long
    @JvmStatic external fun componentTypeGetLayout(h: Long, targetIndex: Long, outDiagnostics: Array<String?>?): Long
    @JvmStatic external fun componentTypeGetEntryPointCode(h: Long, entryPointIndex: Long, targetIndex: Long, outDiagnostics: Array<String?>?): ByteArray?
    @JvmStatic external fun componentTypeGetTargetCode(h: Long, targetIndex: Long, outDiagnostics: Array<String?>?): ByteArray?
    @JvmStatic external fun componentTypeLink(session: Long, h: Long, outDiagnostics: Array<String?>?): Long
    @JvmStatic external fun moduleFindEntryPointByName(session: Long, h: Long, name: String): Long
    @JvmStatic external fun moduleGetDefinedEntryPointCount(h: Long): Int
    @JvmStatic external fun moduleGetDefinedEntryPoint(session: Long, h: Long, index: Int): Long
    @JvmStatic external fun moduleGetName(h: Long): String?
    @JvmStatic external fun moduleGetFilePath(h: Long): String?
    @JvmStatic external fun moduleFindAndCheckEntryPoint(session: Long, h: Long, name: String, stage: Int, outDiagnostics: Array<String?>?): Long
    @JvmStatic external fun entryPointGetFunctionReflection(h: Long): Long
    @JvmStatic external fun programLayoutGetParameterCount(h: Long): Int
    @JvmStatic external fun programLayoutGetParameterByIndex(h: Long, i: Int): Long
    @JvmStatic external fun programLayoutGetEntryPointCount(h: Long): Long
    @JvmStatic external fun programLayoutGetEntryPointByIndex(h: Long, i: Int): Long
    @JvmStatic external fun programLayoutGetGlobalConstantBufferBinding(h: Long): Long
    @JvmStatic external fun programLayoutGetGlobalConstantBufferSize(h: Long): Long
    @JvmStatic external fun programLayoutGetGlobalParamsTypeLayout(h: Long): Long
    @JvmStatic external fun programLayoutGetGlobalParamsVarLayout(h: Long): Long
    @JvmStatic external fun programLayoutFindEntryPointByName(h: Long, name: String): Long
    @JvmStatic external fun entryPointReflectionGetName(h: Long): String?
    @JvmStatic external fun entryPointReflectionGetNameOverride(h: Long): String?
    @JvmStatic external fun entryPointReflectionGetParameterCount(h: Long): Int
    @JvmStatic external fun entryPointReflectionGetFunction(h: Long): Long
    @JvmStatic external fun entryPointReflectionGetParameterByIndex(h: Long, i: Int): Long
    @JvmStatic external fun entryPointReflectionGetStage(h: Long): Int
    @JvmStatic external fun entryPointReflectionGetVarLayout(h: Long): Long
    @JvmStatic external fun entryPointReflectionGetTypeLayout(h: Long): Long
    @JvmStatic external fun entryPointReflectionGetResultVarLayout(h: Long): Long
    @JvmStatic external fun entryPointReflectionHasDefaultConstantBuffer(h: Long): Boolean
    @JvmStatic external fun entryPointReflectionGetComputeThreadGroupSize(h: Long, outSizeAlongAxis: LongArray)
    @JvmStatic external fun functionReflectionGetName(h: Long): String?
    @JvmStatic external fun functionReflectionGetReturnType(h: Long): Long
    @JvmStatic external fun functionReflectionGetParameterCount(h: Long): Int
    @JvmStatic external fun functionReflectionGetParameterByIndex(h: Long, i: Int): Long
    @JvmStatic external fun functionReflectionGetUserAttributeCount(h: Long): Int
    @JvmStatic external fun functionReflectionGetUserAttributeByIndex(h: Long, i: Int): Long
    @JvmStatic external fun variableReflectionGetName(h: Long): String?
    @JvmStatic external fun variableReflectionGetType(h: Long): Long
    @JvmStatic external fun variableReflectionGetUserAttributeCount(h: Long): Int
    @JvmStatic external fun variableReflectionGetUserAttributeByIndex(h: Long, i: Int): Long
    @JvmStatic external fun variableLayoutReflectionGetVariable(h: Long): Long
    @JvmStatic external fun variableLayoutReflectionGetName(h: Long): String?
    @JvmStatic external fun variableLayoutReflectionGetTypeLayout(h: Long): Long
    @JvmStatic external fun variableLayoutReflectionGetCategory(h: Long): Int
    @JvmStatic external fun variableLayoutReflectionGetCategoryCount(h: Long): Int
    @JvmStatic external fun variableLayoutReflectionGetCategoryByIndex(h: Long, i: Int): Int
    @JvmStatic external fun variableLayoutReflectionGetOffset(h: Long, i: Int): Long
    @JvmStatic external fun variableLayoutReflectionGetType(h: Long): Long
    @JvmStatic external fun variableLayoutReflectionGetBindingIndex(h: Long): Int
    @JvmStatic external fun variableLayoutReflectionGetBindingSpace(h: Long): Int
    @JvmStatic external fun variableLayoutReflectionGetBindingSpaceForCategory(h: Long, i: Int): Long
    @JvmStatic external fun variableLayoutReflectionGetSemanticName(h: Long): String?
    @JvmStatic external fun variableLayoutReflectionGetSemanticIndex(h: Long): Long
    @JvmStatic external fun variableLayoutReflectionGetStage(h: Long): Int
    @JvmStatic external fun typeReflectionGetKind(h: Long): Int
    @JvmStatic external fun typeReflectionGetFieldCount(h: Long): Int
    @JvmStatic external fun typeReflectionGetFieldByIndex(h: Long, i: Int): Long
    @JvmStatic external fun typeReflectionIsArray(h: Long): Boolean
    @JvmStatic external fun typeReflectionUnwrapArray(h: Long): Long
    @JvmStatic external fun typeReflectionGetElementCount(h: Long): Long
    @JvmStatic external fun typeReflectionGetElementType(h: Long): Long
    @JvmStatic external fun typeReflectionGetRowCount(h: Long): Int
    @JvmStatic external fun typeReflectionGetColumnCount(h: Long): Int
    @JvmStatic external fun typeReflectionGetScalarType(h: Long): Int
    @JvmStatic external fun typeReflectionGetResourceResultType(h: Long): Long
    @JvmStatic external fun typeReflectionGetName(h: Long): String?
    @JvmStatic external fun typeReflectionGetUserAttributeCount(h: Long): Int
    @JvmStatic external fun typeReflectionGetUserAttributeByIndex(h: Long, i: Int): Long
    @JvmStatic external fun typeLayoutReflectionGetType(h: Long): Long
    @JvmStatic external fun typeLayoutReflectionGetKind(h: Long): Int
    @JvmStatic external fun typeLayoutReflectionGetSize(h: Long, i: Int): Long
    @JvmStatic external fun typeLayoutReflectionGetStride(h: Long, i: Int): Long
    @JvmStatic external fun typeLayoutReflectionGetAlignment(h: Long, i: Int): Int
    @JvmStatic external fun typeLayoutReflectionGetFieldCount(h: Long): Int
    @JvmStatic external fun typeLayoutReflectionGetFieldByIndex(h: Long, i: Int): Long
    @JvmStatic external fun typeLayoutReflectionIsArray(h: Long): Boolean
    @JvmStatic external fun typeLayoutReflectionUnwrapArray(h: Long): Long
    @JvmStatic external fun typeLayoutReflectionGetElementCount(h: Long): Long
    @JvmStatic external fun typeLayoutReflectionGetElementStride(h: Long, i: Int): Long
    @JvmStatic external fun typeLayoutReflectionGetElementTypeLayout(h: Long): Long
    @JvmStatic external fun typeLayoutReflectionGetElementVarLayout(h: Long): Long
    @JvmStatic external fun typeLayoutReflectionGetContainerVarLayout(h: Long): Long
    @JvmStatic external fun typeLayoutReflectionGetParameterCategory(h: Long): Int
    @JvmStatic external fun typeLayoutReflectionGetCategoryCount(h: Long): Int
    @JvmStatic external fun typeLayoutReflectionGetCategoryByIndex(h: Long, i: Int): Int
    @JvmStatic external fun typeLayoutReflectionGetRowCount(h: Long): Int
    @JvmStatic external fun typeLayoutReflectionGetColumnCount(h: Long): Int
    @JvmStatic external fun typeLayoutReflectionGetScalarType(h: Long): Int
    @JvmStatic external fun typeLayoutReflectionGetResourceResultType(h: Long): Long
    @JvmStatic external fun typeLayoutReflectionGetName(h: Long): String?
    @JvmStatic external fun typeLayoutReflectionFindFieldIndexByName(h: Long, name: String): Long
    @JvmStatic external fun attributeGetName(h: Long): String?
    @JvmStatic external fun attributeGetArgumentCount(h: Long): Int
    @JvmStatic external fun attributeGetArgumentType(h: Long, i: Int): Long
    @JvmStatic external fun attributeGetArgumentValueInt(h: Long, index: Int, out: IntArray): Boolean
    @JvmStatic external fun attributeGetArgumentValueFloat(h: Long, index: Int, out: FloatArray): Boolean
    @JvmStatic external fun attributeGetArgumentValueString(h: Long, index: Int): String?
}
