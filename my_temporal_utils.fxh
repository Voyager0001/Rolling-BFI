// File: my_temporal_utils.fxh
// Purpose: Defines persistent storage (A/B) and access functions for frame count and accumulated time.
// Uses tex2Dlod for reading.

#pragma once // Prevent multiple includes

// --- Texture Definitions (Ping-Pong) ---
texture TemporalStorageA < Semantic = "TemporalStorageA"; > // Read by Updater
{ Width = 1; Height = 1; Format = RG32F; };

texture TemporalStorageB < Semantic = "TemporalStorageB"; > // Written by Updater, Read by Main Effect
{ Width = 1; Height = 1; Format = RG32F; };

// --- Sampler Definitions (Ping-Pong) ---
sampler sTemporalStorageA < Semantic = "TemporalStorageSamplerA"; >
{ Texture = TemporalStorageA; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };

sampler sTemporalStorageB < Semantic = "TemporalStorageSamplerB"; >
{ Texture = TemporalStorageB; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };

// --- Access Functions ---
// These will be called by the *main effect* shader, so they read from Texture B
// where the updater writes the latest result.

// Gets the accumulated time (in seconds, assuming fixed delta time updates)
float GetAccumulatedTime()
{
    // Read from Texture B
    return tex2Dlod(sTemporalStorageB, float4(0.5, 0.5, 0.0, 0.0)).r;
}

// Gets the frame count (stored as a float)
float GetFrameCountFloat()
{
    // Read from Texture B
    return tex2Dlod(sTemporalStorageB, float4(0.5, 0.5, 0.0, 0.0)).g;
}

// Optional: Helper to get frame count as an integer
uint GetFrameCount()
{
    return (uint)floor(GetFrameCountFloat());
}