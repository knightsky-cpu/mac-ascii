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
        int luminanceBuckets;
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
        float edgeStrength = smoothstep(0.14, 0.38, gradientMagnitude);

        float edgeHorizontal = rect(local, float2(0.12, 0.70), float2(0.88, 0.86));
        float edgeVertical = rect(local, float2(0.42, 0.12), float2(0.58, 0.88));
        float edgeSlash = 1.0 - smoothstep(0.06, 0.13, abs((local.x + local.y) - 1.0));
        edgeSlash *= rect(local, float2(0.08), float2(0.92));
        float edgeBackslash = 1.0 - smoothstep(0.06, 0.13, abs(local.x - local.y));
        edgeBackslash *= rect(local, float2(0.08), float2(0.92));

        float edgeGlyph = edgeHorizontal;
        float absX = abs(gradientX);
        float absY = abs(gradientY);
        if (absX > absY * 1.35) edgeGlyph = edgeVertical;
        else if (absY > absX * 1.35) edgeGlyph = edgeHorizontal;
        else if (gradientX * gradientY > 0.0) edgeGlyph = edgeSlash;
        else edgeGlyph = edgeBackslash;

        float glyph = glyphMask(glyphBucket, local);
        float aaGlyph = smoothstep(0.03, 0.90, glyph);
        float glyphStrength = mix(0.20, 0.84, smoothstep(2.0, 5.0, uniforms.cellSize));
        float asciiMask = mix(1.0, aaGlyph, glyphStrength);
        float edgeMask = smoothstep(0.18, 0.92, edgeGlyph * edgeStrength);
        float inkAmount = clamp(0.35 + (max(level, edgeStrength) * 0.65), 0.0, 1.0);

        float3 posterColor = floor((pow(clamp(cellColor, float3(0.0), float3(1.0)), float3(0.9)) * 9.0) + 0.5) / 9.0;
        float grayValue = luminance(posterColor);
        float3 gray = float3(grayValue);
        float2 centeredUv = uv - float2(0.5);
        float vignette = smoothstep(0.78, 0.18, dot(centeredUv, centeredUv));

        float3 classicShadow = float3(0.12, 0.065, 0.018);
        float3 classicAmber = float3(1.0, 0.72, 0.18);
        float3 classicColor = mix(classicShadow, mix(classicShadow, classicAmber, inkAmount), asciiMask);

        float3 darkShadow = float3(0.030, 0.014, 0.003);
        float3 darkAmber = float3(0.78, 0.36, 0.055);
        float3 darkColor = mix(darkShadow, mix(darkShadow, darkAmber, inkAmount), asciiMask);
        darkColor = mix(darkColor, darkColor + float3(0.12, 0.045, 0.006), edgeMask * 0.45);

        float3 crtPalette = mix(gray, posterColor, 0.62);
        crtPalette = pow(clamp(crtPalette * 1.12, float3(0.0), float3(1.0)), float3(0.86));
        crtPalette *= mix(float3(0.80, 0.96, 1.16), float3(1.20, 1.02, 0.80), level);
        float3 crtColor = mix(float3(0.018, 0.030, 0.045), mix(float3(0.018, 0.030, 0.045), crtPalette, inkAmount), asciiMask);
        crtColor *= mix(0.74, 1.0, vignette);

        float hash = fract(sin(dot(floor(cell), float2(127.1, 311.7))) * 43758.5453);
        float3 hybridEdge = mix(float3(1.0, 0.78, 0.42), float3(1.0, 0.38, 0.82), step(0.5, hash));
        float3 hybridBase = mix(gray, posterColor, 0.78) * float3(0.96, 1.02, 1.08);
        float3 hybridColor = mix(float3(0.018, 0.022, 0.030), mix(float3(0.018, 0.022, 0.030), hybridBase, inkAmount), asciiMask);
        hybridColor = mix(hybridColor, hybridEdge, edgeMask * 0.55);

        float3 invertColor = mix(float3(0.02, 0.02, 0.025), pow(float3(1.0) - posterColor, float3(0.92)), inkAmount);
        invertColor = mix(float3(0.02, 0.02, 0.025), invertColor, asciiMask);

        float3 cyberBase = mix(gray, posterColor, 0.52) * float3(0.65, 0.92, 1.28);
        float3 cyberGlow = mix(float3(1.0, 0.12, 0.72), float3(0.72, 0.18, 1.0), step(0.46, hash));
        float3 cyberColor = mix(float3(0.025, 0.010, 0.050), mix(float3(0.025, 0.010, 0.050), cyberBase, inkAmount), asciiMask);
        cyberColor = mix(cyberColor, cyberGlow, edgeMask * 0.65);
        cyberColor *= mix(0.76, 1.0, vignette);

        float3 phosphorShadow = float3(0.002, 0.020, 0.010);
        float3 phosphorInk = mix(float3(0.12, 0.42, 0.18), float3(0.72, 1.00, 0.50), level);
        float scanline = 0.88 + (0.12 * sin((uv.y * uniforms.viewportSize.y * 3.14159) + uniforms.time * 8.0));
        float3 phosphorColor = mix(phosphorShadow, mix(phosphorShadow, phosphorInk, inkAmount), asciiMask);
        phosphorColor = mix(phosphorColor, phosphorColor + float3(0.10, 0.28, 0.08), edgeMask * 0.45);
        phosphorColor *= scanline * mix(0.76, 1.0, vignette);

        float3 paperBase = float3(0.94, 0.91, 0.82);
        float3 paperFiber = paperBase + ((hash - 0.5) * float3(0.035, 0.030, 0.018));
        float3 inkTone = mix(float3(0.30, 0.22, 0.14), float3(0.035, 0.030, 0.024), inkAmount);
        float3 paperColor = mix(paperFiber, inkTone, clamp(asciiMask * inkAmount, 0.0, 1.0));
        paperColor = mix(paperColor, float3(0.08, 0.055, 0.030), edgeMask * 0.70);

        float3 blueprintBase = float3(0.012, 0.060, 0.140);
        float3 blueprintInk = mix(float3(0.20, 0.52, 0.92), float3(0.86, 0.96, 1.00), inkAmount);
        float blueprintGrid = max(
            1.0 - smoothstep(0.015, 0.045, min(local.x, 1.0 - local.x)),
            1.0 - smoothstep(0.015, 0.045, min(local.y, 1.0 - local.y))
        );
        float3 blueprintColor = mix(blueprintBase, blueprintInk, asciiMask);
        blueprintColor = mix(blueprintColor, float3(0.45, 0.76, 1.0), blueprintGrid * 0.18);
        blueprintColor = mix(blueprintColor, float3(1.0, 0.95, 0.65), edgeMask * 0.42);

        float3 moonBase = float3(0.012, 0.014, 0.018);
        float3 moonInk = mix(float3(0.18, 0.22, 0.28), float3(0.86, 0.92, 1.0), inkAmount);
        float3 moonColor = mix(moonBase, moonInk, asciiMask);
        moonColor = mix(moonColor, float3(0.62, 0.82, 1.0), edgeMask * 0.48);
        moonColor *= mix(0.70, 1.0, vignette);

        float3 thermalCold = float3(0.020, 0.020, 0.070);
        float3 thermalMid = mix(float3(0.05, 0.26, 0.75), float3(0.95, 0.36, 0.10), smoothstep(0.20, 0.78, level));
        float3 thermalHot = mix(thermalMid, float3(1.0, 0.92, 0.30), smoothstep(0.78, 1.0, level));
        float3 thermalColor = mix(thermalCold, thermalHot, asciiMask * inkAmount);
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

        return float4(styledColor, 0.90);
    }
    """
}
