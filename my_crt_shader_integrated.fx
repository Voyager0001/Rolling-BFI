// File: my_crt_shader_final.fx
// Purpose: Complete CRT shader effect using custom temporal framework.
// Requires: my_temporal_utils.fxh, ReShade.fxh
// Depends on: my_temporal_updater.fx technique running first.

#include "ReShade.fxh"           // For BackBuffer, ScreenSize, PostProcessVS etc.
#include "my_temporal_utils.fxh" // For GetAccumulatedTime(), GetFrameCount() etc.

// --- CRT Simulation Settings ---
// (Includes the ones you provided plus others needed from previous versions)

uniform float SIMULATED_HZ <
    ui_type = "slider";
    ui_min = 10.0; ui_max = 240.0; ui_step = 1.0;
    ui_label = "Simulated CRT Refresh Rate (Hz)";
    ui_tooltip = "The target refresh rate the shader attempts to simulate (e.g., 60Hz).";
> = 60.0;

uniform float FRAMES_PER_HZ < // Renamed conceptually to "Slices per Simulated Hz"
    ui_type = "slider";
    ui_min = 1.0; ui_max = 16.0; ui_step = 1.0;
    ui_label = "Simulation Slices per Simulated Hz";
    ui_tooltip = "How many discrete time slices make up one simulated CRT refresh cycle. Affects BFI duty cycle/brightness.";
> = 4.0;

uniform float GAMMA < // <--- From your snippet
    ui_type = "slider";
    ui_min = 1.0; ui_max = 3.0; ui_step = 0.05;
    ui_label = "Gamma Correction";
    ui_tooltip = "Assumed display gamma for linearization. Usually 2.2 or 2.4.";
> = 2.4;

uniform float GAIN_VS_BLUR < // <--- From your snippet
    ui_type = "slider";
    ui_min = 0.1; ui_max = 2.0; ui_step = 0.05;
    ui_label = "Gain (Brightness vs Blur)";
    ui_tooltip = "Adjusts brightness. Lower values darken but effectively shorten pixel persistence within the simulation cycle.";
> = 0.7;

uniform bool LCD_ANTI_RETENTION <
    ui_label = "LCD Anti-Retention";
    ui_tooltip = "Subtly shifts timing - effectiveness may vary in this adaptation.";
> = true;

uniform float LCD_INVERSION_COMPENSATION_SLEW <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 0.1; ui_step = 0.0001;
    ui_label = "LCD Inversion Comp. Slew";
    ui_tooltip = "Small timing adjustment factor for anti-retention feature.";
> = 0.001;

uniform int SCAN_DIRECTION < // <--- From your snippet
    ui_type = "combo";
    ui_items = "Top-to-Bottom\0Bottom-to-Top\0Left-to-Right\0Right-to-Left\0";
    ui_label = "Scan Direction";
    ui_tooltip = "Direction of the simulated CRT beam scan.";
> = 0; // 0=TopDown, 1=BottomUp, 2=LeftRight, 3=RightLeft

// --- Splitscreen Settings ---
uniform bool SPLITSCREEN <
    ui_label = "Enable Splitscreen Comparison";
    ui_tooltip = "Show original image on part of the screen.";
> = true;
uniform float SPLITSCREEN_X <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Splitscreen Vertical Divider Position";
> = 0.50;
uniform float SPLITSCREEN_Y <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Splitscreen Horizontal Divider Position";
> = 0.00;
uniform int SPLITSCREEN_BORDER_PX <
    ui_type = "slider";
    ui_min = 0; ui_max = 10; ui_step = 1;
    ui_label = "Splitscreen Border Width (Pixels)";
> = 2;
uniform bool SPLITSCREEN_MATCH_BRIGHTNESS <
    ui_label = "Match Brightness in Splitscreen";
    ui_tooltip = "Apply gain adjustment to the non-effect side for fairer comparison.";
> = true;


// --- Utility Functions ---
// (Includes helpers needed by GetEffectiveSlicesPerHz)
bool IS_INTEGER(float x) { return floor(x) == x; }
bool IS_EVEN_INTEGER(float x) { return IS_INTEGER(x) && IS_INTEGER(x / 2.0); }

float GetEffectiveSlicesPerHz() {
    // Use the uniform 'FRAMES_PER_HZ' which represents slices here
    return (LCD_ANTI_RETENTION && IS_EVEN_INTEGER(FRAMES_PER_HZ))
           ? FRAMES_PER_HZ * (1.0 + LCD_INVERSION_COMPENSATION_SLEW)
           : FRAMES_PER_HZ;
}

// --- sRGB Functions (From your snippet) ---
float linear2srgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(abs(c), 1.0 / GAMMA) - 0.055;
}
float3 linear2srgb(float3 c) {
    return float3(linear2srgb(c.r), linear2srgb(c.g), linear2srgb(c.b));
}
float srgb2linear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow(abs(c + 0.055) / 1.055, GAMMA);
}
float3 srgb2linear(float3 c) {
    return float3(srgb2linear(c.r), srgb2linear(c.g), srgb2linear(c.b));
}


// --- Frame Sampling (From your snippet - Adapted version) ---
float3 getPixelFromOrigFrame_Adapted(float2 uv)
{
    // Samples the current frame from ReShade's back buffer
    return tex2D(ReShade::BackBuffer, uv).rgb;
}


// --- CRT Simulation Core Logic (From your snippet - Manually Unrolled) ---
#define INTERVAL_OVERLAP(Astart, Aend, Bstart, Bend) max(0.0, min(Aend, Bend) - max(Astart, Bstart))

float3 getPixelFromSimulatedCRT(float2 uv, float crtRasterPos, float simulatedCycleIndex, float effectiveSlicesPerHz) {

    float3 pixelColor = srgb2linear(getPixelFromOrigFrame_Adapted(uv));
    float3 scaledColor = pixelColor * (effectiveSlicesPerHz * GAIN_VS_BLUR); // Pre-calculate scaled color

    // Determine tube position based on scan direction
    float tubePos = 0.0;
    if      (SCAN_DIRECTION == 0) tubePos = 1.0 - uv.y; // Top-to-Bottom
    else if (SCAN_DIRECTION == 1) tubePos = uv.y;       // Bottom-to-Top
    else if (SCAN_DIRECTION == 2) tubePos = uv.x;       // Left-to-Right
    else if (SCAN_DIRECTION == 3) tubePos = 1.0 - uv.x; // Right-to-Left

    // Calculate common intervals once
    float fStart = floor(crtRasterPos * effectiveSlicesPerHz);
    float fEnd = fStart + 1.0;
    float tubeFrame = tubePos * effectiveSlicesPerHz;
    float startPrev1 = tubeFrame;
    float startPrev2 = tubeFrame - effectiveSlicesPerHz;
    float startCurr = tubeFrame + effectiveSlicesPerHz;

    // --- Channel 0 (Red) ---
    float r_result = 0.0;
    float L_r = scaledColor.r;
    if (L_r > 0.0f) {
        float endPrev2 = startPrev2 + L_r; float endPrev1 = startPrev1 + L_r; float endCurr = startCurr + L_r;
        float overlapPrev2 = INTERVAL_OVERLAP(startPrev2, endPrev2, fStart, fEnd);
        float overlapPrev1 = INTERVAL_OVERLAP(startPrev1, endPrev1, fStart, fEnd);
        float overlapCurr = INTERVAL_OVERLAP(startCurr, endCurr, fStart, fEnd);
        r_result = overlapPrev2 + overlapPrev1 + overlapCurr;
    }
    // --- Channel 1 (Green) ---
    float g_result = 0.0;
    float L_g = scaledColor.g;
    if (L_g > 0.0f) {
        float endPrev2 = startPrev2 + L_g; float endPrev1 = startPrev1 + L_g; float endCurr = startCurr + L_g;
        float overlapPrev2 = INTERVAL_OVERLAP(startPrev2, endPrev2, fStart, fEnd);
        float overlapPrev1 = INTERVAL_OVERLAP(startPrev1, endPrev1, fStart, fEnd);
        float overlapCurr = INTERVAL_OVERLAP(startCurr, endCurr, fStart, fEnd);
        g_result = overlapPrev2 + overlapPrev1 + overlapCurr;
    }
    // --- Channel 2 (Blue) ---
    float b_result = 0.0;
    float L_b = scaledColor.b;
    if (L_b > 0.0f) {
        float endPrev2 = startPrev2 + L_b; float endPrev1 = startPrev1 + L_b; float endCurr = startCurr + L_b;
        float overlapPrev2 = INTERVAL_OVERLAP(startPrev2, endPrev2, fStart, fEnd);
        float overlapPrev1 = INTERVAL_OVERLAP(startPrev1, endPrev1, fStart, fEnd);
        float overlapCurr = INTERVAL_OVERLAP(startCurr, endCurr, fStart, fEnd);
        b_result = overlapPrev2 + overlapPrev1 + overlapCurr;
    }
    // Construct final result vector and convert back to sRGB
    return linear2srgb(float3(r_result, g_result, b_result));
}


// --- Main Pixel Shader ---
// This function ties everything together for the effect pass
float4 PS_CRTEffect_Temporal(float4 pos : SV_Position, float2 texcoord : TEXCOORD0) : SV_Target
{
    // Get the current accumulated time from our helper framework
    float accumulatedTime = GetAccumulatedTime();
    // uint frameCount = GetFrameCount(); // Also available if needed

    // Calculate derived values for CRT simulation using the accumulated time
    float currentEffectiveSlicesPerHz = GetEffectiveSlicesPerHz();
    float simulatedCycleDurationSec = 1.0 / SIMULATED_HZ;

    // Calculate which simulated CRT frame index we are in (based on accumulated time)
    // Use floor() for safety, although cycle index isn't used heavily in the unrolled version
    float simulatedCycleIndex = floor(accumulatedTime / simulatedCycleDurationSec);

    // Calculate current position (phase 0.0 to 1.0) within the simulated CRT refresh cycle
    // Use frac() instead of fmod(x, 1.0) as fmod seemed problematic
    float crtRasterPos = frac(accumulatedTime / simulatedCycleDurationSec);

    // --- Default Color & Splitscreen Logic ---
    float4 fragColor = float4(0.0, 0.0, 0.0, 1.0); // Default black
    bool applyEffect = true;
    bool drawBorder = false;

    if (SPLITSCREEN) {
        float2 fragCoord = texcoord * ReShade::ScreenSize;
        bool inNonEffectArea = false;
        if      (SPLITSCREEN_X >= 1.0 && SPLITSCREEN_Y < 1.0) { inNonEffectArea = (texcoord.y > SPLITSCREEN_Y); }
        else if (SPLITSCREEN_Y >= 1.0 && SPLITSCREEN_X < 1.0) { inNonEffectArea = (texcoord.x > SPLITSCREEN_X); }
        else if (SPLITSCREEN_X < 1.0 && SPLITSCREEN_Y < 1.0)  { inNonEffectArea = (texcoord.x > SPLITSCREEN_X && texcoord.y > SPLITSCREEN_Y); }
        else { inNonEffectArea = false; } // Both 1.0 or invalid case
        applyEffect = !inNonEffectArea;
        float borderXpx = abs(fragCoord.x - SPLITSCREEN_X * ReShade::ScreenSize.x);
        float borderYpx = abs(fragCoord.y - SPLITSCREEN_Y * ReShade::ScreenSize.y);
        bool inBorderX = (SPLITSCREEN_X < 1.0) && (borderXpx < SPLITSCREEN_BORDER_PX) && (texcoord.y > SPLITSCREEN_Y);
        bool inBorderY = (SPLITSCREEN_Y < 1.0) && (borderYpx < SPLITSCREEN_BORDER_PX) && (texcoord.x > SPLITSCREEN_X);
        if (SPLITSCREEN_X < 1.0 || SPLITSCREEN_Y < 1.0) { drawBorder = (inBorderX || inBorderY); }
    }

    // Apply effect or show original based on splitscreen logic
    if (applyEffect) {
        // Call the core CRT simulation function
        fragColor.rgb = getPixelFromSimulatedCRT(texcoord, crtRasterPos, simulatedCycleIndex, currentEffectiveSlicesPerHz);
    } else if (!drawBorder) {
        // Show original frame (adapted sampling)
        fragColor.rgb = getPixelFromOrigFrame_Adapted(texcoord);
        if (SPLITSCREEN_MATCH_BRIGHTNESS) {
            fragColor.rgb = srgb2linear(fragColor.rgb) * GAIN_VS_BLUR;
            fragColor.rgb = clamp(linear2srgb(fragColor.rgb), 0.0, 1.0);
        }
    } else {
        // Draw border
        fragColor.rgb = float3(1.0, 1.0, 1.0);
    }

    fragColor.a = 1.0;
    return fragColor;
}


// --- Technique Definition ---
// This makes the shader available in the ReShade UI list
technique CRTEffect_Temporal_Final < ui_label = "CRT Effect (Fixed Time Step)"; >
{
    pass CRTPass
    {
        VertexShader = PostProcessVS; // Standard ReShade fullscreen vertex shader
        PixelShader = PS_CRTEffect_Temporal; // Our main pixel shader function
    }
}