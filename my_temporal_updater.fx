// File: my_temporal_updater.fx
// Purpose: Updates the persistent frame count and accumulated time using Ping-Pong Buffering.
// Reads from Texture A, Writes to Texture B. Assumes fixed FPS.
// Requires: my_temporal_utils.fxh, ReShade.fxh
// This technique MUST run *before* any effect that reads the temporal data from B.

#include "ReShade.fxh"
#include "my_temporal_utils.fxh" // Include our definitions (now has A/B textures/samplers)

// Define the fixed delta time based on the assumed FPS
#define FIXED_FPS 165.0
#define FIXED_DELTA_TIME (1.0 / FIXED_FPS)

// --- Pixel Shader to Update State ---
// Reads old state from A, calculates new state, outputs to B.
float4 PS_UpdateTemporalState_PingPong(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    // Read the previously stored values from Texture A using its sampler
    float oldTime = tex2Dlod(sTemporalStorageA, float4(0.5, 0.5, 0.0, 0.0)).r;
    float oldFrameCountFloat = tex2Dlod(sTemporalStorageA, float4(0.5, 0.5, 0.0, 0.0)).g;

    // Calculate the new values
    float newTime = oldTime + FIXED_DELTA_TIME;
    float newFrameCountFloat = oldFrameCountFloat + 1.0;

    // Output the new values to be stored back into Texture B
    return float4(newTime, newFrameCountFloat, 0.0, 1.0);
}

// --- Simple Blit Pixel Shader to copy Texture B --- <<< MOVED DEFINITION UP
float4 BlitB(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    // Read directly from Texture B (using its sampler)
    // Use standard tex2D here as we're just copying the whole texture
    return tex2D(sTemporalStorageB, uv);
    // Using tex2Dlod might also work: return tex2Dlod(sTemporalStorageB, float4(uv, 0.0, 0.0));
}


// --- Technique ---
technique TemporalUpdater < ui_label = "Helper: Fixed Step Temporal Updater (PingPong)"; ui_tooltip = "Updates time/frame count (Reads A, Writes B). MUST run BEFORE effects reading B."; >
{
    pass UpdatePass_WriteToB
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_UpdateTemporalState_PingPong;
        RenderTarget0 = TemporalStorageB; // <<< Write to Texture B
    }

    // Pass to copy B back to A for the *next* frame's read
    pass CopyBtoA
    {
         VertexShader = PostProcessVS;
         PixelShader = BlitB; // <<< Now defined before use (Line 46 approx)
         RenderTarget0 = TemporalStorageA; // <<< Write to Texture A // Line 47 approx
    }
}