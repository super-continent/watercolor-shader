// An implementation of the Guided Blur proposed by He et al. in 2013

#include "ReShade.fxh"
#include "ShaderCommon.fxh"

#ifndef KERNEL_SIZE
#define KERNEL_SIZE 16
#endif

#ifndef SAMPLING_MULTIPLIER
#define SAMPLING_MULTIPLIER 0.5
#endif

#define BACKBUFFER ReShade::BackBuffer

// in the case of this shader, these images are identical in content.
// I is the guidance image
// p is the filtering image
// q is the filter output

uniform float fEpsilon <
    ui_type = "slider";
    ui_min = 0.001;
    ui_max = 1.0;
    ui_label = "Edge Detection Factor";
    ui_step = 0.01;
> = 0.35;

uniform float fSigma <
    ui_type = "slider";
    ui_label = "Blur Distance Weight";
    ui_min = 0.1;
    ui_max = 10.0;
    ui_step = 0.1;
> = 8.0;

texture2D buffer0Tex <pooled = true;>
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D buffer0Sampler
{
    Texture = buffer0Tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D buffer1Tex <pooled = true;>
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D buffer1Sampler
{
    Texture = buffer1Tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

// we can reuse the same 2 buffers for these variables
#define MEAN_I_SAMPLER buffer0Sampler
#define MEAN_P_SAMPLER buffer0Sampler
#define CORR_I_SAMPLER buffer1Sampler
#define MEAN_A_SAMPLER buffer1Sampler
#define MEAN_B_SAMPLER buffer0Sampler

#define MEAN_I_TEX buffer0Tex
#define MEAN_P_TEX buffer0Tex
#define CORR_I_TEX buffer1Tex
#define MEAN_A_TEX buffer1Tex
#define MEAN_B_TEX buffer0Tex

float normpdf(float x, float sigma)
{
    return (1 / sqrt(2.0 * M_PI) * sigma) * exp(-0.5 * pow(x / sigma, 2.0));
}

// vertical pass of a separated Gaussian blur
float4 gaussianVerticalPass(sampler2D s, float2 tex)
{
    const int kernel_radius = (KERNEL_SIZE) / 2;

    float weight = 0;
    float4 final_color = float4(0.0, 0.0, 0.0, 0.0);
    for (int x = -kernel_radius; x <= kernel_radius; ++x)
    {
        float w = normpdf(x, fSigma);
        weight += w;
        float2 sample_offset = float2(0, x) * (BUFFER_PIXEL_SIZE);
        final_color += tex2D(s, tex + sample_offset) * w;
    }

    return final_color / weight;
}

// horizontal pass of a separated Gaussian blur
float4 gaussianHorizontalPass(sampler2D s, float2 tex)
{
    const int kernel_radius = (KERNEL_SIZE) / 2;

    float weight = 0;
    float4 final_color = float4(0.0, 0.0, 0.0, 0.0);
    for (int x = -kernel_radius; x <= kernel_radius; ++x)
    {
        float w = normpdf(x, fSigma);
        weight += w;
        float2 sample_offset = float2(x, 0) * (BUFFER_PIXEL_SIZE);
        final_color += tex2D(s, tex + sample_offset) * w;
    }

    return final_color / weight;
}

// this language doesnt have support for passing in a sampler to pixel shaders
// and it also doesnt have first class functions so i need to create
// all these wrapper functions to make anything work Lol
namespace Wrappers
{
    [shader("pixel")]
    float4 BackBuffer_gaussianVerticalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianVerticalPass(BACKBUFFER, tex);
    }

    [shader("pixel")]
    float4 buffer0_gaussianVerticalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianVerticalPass(buffer0Sampler, tex);
    }

    [shader("pixel")]
    float4 buffer0_gaussianHorizontalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianHorizontalPass(buffer0Sampler, tex);
    }

    [shader("pixel")]
    float4 buffer1_gaussianHorizontalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianHorizontalPass(buffer1Sampler, tex);
    }

    [shader("pixel")]
    float4 buffer1_gaussianVerticalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianVerticalPass(buffer1Sampler, tex);
    }
}

// multiplies I * p and stores the result for later blurring
[shader("pixel")]
float4 multiplyIp(float4 position : SV_Position, float2 tex : TEXCOORD) : SV_Target
{
    float4 c = tex2D(BACKBUFFER, tex);
    return c * c;
}

[shader("pixel")]
float4 squareI(float4 position : SV_Position, float2 tex : TEXCOORD) : SV_Target
{
    float4 c = tex2D(BACKBUFFER, tex);
    return c * c;
}

[shader("pixel")]
float4 aConstruct(float4 position : SV_Position, float2 tex : TEXCOORD) : SV_Target
{
    float4 mean_i = tex2D(MEAN_I_SAMPLER, tex);
    float4 mean_p = mean_i;
    float4 corr_i = tex2D(CORR_I_SAMPLER, tex);
    float4 corr_ip = corr_i;
    
    float4 var_i = corr_i - mean_i * mean_i;
    float4 cov_ip = corr_ip - mean_i * mean_p;

    // a
    return cov_ip / (var_i + pow(fEpsilon, 5.0));
}

[shader("pixel")]
float4 bConstruct(float4 position : SV_Position, float2 tex : TEXCOORD) : SV_Target
{
    float4 mean_i = tex2D(MEAN_I_SAMPLER, tex);
    float4 mean_p = mean_i;

    float4 a = tex2D(MEAN_A_SAMPLER, tex);
    
    // b
    return mean_p - a * mean_i;
}

[shader("pixel")]
float4 mainImage(float4 position : SV_Position, float2 tex : TEXCOORD) : SV_Target
{
    float4 mean_a = tex2D(MEAN_A_SAMPLER, tex);
    float4 mean_b = tex2D(MEAN_B_SAMPLER, tex);

    // q = mean_a * I + mean_b
    return mean_a * tex2D(BACKBUFFER, tex) + mean_b;
}

technique GuidedBlur
{
    // construct meanI and meanp (both are the same)
    pass IVerticalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::BackBuffer_gaussianVerticalBlur;
        RenderTarget = MEAN_I_TEX;
    }
    pass IHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::buffer0_gaussianHorizontalBlur;
        RenderTarget = MEAN_I_TEX;
    }

    // construct corrI
    // corrI = mean(I^2)
    pass corrIConstruct
    {
        VertexShader = PostProcessVS;
        PixelShader = squareI;
        RenderTarget = CORR_I_TEX;
    }
    pass corrIVerticalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::buffer1_gaussianVerticalBlur;
        RenderTarget = CORR_I_TEX;
    }
    pass corrIHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::buffer1_gaussianHorizontalBlur;
        RenderTarget = CORR_I_TEX;
    }

    // construct a and b, these will overwrite buffers 1 and 0 respectively
    //
    // b relies on the contents of meanI and meanp however, which means we must preserve buffer 0 
    // until b is constructed, and then overwrite that buffer with b
    pass aConstruct
    {
        VertexShader = PostProcessVS;
        PixelShader = aConstruct;
        RenderTarget = MEAN_A_TEX;
    }
    pass bConstruct
    {
        VertexShader = PostProcessVS;
        PixelShader = bConstruct;
        RenderTarget = MEAN_B_TEX;
    }

    // blur a and b
    pass aVerticalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::buffer1_gaussianVerticalBlur;
        RenderTarget = MEAN_A_TEX;
    }
    pass aHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::buffer1_gaussianHorizontalBlur;
        RenderTarget = MEAN_A_TEX;
    }
    pass bVerticalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::buffer0_gaussianVerticalBlur;
        RenderTarget = MEAN_B_TEX;
    }
    pass bHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::buffer0_gaussianHorizontalBlur;
        RenderTarget = MEAN_B_TEX;
    }

    // final output!
    pass final
    {
        VertexShader = PostProcessVS;
        PixelShader = mainImage;
    }
}