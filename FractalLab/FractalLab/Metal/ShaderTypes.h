#pragma once

// Shared between Metal shaders and Swift via bridging header.
// All fields use 32-bit types to avoid platform alignment surprises.

typedef struct {
    // View position
    float centerX;          // Fractal-space X of screen centre
    float centerY;          // Fractal-space Y of screen centre
    float zoom;             // Pixels per fractal unit (scaled by min dimension)
    float colorOffset;      // Palette rotation [0, 1)

    // Julia parameter
    float juliaCX;
    float juliaCY;

    // Colour control
    float colorCycleLength; // Smooth-iter divisor (controls colour density)
    float aspectRatio;      // viewWidth / viewHeight

    // Integer config
    int   maxIterations;
    int   fractalType;      // 0 = Mandelbrot, 1 = Julia
    int   paletteIndex;     // 0–7

    // Viewport
    float viewWidth;
    float viewHeight;

    int   padding;          // Keeps struct size a multiple of 16 bytes
} FractalParams;
