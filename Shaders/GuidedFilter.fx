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

// May the lord have mercy on my soul
texture2D intermediateMeanITex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D intermediateMeanISampler
{
    Texture = intermediateMeanITex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D finalMeanITex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D finalMeanISampler
{
    Texture = intermediateMeanITex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D intermediateCorrITex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D intermediateCorrISampler
{
    Texture = intermediateCorrITex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D intermediateCorrITex2
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D intermediateCorrISampler2
{
    Texture = intermediateCorrITex2;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D finalCorrITex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D finalCorrISampler
{
    Texture = intermediateCorrITex2;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D baseATex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D baseASampler
{
    Texture = baseATex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D intermediateMeanATex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D intermediateMeanASampler
{
    Texture = intermediateMeanATex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D finalMeanATex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D finalMeanASampler
{
    Texture = finalMeanATex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D intermediateMeanBTex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D intermediateMeanBSampler
{
    Texture = intermediateMeanBTex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D intermediateMeanBTex2
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D intermediateMeanBSampler2
{
    Texture = intermediateMeanBTex2;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

texture2D finalMeanBTex
{
    Width = BUFFER_WIDTH * SAMPLING_MULTIPLIER;
    Height = BUFFER_HEIGHT * SAMPLING_MULTIPLIER;
    Format = RGBA8;
};

sampler2D finalMeanBSampler
{
    Texture = finalMeanBTex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
};

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
    float4 intermediateMeanISampler_gaussianHorizontalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianHorizontalPass(intermediateMeanISampler, tex);
    }

    [shader("pixel")]
    float4 intermediateCorrISampler_gaussianVerticalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianVerticalPass(intermediateCorrISampler, tex);
    }

    [shader("pixel")]
    float4 intermediateCorrISampler2_gaussianHorizontalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianHorizontalPass(intermediateCorrISampler2, tex);
    }

    [shader("pixel")]
    float4 baseASampler_gaussianVerticalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianVerticalPass(baseASampler, tex);
    }

    [shader("pixel")]
    float4 intermediateMeanASampler_gaussianHorizontalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianHorizontalPass(intermediateMeanASampler, tex);
    }

    [shader("pixel")]
    float4 intermediateMeanBSampler_gaussianVerticalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianVerticalPass(intermediateMeanBSampler, tex);
    }

    [shader("pixel")]
    float4 intermediateMeanBSampler2_gaussianHorizontalBlur(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
    {
        return gaussianHorizontalPass(intermediateMeanBSampler2, tex);
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
    float4 mean_i = tex2D(finalMeanISampler, tex);
    float4 mean_p = mean_i;
    float4 corr_i = tex2D(finalCorrISampler, tex);
    float4 corr_ip = corr_i;
    
    float4 var_i = corr_i - mean_i * mean_i;
    float4 cov_ip = corr_ip - mean_i * mean_p;

    // a
    return cov_ip / (var_i + pow(fEpsilon, 5.0));
}

[shader("pixel")]
float4 bConstruct(float4 position : SV_Position, float2 tex : TEXCOORD) : SV_Target
{
    float4 mean_i = tex2D(finalMeanISampler, tex);
    float4 mean_p = mean_i;

    float4 a = tex2D(baseASampler, tex);
    
    // b
    return mean_p - a * mean_i;
}

[shader("pixel")]
float4 mainImage(float4 position : SV_Position, float2 tex : TEXCOORD) : SV_Target
{
    float4 mean_a = tex2D(finalMeanASampler, tex);
    float4 mean_b = tex2D(finalMeanBSampler, tex);

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
        RenderTarget = intermediateMeanITex;
    }
    pass IHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::intermediateMeanISampler_gaussianHorizontalBlur;
        RenderTarget = finalMeanITex;
    }

    // construct corrI
    // corrI = mean(I^2)
    pass corrIConstruct
    {
        VertexShader = PostProcessVS;
        PixelShader = squareI;
        RenderTarget = intermediateCorrITex;
    }
    pass corrIVerticalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::intermediateCorrISampler_gaussianVerticalBlur;
        RenderTarget = intermediateCorrITex2;
    }
    pass corrIHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::intermediateCorrISampler2_gaussianHorizontalBlur;
        RenderTarget = finalCorrITex;
    }

    // construct a
    pass aConstruct
    {
        VertexShader = PostProcessVS;
        PixelShader = aConstruct;
        RenderTarget = baseATex;
    }
    pass aVerticalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::baseASampler_gaussianVerticalBlur;
        RenderTarget = intermediateMeanATex;
    }
    pass aHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::intermediateMeanASampler_gaussianHorizontalBlur;
        RenderTarget = finalMeanATex;
    }

    // construct b
    pass bConstruct
    {
        VertexShader = PostProcessVS;
        PixelShader = bConstruct;
        RenderTarget = intermediateMeanBTex;
    }
    pass bVerticalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::intermediateMeanBSampler_gaussianVerticalBlur;
        RenderTarget = intermediateMeanBTex2;
    }
    pass bHorizontalBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = Wrappers::intermediateMeanBSampler2_gaussianHorizontalBlur;
        RenderTarget = finalMeanBTex;
    }

    // final output!
    pass final
    {
        VertexShader = PostProcessVS;
        PixelShader = mainImage;
    }
}