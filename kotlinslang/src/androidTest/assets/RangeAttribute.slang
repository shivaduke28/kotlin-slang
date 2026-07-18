[__AttributeUsage(_AttributeTargets.Var)]
struct rangeAttribute {
    float min;
    float max;
    float value;
};

[__AttributeUsage(_AttributeTargets.Var)]
struct rgbAttribute {
    float r;
    float g;
    float b;
};

[__AttributeUsage(_AttributeTargets.Var)]
struct rgbaAttribute {
    float r;
    float g;
    float b;
    float a;
};

[__AttributeUsage(_AttributeTargets.Var)]
struct toggleAttribute {
    int value;
};

[__AttributeUsage(_AttributeTargets.Function)]
struct dispatchAttribute {
    int x;
    int y;
    int z;
};


[__AttributeUsage(_AttributeTargets.Var)]
struct sizeAttribute {
    int count;
};

[__AttributeUsage(_AttributeTargets.Var)]
struct size2dAttribute {
    int width;
    int height;
};

[__AttributeUsage(_AttributeTargets.Function)]
struct primitiveAttribute {
    int type;
    int count;
};

[__AttributeUsage(_AttributeTargets.Function)]
struct passAttribute {
    int index;
};

enum BlendMode {
    None = 0,
    Additive = 1,
    Alpha = 2,
};

[__AttributeUsage(_AttributeTargets.Function)]
struct blendAttribute {
    BlendMode mode;
};
