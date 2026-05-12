enum ShaderSource {
    static let asciiOverlay = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float2 viewportSize;
        float2 sourceSize;
        float cellSize;
        int styleMode;
        int renderMode;
        int luminanceBuckets;
        float opacity;
        float brightness;
        float contrast;
        float gamma;
        float edgeStrength;
        float time;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };

        float2 uvs[3] = {
            float2(0.0, 1.0),
            float2(2.0, 1.0),
            float2(0.0, -1.0)
        };

        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    constexpr sampler linearSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float luminance(float3 color) {
        return dot(color, float3(0.2126, 0.7152, 0.0722));
    }

    float rect(float2 p, float2 minP, float2 maxP) {
        return step(minP.x, p.x) * step(p.x, maxP.x) * step(minP.y, p.y) * step(p.y, maxP.y);
    }

    float glyphMask(float bucket, float2 local) {
        float dotBottom = 1.0 - smoothstep(0.09, 0.13, distance(local, float2(0.5, 0.76)));
        float dotTop = 1.0 - smoothstep(0.08, 0.12, distance(local, float2(0.5, 0.38)));
        float ringDistance = distance(local, float2(0.5, 0.5));
        float outerRing = 1.0 - smoothstep(0.41, 0.46, ringDistance);
        float innerRing = 1.0 - smoothstep(0.24, 0.29, ringDistance);
        float ring = clamp(outerRing - innerRing, 0.0, 1.0);
        float leftStroke = rect(local, float2(0.00, 0.18), float2(0.28, 0.84));
        float topStroke = rect(local, float2(0.18, 0.00), float2(0.78, 0.25));
        float midStroke = rect(local, float2(0.18, 0.43), float2(0.75, 0.56));
        float rightUpperStroke = rect(local, float2(0.66, 0.20), float2(0.84, 0.54));
        float rightStroke = rect(local, float2(0.70, 0.18), float2(0.87, 0.84));
        float verticalMid = rect(local, float2(0.42, 0.00), float2(0.58, 1.00));
        float horizontalMid = rect(local, float2(0.00, 0.42), float2(1.00, 0.58));

        if (bucket < 1.0) return 0.0;
        if (bucket < 2.0) return dotBottom;
        if (bucket < 3.0) return max(dotTop, dotBottom);
        if (bucket < 4.0) return ring * (1.0 - step(0.58, local.x));
        if (bucket < 5.0) return ring;
        if (bucket < 6.0) return max(max(leftStroke, topStroke), max(midStroke, rightUpperStroke));
        if (bucket < 7.0) return max(ring, max(leftStroke * 0.8, rightStroke * 0.8));
        if (bucket < 8.0) return max(max(topStroke, rightUpperStroke), max(midStroke, dotBottom));
        if (bucket < 9.0) return max(max(ring, dotBottom * 0.9), max(midStroke * 0.7, rightUpperStroke * 0.65));
        return max(max(verticalMid, horizontalMid), max(leftStroke, rightStroke));
    }

    fragment float4 fragment_ascii(VertexOut in [[stage_in]],
                                  texture2d<float> source [[texture(0)]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
        float2 uv = clamp(in.uv, float2(0.0), float2(1.0));
        float2 gridSize = max(float2(1.0), floor(uniforms.viewportSize / max(1.0, uniforms.cellSize)));
        float2 cell = uv * gridSize;
        float2 local = fract(cell);
        float2 cellUv = (floor(cell) + float2(0.5)) / gridSize;

        float3 cellColor = source.sample(linearSampler, cellUv).rgb;
        float toneGamma = clamp(uniforms.gamma, 0.50, 2.0);
        cellColor = clamp(((cellColor + uniforms.brightness) - 0.5) * clamp(uniforms.contrast, 0.50, 2.0) + 0.5, float3(0.0), float3(1.0));
        cellColor = pow(cellColor, float3(1.0 / toneGamma));
        float lum = luminance(cellColor);
        float exposed = pow(clamp((lum * 1.35) + 0.08, 0.0, 0.999), 0.72);
        float bucket = floor(exposed * float(uniforms.luminanceBuckets));
        float level = bucket / max(1.0, float(uniforms.luminanceBuckets - 1));
        float glyphBucket = floor((bucket / float(uniforms.luminanceBuckets)) * 10.0);

        float2 texel = 1.0 / gridSize;
        float lumLeft = luminance(source.sample(linearSampler, clamp(cellUv + float2(-texel.x, 0.0), float2(0.0), float2(1.0))).rgb);
        float lumRight = luminance(source.sample(linearSampler, clamp(cellUv + float2(texel.x, 0.0), float2(0.0), float2(1.0))).rgb);
        float lumTop = luminance(source.sample(linearSampler, clamp(cellUv + float2(0.0, -texel.y), float2(0.0), float2(1.0))).rgb);
        float lumBottom = luminance(source.sample(linearSampler, clamp(cellUv + float2(0.0, texel.y), float2(0.0), float2(1.0))).rgb);
        float gradientX = lumRight - lumLeft;
        float gradientY = lumBottom - lumTop;
        float gradientMagnitude = length(float2(gradientX, gradientY));
        float absX = abs(gradientX);
        float absY = abs(gradientY);
        float majorGradient = max(absX, absY);
        float minorGradient = min(absX, absY);
        float gradientSum = max(0.0001, absX + absY);
        float axisDominance = majorGradient / gradientSum;
        float axisMargin = (majorGradient - minorGradient) / gradientSum;
        float diagonalBalance = 1.0 - axisMargin;
        float directionCoherence = max(
            smoothstep(0.58, 0.78, axisDominance),
            smoothstep(0.42, 0.62, diagonalBalance)
        );
        float rawEdgeStrength = smoothstep(0.14, 0.38, gradientMagnitude) * directionCoherence;
        float edgeStrength = rawEdgeStrength * clamp(uniforms.edgeStrength, 0.0, 2.0);

        float edgeHorizontal = rect(local, float2(0.12, 0.70), float2(0.88, 0.86));
        float edgeVertical = rect(local, float2(0.42, 0.12), float2(0.58, 0.88));
        float edgeSlash = 1.0 - smoothstep(0.06, 0.13, abs((local.x + local.y) - 1.0));
        edgeSlash *= rect(local, float2(0.08), float2(0.92));
        float edgeBackslash = 1.0 - smoothstep(0.06, 0.13, abs(local.x - local.y));
        edgeBackslash *= rect(local, float2(0.08), float2(0.92));

        float edgeGlyph = edgeHorizontal;
        float diagonalEdge = 0.0;
        if (absX > absY * 1.40) edgeGlyph = edgeVertical;
        else if (absY > absX * 1.40) edgeGlyph = edgeHorizontal;
        else {
            diagonalEdge = 1.0;
            if (gradientX * gradientY > 0.0) edgeGlyph = edgeSlash;
            else edgeGlyph = edgeBackslash;
        }

        float glyph = glyphMask(glyphBucket, local);
        float aaGlyph = smoothstep(0.03, 0.90, glyph);
        float glyphStrength = mix(0.20, 0.84, smoothstep(2.0, 5.0, uniforms.cellSize));
        float asciiMask = mix(1.0, aaGlyph, glyphStrength);
        float edgeStrokeMask = smoothstep(0.12, 0.84, edgeGlyph);
        float coherentEdgeStrength = edgeStrength * mix(0.90, 1.16, directionCoherence);
        float edgeReplaceWeight = smoothstep(
            mix(0.58, 0.68, diagonalEdge),
            mix(1.05, 1.16, diagonalEdge),
            coherentEdgeStrength
        );
        asciiMask = mix(asciiMask, edgeStrokeMask, edgeReplaceWeight);
        float edgeMask = smoothstep(0.20, 0.88, edgeGlyph * coherentEdgeStrength);
        float inkAmount = clamp(0.35 + (max(level, coherentEdgeStrength) * 0.65), 0.0, 1.0);
        float asciiGridCompensation = smoothstep(3.0, 8.0, uniforms.cellSize);
        float asciiEnergyLift = (0.05 + (0.10 * level)) * asciiGridCompensation;
        float asciiNormalizedMask = clamp(
            asciiMask + ((1.0 - asciiMask) * asciiEnergyLift),
            0.0,
            1.0
        );
        float styleMask = uniforms.renderMode == 0 ? asciiNormalizedMask : asciiMask;

        float3 posterColor = floor((pow(clamp(cellColor, float3(0.0), float3(1.0)), float3(0.9)) * 9.0) + 0.5) / 9.0;
        float grayValue = luminance(posterColor);
        float3 gray = float3(grayValue);
        float2 centeredUv = uv - float2(0.5);
        float vignette = smoothstep(0.78, 0.18, dot(centeredUv, centeredUv));

        float3 classicShadow = float3(0.12, 0.065, 0.018);
        float3 classicAmber = float3(1.0, 0.72, 0.18);
        float3 classicColor = mix(classicShadow, mix(classicShadow, classicAmber, inkAmount), styleMask);

        float3 darkShadow = float3(0.030, 0.014, 0.003);
        float3 darkAmber = float3(0.78, 0.36, 0.055);
        float3 darkColor = mix(darkShadow, mix(darkShadow, darkAmber, inkAmount), styleMask);
        darkColor = mix(darkColor, darkColor + float3(0.12, 0.045, 0.006), edgeMask * 0.45);

        float3 crtPalette = mix(gray, posterColor, 0.62);
        crtPalette = pow(clamp(crtPalette * 1.12, float3(0.0), float3(1.0)), float3(0.86));
        crtPalette *= mix(float3(0.80, 0.96, 1.16), float3(1.20, 1.02, 0.80), level);
        float3 crtColor = mix(float3(0.018, 0.030, 0.045), mix(float3(0.018, 0.030, 0.045), crtPalette, inkAmount), styleMask);
        crtColor *= mix(0.74, 1.0, vignette);

        float hash = fract(sin(dot(floor(cell), float2(127.1, 311.7))) * 43758.5453);
        float3 hybridEdge = mix(float3(1.0, 0.78, 0.42), float3(1.0, 0.38, 0.82), step(0.5, hash));
        float3 hybridBase = mix(gray, posterColor, 0.78) * float3(0.96, 1.02, 1.08);
        float3 hybridColor = mix(float3(0.018, 0.022, 0.030), mix(float3(0.018, 0.022, 0.030), hybridBase, inkAmount), styleMask);
        hybridColor = mix(hybridColor, hybridEdge, edgeMask * 0.55);

        float3 invertColor = mix(float3(0.02, 0.02, 0.025), pow(float3(1.0) - posterColor, float3(0.92)), inkAmount);
        invertColor = mix(float3(0.02, 0.02, 0.025), invertColor, styleMask);

        float3 cyberBase = mix(gray, posterColor, 0.52) * float3(0.65, 0.92, 1.28);
        float3 cyberGlow = mix(float3(1.0, 0.12, 0.72), float3(0.72, 0.18, 1.0), step(0.46, hash));
        float3 cyberColor = mix(float3(0.025, 0.010, 0.050), mix(float3(0.025, 0.010, 0.050), cyberBase, inkAmount), styleMask);
        cyberColor = mix(cyberColor, cyberGlow, edgeMask * 0.65);
        cyberColor *= mix(0.76, 1.0, vignette);

        float3 phosphorShadow = float3(0.002, 0.020, 0.010);
        float3 phosphorInk = mix(float3(0.12, 0.42, 0.18), float3(0.72, 1.00, 0.50), level);
        float scanline = 0.88 + (0.12 * sin((uv.y * uniforms.viewportSize.y * 3.14159) + uniforms.time * 8.0));
        float3 phosphorColor = mix(phosphorShadow, mix(phosphorShadow, phosphorInk, inkAmount), styleMask);
        phosphorColor = mix(phosphorColor, phosphorColor + float3(0.10, 0.28, 0.08), edgeMask * 0.45);
        phosphorColor *= scanline * mix(0.76, 1.0, vignette);

        float3 paperBase = float3(0.94, 0.91, 0.82);
        float3 paperFiber = paperBase + ((hash - 0.5) * float3(0.035, 0.030, 0.018));
        float3 inkTone = mix(float3(0.30, 0.22, 0.14), float3(0.035, 0.030, 0.024), inkAmount);
        float3 paperColor = mix(paperFiber, inkTone, clamp(styleMask * inkAmount, 0.0, 1.0));
        paperColor = mix(paperColor, float3(0.08, 0.055, 0.030), edgeMask * 0.70);

        float3 blueprintBase = float3(0.012, 0.060, 0.140);
        float3 blueprintInk = mix(float3(0.20, 0.52, 0.92), float3(0.86, 0.96, 1.00), inkAmount);
        float blueprintGrid = max(
            1.0 - smoothstep(0.015, 0.045, min(local.x, 1.0 - local.x)),
            1.0 - smoothstep(0.015, 0.045, min(local.y, 1.0 - local.y))
        );
        float3 blueprintColor = mix(blueprintBase, blueprintInk, styleMask);
        blueprintColor = mix(blueprintColor, float3(0.45, 0.76, 1.0), blueprintGrid * 0.18);
        blueprintColor = mix(blueprintColor, float3(1.0, 0.95, 0.65), edgeMask * 0.42);

        float3 moonBase = float3(0.012, 0.014, 0.018);
        float3 moonInk = mix(float3(0.18, 0.22, 0.28), float3(0.86, 0.92, 1.0), inkAmount);
        float3 moonColor = mix(moonBase, moonInk, styleMask);
        moonColor = mix(moonColor, float3(0.62, 0.82, 1.0), edgeMask * 0.48);
        moonColor *= mix(0.70, 1.0, vignette);

        float3 thermalCold = float3(0.020, 0.020, 0.070);
        float3 thermalMid = mix(float3(0.05, 0.26, 0.75), float3(0.95, 0.36, 0.10), smoothstep(0.20, 0.78, level));
        float3 thermalHot = mix(thermalMid, float3(1.0, 0.92, 0.30), smoothstep(0.78, 1.0, level));
        float3 thermalColor = mix(thermalCold, thermalHot, styleMask * inkAmount);
        thermalColor = mix(thermalColor, float3(0.05, 1.0, 0.82), edgeMask * 0.62);

        float3 styledColor = classicColor;
        if (uniforms.styleMode == 1) styledColor = crtColor;
        else if (uniforms.styleMode == 2) styledColor = hybridColor;
        else if (uniforms.styleMode == 3) styledColor = invertColor;
        else if (uniforms.styleMode == 4) styledColor = cyberColor;
        else if (uniforms.styleMode == 5) styledColor = darkColor;
        else if (uniforms.styleMode == 6) styledColor = phosphorColor;
        else if (uniforms.styleMode == 7) styledColor = paperColor;
        else if (uniforms.styleMode == 8) styledColor = blueprintColor;
        else if (uniforms.styleMode == 9) styledColor = moonColor;
        else if (uniforms.styleMode == 10) styledColor = thermalColor;

        if (uniforms.renderMode == 1) {
            float3 blockBase = floor(clamp(cellColor, float3(0.0), float3(1.0)) * 5.0 + 0.5) / 5.0;
            float blockLum = luminance(blockBase);
            float3 blockColor = mix(blockBase, posterColor, 0.35);

            if (uniforms.styleMode == 0 || uniforms.styleMode == 5) {
                float3 amber = mix(float3(0.16, 0.08, 0.02), float3(1.0, 0.66, 0.14), blockLum);
                blockColor = mix(blockColor, amber, uniforms.styleMode == 0 ? 0.50 : 0.70);
            } else if (uniforms.styleMode == 1 || uniforms.styleMode == 6) {
                float3 phosphor = mix(float3(0.02, 0.10, 0.05), float3(0.52, 1.0, 0.36), blockLum);
                blockColor = mix(blockColor, phosphor, 0.58);
            } else if (uniforms.styleMode == 3) {
                blockColor = floor((float3(1.0) - blockBase) * 5.0 + 0.5) / 5.0;
            } else if (uniforms.styleMode == 4) {
                blockColor = mix(blockColor * float3(0.55, 0.90, 1.18), float3(1.0, 0.12, 0.72), edgeMask * 0.45);
            } else if (uniforms.styleMode == 7) {
                blockColor = mix(float3(0.90, 0.84, 0.68), float3(0.20, 0.14, 0.09), blockLum);
            } else if (uniforms.styleMode == 8) {
                blockColor = mix(float3(0.03, 0.16, 0.34), float3(0.60, 0.88, 1.0), blockLum);
            } else if (uniforms.styleMode == 9) {
                blockColor = mix(float3(0.04, 0.05, 0.08), float3(0.72, 0.84, 1.0), blockLum);
            } else if (uniforms.styleMode == 10) {
                blockColor = thermalHot;
            }

            float leftBevel = 1.0 - smoothstep(0.06, 0.18, local.x);
            float topBevel = 1.0 - smoothstep(0.06, 0.18, local.y);
            float rightShade = smoothstep(0.74, 0.96, local.x);
            float bottomShade = smoothstep(0.74, 0.96, local.y);
            float cellBorder = max(
                1.0 - smoothstep(0.015, 0.055, min(local.x, 1.0 - local.x)),
                1.0 - smoothstep(0.015, 0.055, min(local.y, 1.0 - local.y))
            );
            float pixelNoise = (hash - 0.5) * 0.055;
            float highlight = max(leftBevel, topBevel) * 0.14;
            float shade = max(rightShade, bottomShade) * 0.18;
            blockColor = blockColor + highlight - shade + pixelNoise;
            blockColor = mix(blockColor, blockColor * 0.46, cellBorder * 0.42);
            blockColor = mix(blockColor, blockColor * 0.34, edgeMask * clamp(uniforms.edgeStrength, 0.0, 2.0) * 0.34);
            float blockGridCompensation = smoothstep(3.0, 8.0, uniforms.cellSize);
            float blockLift = (0.04 + (0.08 * blockLum)) * blockGridCompensation;
            blockColor += float3(blockLift);
            styledColor = clamp(blockColor, float3(0.0), float3(1.0));
        }

        if (uniforms.renderMode == 2) {
            float radius = mix(0.07, 0.46, smoothstep(0.02, 0.98, level));
            float dotMask = 1.0 - smoothstep(radius, radius + 0.055, distance(local, float2(0.5)));
            float inkDot = max(dotMask, edgeMask * clamp(uniforms.edgeStrength, 0.0, 2.0) * 0.72);
            float halftoneGridCompensation = smoothstep(3.0, 8.0, uniforms.cellSize);
            float halftoneLift = (0.05 + (0.08 * level)) * halftoneGridCompensation;
            float halftoneMask = clamp(inkDot + ((1.0 - inkDot) * halftoneLift), 0.0, 1.0);
            float ring = smoothstep(radius + 0.07, radius + 0.01, distance(local, float2(0.5))) *
                         smoothstep(radius - 0.11, radius - 0.02, distance(local, float2(0.5)));
            float printTexture = (hash - 0.5) * 0.045;
            float3 papered = styledColor * (0.20 + printTexture);
            float3 inked = clamp(styledColor * (1.04 + (ring * 0.12)), float3(0.0), float3(1.0));
            styledColor = mix(papered, inked, halftoneMask);
        }

        if (uniforms.renderMode == 3) {
            float pixelColumn = floor(local.x * 3.0);
            float redBar = 1.0 - smoothstep(0.24, 0.34, abs(local.x - 0.17));
            float greenBar = 1.0 - smoothstep(0.24, 0.34, abs(local.x - 0.50));
            float blueBar = 1.0 - smoothstep(0.24, 0.34, abs(local.x - 0.83));
            float aperture = max(max(redBar, greenBar), blueBar);
            float3 subpixel = float3(redBar, greenBar, blueBar);
            float scan = 0.70 + (0.30 * sin((uv.y * uniforms.viewportSize.y * 3.14159) + uniforms.time * 7.0));
            float phosphor = 0.82 + (0.18 * sin((floor(cell.x) + floor(cell.y) + uniforms.time * 10.0) * 0.55));
            float3 crtBase = styledColor * (0.28 + (0.72 * subpixel));
            crtBase *= scan * phosphor * mix(0.72, 1.0, vignette);
            crtBase = mix(crtBase * 0.42, crtBase, aperture);
            crtBase += styledColor * edgeMask * clamp(uniforms.edgeStrength, 0.0, 2.0) * 0.18;
            float crtGridCompensation = smoothstep(3.0, 8.0, uniforms.cellSize);
            float crtLift = (0.04 + (0.07 * level)) * crtGridCompensation;
            crtBase += styledColor * crtLift;
            styledColor = clamp(crtBase, float3(0.0), float3(1.0));
        }

        if (uniforms.renderMode == 4) {
            float2 shard = abs(local - float2(0.5));
            float diamond = 1.0 - smoothstep(0.36, 0.58, shard.x + shard.y);
            float tileEdge = smoothstep(0.44, 0.56, shard.x + shard.y);
            float3 mosaicColor = floor(clamp(styledColor, float3(0.0), float3(1.0)) * 6.0 + 0.5) / 6.0;
            float facetLight = (0.10 * (1.0 - local.y)) + ((hash - 0.5) * 0.055);
            mosaicColor += facetLight;
            mosaicColor = mix(mosaicColor * 0.48, mosaicColor, diamond);
            mosaicColor = mix(mosaicColor, mosaicColor * 0.36, tileEdge * 0.28);
            mosaicColor = mix(mosaicColor, styledColor * 1.18, edgeMask * clamp(uniforms.edgeStrength, 0.0, 2.0) * 0.30);
            float mosaicGridCompensation = smoothstep(3.0, 8.0, uniforms.cellSize);
            float mosaicLift = (0.04 + (0.08 * level)) * mosaicGridCompensation;
            mosaicColor += float3(mosaicLift);
            styledColor = clamp(mosaicColor, float3(0.0), float3(1.0));
        }

        if (uniforms.renderMode == 5) {
            float columnHash = fract(sin(floor(cell.x) * 91.73) * 23454.21);
            float stream = fract((uv.y * 7.0) + uniforms.time * (0.35 + columnHash * 0.75) + columnHash);
            float head = smoothstep(0.96, 1.0, stream);
            float trail = smoothstep(0.52, 1.0, stream) * (1.0 - head);
            float glyphBits = step(0.55, fract(sin(dot(floor(cell) + floor(uniforms.time * 7.0), float2(12.9898, 78.233))) * 43758.5453));
            float fineGridReadability = smoothstep(1.0, 6.0, uniforms.cellSize);
            float trailGate = smoothstep(0.22, 0.92, level) * mix(0.24, 0.78, fineGridReadability);
            float headMask = head * mix(0.50, 0.95, fineGridReadability);
            float rainMask = max(headMask, trail * glyphBits * trailGate);
            float3 rainBase = styledColor * mix(0.22, 0.08, fineGridReadability);
            float3 rainInk = clamp(styledColor * mix(0.62, 0.90, fineGridReadability) + float3(0.02, 0.08, 0.02) * headMask, float3(0.0), float3(1.0));
            rainInk = mix(rainInk, rainInk + float3(0.04, 0.18, 0.05), headMask * 0.45);
            styledColor = mix(rainBase, rainInk, rainMask);
            styledColor = mix(styledColor, styledColor + styledColor * 0.45, edgeMask * clamp(uniforms.edgeStrength, 0.0, 2.0) * 0.14);
        }

        if (uniforms.renderMode == 6) {
            float3 cyberSource = floor(clamp(cellColor, float3(0.0), float3(1.0)) * 10.0 + 0.5) / 10.0;
            float cyberLum = luminance(cyberSource);
            float scanline = 0.88 + (0.12 * sin((uv.y * uniforms.viewportSize.y * 1.65) + uniforms.time * 10.0));
            float sweep = smoothstep(0.028, 0.0, abs(fract((uv.y * 0.85) - uniforms.time * 0.08) - 0.5));
            float verticalHud = 1.0 - smoothstep(0.010, 0.038, min(local.x, 1.0 - local.x));
            float horizontalHud = 1.0 - smoothstep(0.010, 0.038, min(local.y, 1.0 - local.y));
            float hudGrid = max(verticalHud, horizontalHud) * 0.22;

            float edgeControl = clamp(uniforms.edgeStrength, 0.0, 2.0);
            float neonEdge = smoothstep(0.18, 0.86, edgeGlyph * coherentEdgeStrength * (0.62 + edgeControl));
            float edgeBloom = smoothstep(0.06, 0.58, edgeGlyph * coherentEdgeStrength * (0.52 + edgeControl));
            float magentaMix = step(0.5, hash);
            float3 neonA = float3(0.00, 0.92, 1.00);
            float3 neonB = float3(1.00, 0.08, 0.72);
            float3 neon = mix(neonA, neonB, magentaMix);

            float3 base = pow(clamp(cyberSource, float3(0.0), float3(1.0)), float3(0.86));
            float3 shadowTint = float3(0.012, 0.020, 0.036);
            float3 coolTint = float3(0.58, 0.86, 1.0);
            base = mix(shadowTint, base * coolTint, smoothstep(0.04, 0.98, cyberLum));
            base *= 0.62 + (0.26 * scanline);
            base *= mix(0.74, 1.0, vignette);
            base += float3(0.0, 0.18, 0.22) * sweep;
            base = mix(base, float3(0.0, 0.32, 0.42), hudGrid * 0.30);
            base = mix(base, neon, neonEdge * 0.70);
            base += neon * edgeBloom * 0.18;
            styledColor = clamp(base, float3(0.0), float3(1.0));
        }

        return float4(styledColor, clamp(uniforms.opacity, 0.10, 1.0));
    }
    """
}
