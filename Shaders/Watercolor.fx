#include "ReShade.fxh"
#include "ShaderCommon.fxh"

#ifndef PAPER_TEXTURE_WIDTH
    #define PAPER_TEXTURE_WIDTH 2048
#endif
#ifndef PAPER_TEXTURE_HEIGHT
    #define PAPER_TEXTURE_HEIGHT 2048
#endif

#define PAPER_TEXTURE_SIZE float2(PAPER_TEXTURE_WIDTH, PAPER_TEXTURE_HEIGHT)

#define PAPER_TEXTURE_MIDLEVEL 0.5

#define BACKBUFFER ReShade::BackBuffer

uniform int iColorSpace <
    ui_type = "combo";
    ui_label = "Pigment Color Space";
    ui_items = 
        "OkLab\0"
        "sRGB\0";
> = 0;

uniform float fDensityOffset <
    ui_type = "slider";
    ui_label = "Pigment Density Offset";
    ui_tooltip = "This functions as a brightness slider";
    ui_min = -1.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.0;

uniform float fPaperDensity <
    ui_type = "drag";
    ui_label = "Paper Texture Influence";
    ui_min = 0.0;
    ui_step = 0.01;
> = 0.75;

uniform float2 fDisplacementScaling <
    ui_type = "drag";
    ui_label = "Paper Wobbling Scale";
    ui_step = 0.01;
> = float2(0.3, 0.2);

uniform float fEdgeDensity <
    ui_type = "drag";
    ui_min = 0;
    ui_label = "Edge Darkening Effect";
    ui_step = 0.01;
> = 1.2;

uniform float fEdgeOffset <
    ui_type = "drag";
    ui_min = -1;
    ui_max = 1;
    ui_label = "Edge Pigment Effect Offset";
    ui_step = 0.01;
> = -0.05;

texture2D paperTex < source = "WatercolorCanvas.png"; > {
    Width = PAPER_TEXTURE_WIDTH;
    Height = PAPER_TEXTURE_HEIGHT;
    Format = R8;
};

sampler2D paperSampler
{
	Texture = paperTex;

	AddressU = REPEAT;
	AddressV = REPEAT;
	AddressW = CLAMP;
};

texture2D edgeTex < pooled = true; >
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
};

sampler2D edgeSampler
{
	Texture = edgeTex;
    MagFilter = LINEAR;
	MinFilter = LINEAR;
	MipFilter = LINEAR;
};

float3 pigmentDensityOkLab(float3 color, float density) {
    float new_lightness = color.x * (1.0 - ((1.0 - color.x) * (density - 1.0)));
    return float3(new_lightness, color.yz);
}

float3 pigmentDensityRGB(float3 color, float density) {
    return color * (1.0 - ((1.0 - color) * (density - 1.0)));
}

[shader("pixel")]
float edgeDetectPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
    // A very simple convolution which detects edges from adjacent pixels
    // P = image
    // x, y = pixel indices
    // f(P[x, y]) = |P[x-1, y] - P[x+1, y]| + |P[x, y-1] - P[x, y+1]|

    float3 filtered = abs(
        tex2D(BACKBUFFER, texcoord + float2(-BUFFER_PIXEL_SIZE.x, 0.0)).rgb
        - tex2D(BACKBUFFER, texcoord + float2(BUFFER_PIXEL_SIZE.x, 0.0)).rgb
    ) + abs(
        tex2D(BACKBUFFER, texcoord + float2(0.0, -BUFFER_PIXEL_SIZE.y)).rgb
        - tex2D(BACKBUFFER, texcoord + float2(0.0, BUFFER_PIXEL_SIZE.y)).rgb
    );

    return ((filtered.r + filtered.g + filtered.b) / 3.0);
}

[shader("pixel")]
float3 watercolorPS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    // Here we scale the texture coordinates by the paper texture dimensions,
    // this will prevent stretching of the paper texture
    float2 paperRatio = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / PAPER_TEXTURE_SIZE;
    float paper = tex2D(paperSampler, texcoord * paperRatio);
    
    // displace the texture coordinates by the value of the paper * displacement scaling.
    // displacement is multiplied by 0.01 to make the UI values a bit easier to tweak
    float2 displacedTexcoord = texcoord + (paper - PAPER_TEXTURE_MIDLEVEL) * fDisplacementScaling * 0.01;

    float edges = tex2D(edgeSampler, displacedTexcoord);
    float3 color = tex2D(BACKBUFFER, displacedTexcoord).rgb;

    // Calculate the final result based on chosen color space
    float3 result;
    if (iColorSpace == 0) {
        // OkLab
        float3 oklab_color = Color::linear_srgb_to_oklab(color.rgb);
        float density = 1.0 + ((edges + fEdgeOffset) * fEdgeDensity)
                + (paper - PAPER_TEXTURE_MIDLEVEL) * fPaperDensity
                + fDensityOffset;
        result = Color::oklab_to_linear_srgb(pigmentDensityOkLab(oklab_color, density));
    } else if (iColorSpace == 1) {
        // sRGB
        float density = 1.0 + ((edges + fEdgeOffset) * fEdgeDensity)
            + (paper - PAPER_TEXTURE_MIDLEVEL) * fPaperDensity
            + fDensityOffset;
        result = pigmentDensityRGB(color, density);
    }

    return result;
}

technique Watercolor
<
    ui_tooltip = "Adds a watercolor effect to the image";
>
{
    pass pEdgeDetect {
        VertexShader = PostProcessVS;
        PixelShader = edgeDetectPS;
        RenderTarget = edgeTex;
    }

    pass pWatercolor {
        VertexShader = PostProcessVS;
        PixelShader = watercolorPS;
    }
}
