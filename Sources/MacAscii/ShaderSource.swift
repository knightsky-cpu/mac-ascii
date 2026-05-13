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
        float2 mousePosition;
        float mouseActive;
        float mousePadding;
        float2 mouseTrail0;
        float2 mouseTrail1;
        float2 mouseTrail2;
        float2 mouseTrail3;
        float2 mouseTrail4;
        float2 mouseTrail5;
        float2 mouseTrail6;
        float2 mouseTrail7;
        float2 mouseTrail8;
        float2 mouseTrail9;
        float2 mouseTrail10;
        float2 mouseTrail11;
        float2 mouseTrail12;
        float2 mouseTrail13;
        float2 mouseTrail14;
        float2 mouseTrail15;
        float circuitRowShred;
        float circuitRGBDrift;
        float circuitSmear;
        float circuitColorSwap;
        float circuitLumaInvert;
        float circuitBitRot;
        float circuitStaticNoise;
        float circuitVSyncRoll;
        float waterRippleCount;
        float4 waterRipple0;
        float4 waterRipple1;
        float4 waterRipple2;
        float4 waterRipple3;
        float4 waterRipple4;
        float4 waterRipple5;
        float4 waterRipple6;
        float4 waterRipple7;
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

    float hash12(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    uint trueAsciiGlyphIndex(uint bucketIndex, int luminanceBuckets) {
        if (luminanceBuckets <= 10) {
            switch (bucketIndex) {
                case 0: return 0;   // space
                case 1: return 1;   // .
                case 2: return 6;   // :
                case 3: return 8;   // c
                case 4: return 9;   // o
                case 5: return 11;  // P
                case 6: return 10;  // O
                case 7: return 20;  // ?
                case 8: return 18;  // @
                default: return 19; // #
            }
        }

        return min(bucketIndex, uint(19));
    }

    float trueAsciiEdgeVote(texture2d<float, access::sample> source, float2 sampleUv, float2 texel, thread uint& direction) {
        float rawLum = luminance(source.sample(linearSampler, sampleUv).rgb);
        float lumLeft = luminance(source.sample(linearSampler, clamp(sampleUv + float2(-texel.x, 0.0), float2(0.0), float2(1.0))).rgb);
        float lumRight = luminance(source.sample(linearSampler, clamp(sampleUv + float2(texel.x, 0.0), float2(0.0), float2(1.0))).rgb);
        float lumTop = luminance(source.sample(linearSampler, clamp(sampleUv + float2(0.0, -texel.y), float2(0.0), float2(1.0))).rgb);
        float lumBottom = luminance(source.sample(linearSampler, clamp(sampleUv + float2(0.0, texel.y), float2(0.0), float2(1.0))).rgb);
        float lumTopLeft = luminance(source.sample(linearSampler, clamp(sampleUv + float2(-texel.x, -texel.y), float2(0.0), float2(1.0))).rgb);
        float lumTopRight = luminance(source.sample(linearSampler, clamp(sampleUv + float2(texel.x, -texel.y), float2(0.0), float2(1.0))).rgb);
        float lumBottomLeft = luminance(source.sample(linearSampler, clamp(sampleUv + float2(-texel.x, texel.y), float2(0.0), float2(1.0))).rgb);
        float lumBottomRight = luminance(source.sample(linearSampler, clamp(sampleUv + float2(texel.x, texel.y), float2(0.0), float2(1.0))).rgb);
        float localMean = (
            lumTopLeft + lumTop + lumTopRight +
            lumLeft + rawLum + lumRight +
            lumBottomLeft + lumBottom + lumBottomRight
        ) / 9.0;
        float gradientX = (lumTopRight + (2.0 * lumRight) + lumBottomRight) - (lumTopLeft + (2.0 * lumLeft) + lumBottomLeft);
        float gradientY = (lumBottomLeft + (2.0 * lumBottom) + lumBottomRight) - (lumTopLeft + (2.0 * lumTop) + lumTopRight);
        float gradientMagnitude = length(float2(gradientX, gradientY));
        float absX = abs(gradientX);
        float absY = abs(gradientY);
        float gradientSum = max(0.0001, absX + absY);
        float majorGradient = max(absX, absY);
        float minorGradient = min(absX, absY);
        float axisDominance = majorGradient / gradientSum;
        float axisMargin = (majorGradient - minorGradient) / gradientSum;
        float diagonalBalance = 1.0 - axisMargin;
        float directionCoherence = max(
            smoothstep(0.58, 0.78, axisDominance),
            smoothstep(0.42, 0.62, diagonalBalance)
        );
        float dogContrast = clamp(abs(rawLum - localMean) * 4.0, 0.0, 1.0);
        float dogGate = smoothstep(0.018, 0.085, dogContrast);
        float confidence = smoothstep(0.30, 0.88, gradientMagnitude) * mix(0.58, 1.0, dogGate) * directionCoherence;

        if (absX > absY * 1.40) {
            direction = 1; // |
        } else if (absY > absX * 1.40) {
            direction = 0; // _
        } else if (gradientX * gradientY > 0.0) {
            direction = 2; // /
        } else {
            direction = 3; // backslash
        }

        return confidence;
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

    kernel void compute_true_ascii_cell_map(texture2d<float, access::sample> source [[texture(0)]],
                                            texture2d<uint, access::write> cellMap [[texture(1)]],
                                            constant Uniforms& uniforms [[buffer(0)]],
                                            uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= cellMap.get_width() || gid.y >= cellMap.get_height()) {
            return;
        }

        float2 gridSize = float2(float(cellMap.get_width()), float(cellMap.get_height()));
        float2 cellUv = (float2(gid) + float2(0.5)) / gridSize;
        float3 cellColor = source.sample(linearSampler, cellUv).rgb;
        float rawLum = luminance(cellColor);
        float toneGamma = clamp(uniforms.gamma, 0.50, 2.0);
        cellColor = clamp(((cellColor + uniforms.brightness) - 0.5) * clamp(uniforms.contrast, 0.50, 2.0) + 0.5, float3(0.0), float3(1.0));
        cellColor = pow(cellColor, float3(1.0 / toneGamma));
        float lum = luminance(cellColor);
        float glyphLum = mix(lum, rawLum, 0.15);
        float exposed = pow(clamp((glyphLum * 1.35) + 0.08, 0.0, 0.999), 0.72);
        uint bucketIndex = uint(clamp(floor(exposed * float(uniforms.luminanceBuckets)), 0.0, float(uniforms.luminanceBuckets - 1)));
        uint glyphIndex = trueAsciiGlyphIndex(bucketIndex, uniforms.luminanceBuckets);

        float2 texel = 1.0 / gridSize;
        float2 offsets[5] = {
            float2(0.0, 0.0),
            float2(-0.28, -0.28),
            float2(0.28, -0.28),
            float2(-0.28, 0.28),
            float2(0.28, 0.28)
        };
        float directionScores[4] = {0.0, 0.0, 0.0, 0.0};
        float totalEdgeConfidence = 0.0;
        for (uint sampleIndex = 0; sampleIndex < 5; sampleIndex++) {
            uint direction = 0;
            float2 sampleUv = clamp(cellUv + (offsets[sampleIndex] / gridSize), float2(0.0), float2(1.0));
            float confidence = trueAsciiEdgeVote(source, sampleUv, texel, direction);
            directionScores[direction] += confidence;
            totalEdgeConfidence += confidence;
        }

        float bestScore = directionScores[0];
        uint bestDirection = 0;
        float runnerUpScore = 0.0;
        for (uint direction = 1; direction < 4; direction++) {
            float score = directionScores[direction];
            if (score > bestScore) {
                runnerUpScore = bestScore;
                bestScore = score;
                bestDirection = direction;
            } else {
                runnerUpScore = max(runnerUpScore, score);
            }
        }

        float dominance = bestScore / max(0.0001, totalEdgeConfidence);
        float margin = (bestScore - runnerUpScore) / max(0.0001, totalEdgeConfidence);
        bool diagonalEdge = bestDirection >= 2;
        float edgeThreshold = diagonalEdge ? 1.18 : 0.82;
        float dominanceThreshold = diagonalEdge ? 0.58 : 0.46;
        float marginThreshold = diagonalEdge ? 0.18 : 0.08;
        if (
            bestScore >= edgeThreshold &&
            dominance >= dominanceThreshold &&
            margin >= marginThreshold
        ) {
            if (bestDirection == 0) {
                glyphIndex = 20; // _
            } else if (bestDirection == 1) {
                glyphIndex = 21; // |
            } else if (bestDirection == 2) {
                glyphIndex = 22; // /
            } else {
                glyphIndex = 23; // backslash
            }
        }

        float edgeConfidence = clamp(bestScore / 2.20, 0.0, 1.0);
        uint packedEdge = (bestDirection + 1u) |
            (uint(round(edgeConfidence * 255.0)) << 8) |
            (uint(round(clamp(dominance, 0.0, 1.0) * 255.0)) << 16);

        uint3 color8 = uint3(round(clamp(cellColor, float3(0.0), float3(1.0)) * 255.0));
        uint packedColor = color8.r | (color8.g << 8) | (color8.b << 16);
        cellMap.write(uint4(glyphIndex, bucketIndex, packedColor, packedEdge), gid);
    }

    kernel void compute_circuit_bend(texture2d<float, access::sample> source [[texture(0)]],
                                     texture2d<float, access::write> output [[texture(1)]],
                                     constant Uniforms& uniforms [[buffer(0)]],
                                     uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
            return;
        }

        float2 outputSize = float2(float(output.get_width()), float(output.get_height()));
        float2 uv = (float2(gid) + float2(0.5)) / outputSize;
        float time = uniforms.time;

        float rowShredAmount = clamp(uniforms.circuitRowShred, 0.0, 2.0);
        float rgbDriftAmount = clamp(uniforms.circuitRGBDrift, 0.0, 2.0);
        float smearAmount = clamp(uniforms.circuitSmear, 0.0, 2.0);
        float colorSwapAmount = clamp(uniforms.circuitColorSwap, 0.0, 2.0);
        float lumaInvertAmount = clamp(uniforms.circuitLumaInvert, 0.0, 2.0);
        float bitRotAmount = clamp(uniforms.circuitBitRot, 0.0, 2.0);
        float staticAmount = clamp(uniforms.circuitStaticNoise, 0.0, 2.0);
        float rollAmount = clamp(uniforms.circuitVSyncRoll, 0.0, 2.0);

        float pulse = pow(max(0.0, sin(time * 1.35)), 24.0);
        float row = floor(uv.y * outputSize.y);
        float rowSeed = hash12(float2(row, floor(time * 18.0)));
        float rowGate = step(0.965 - (pulse * 0.035 * rowShredAmount), rowSeed) * min(1.0, rowShredAmount);
        float rowShift = (hash12(float2(row * 0.37, floor(time * 23.0))) - 0.5) * 0.12 * rowGate * rowShredAmount;
        float waveShift = sin((uv.y * 95.0) + (time * 8.0)) * 0.0035 * (0.35 + pulse) * rowShredAmount;
        float roll = pulse * 0.18 * rollAmount;

        float2 baseUv = fract(float2(uv.x + rowShift + waveShift, uv.y + roll));
        float rowDrift = (hash12(float2(row * 1.17, floor(time * 13.0))) - 0.5) * 0.010 * rowGate;
        float drift = ((sin((time * 3.0) + (uv.y * 24.0)) * 0.010) + (rowGate * 0.022) + rowDrift) * rgbDriftAmount;

        float3 center = source.sample(linearSampler, baseUv).rgb;
        float red = source.sample(linearSampler, fract(baseUv + float2(drift, 0.0))).r;
        float green = center.g;
        float blue = source.sample(linearSampler, fract(baseUv - float2(drift, 0.0))).b;
        float3 color = float3(red, green, blue);

        float smearGate = rowGate * step(0.36, hash12(float2(row, floor(time * 11.0)))) * min(1.0, smearAmount);
        float3 smearColor = source.sample(linearSampler, fract(baseUv + float2(rowShift * 0.55 + drift * 2.2, 0.0))).rgb;
        color = mix(color, smearColor, smearGate * 0.38 * smearAmount);

        float swapGate = step(0.978 - (pulse * 0.030 * colorSwapAmount), hash12(floor(uv * outputSize / 24.0) + floor(time * 7.0))) * min(1.0, colorSwapAmount);
        float swapKind = hash12(float2(row * 0.19, floor(time * 5.0)));
        float3 swappedA = color.gbr;
        float3 swappedB = color.brg;
        color = mix(color, mix(swappedA, swappedB, step(0.5, swapKind)), swapGate * (0.34 + rowGate * 0.28) * colorSwapAmount);

        float lum = luminance(color);
        float inversionGate = step(0.82, lum) * step(0.78 - (pulse * 0.18 * lumaInvertAmount), hash12(floor(uv * outputSize / 18.0) + floor(time * 9.0))) * min(1.0, lumaInvertAmount);
        color = mix(color, 1.0 - color, inversionGate * (0.42 + (pulse * 0.38)) * lumaInvertAmount);

        float rotGate = step(0.991 - (pulse * 0.040 * bitRotAmount), hash12(float2(gid) + floor(time * 31.0))) * min(1.0, bitRotAmount);
        uint3 bits = uint3(round(clamp(color, float3(0.0), float3(1.0)) * 255.0));
        uint3 bentBits = bits ^ uint3(0x1Au, 0x05u, 0x22u);
        color = mix(color, float3(bentBits) / 255.0, rotGate * 0.72 * bitRotAmount);

        float staticGate = step(0.996 - (pulse * 0.025 * staticAmount), hash12(float2(gid.yx) + (time * 43.0))) * min(1.0, staticAmount);
        float staticValue = step(0.5, hash12(float2(gid) * 1.91 + floor(time * 60.0)));
        color = mix(color, float3(staticValue), staticGate * 0.55 * staticAmount);

        float scan = 0.94 + (0.06 * sin((uv.y * outputSize.y * 3.14159) + (time * 12.0)));
        color *= scan;

        output.write(float4(clamp(color, float3(0.0), float3(1.0)), 1.0), gid);
    }

    float2 inputBendDisplacement(float2 uv,
                                  float2 point,
                                  float active,
                                  float weight,
                                  float radius,
                                  float2 outputSize,
                                  float time) {
        float aspect = outputSize.x / max(1.0, outputSize.y);
        float2 delta = uv - point;
        delta.x *= aspect;
        float dist = length(delta);
        float influence = (1.0 - smoothstep(0.0, radius, dist)) * active * weight;

        float2 direction = normalize(delta + float2(0.0001));
        direction.x /= aspect;
        float pull = influence * influence * 0.040;
        float ripple = sin((dist * 84.0) - (time * 5.0)) * influence * 0.004;
        return direction * (pull + ripple);
    }

    kernel void compute_input_bend_trail_state(texture2d<float, access::read> previousState [[texture(0)]],
                                               texture2d<float, access::write> nextState [[texture(1)]],
                                               constant Uniforms& uniforms [[buffer(0)]],
                                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= nextState.get_width() || gid.y >= nextState.get_height()) {
            return;
        }

        float2 outputSize = float2(float(nextState.get_width()), float(nextState.get_height()));
        float2 uv = (float2(gid) + float2(0.5)) / outputSize;
        float4 state = previousState.read(gid);
        state.xy *= 0.90;
        state.z *= 0.90;

        float active = clamp(uniforms.mouseActive, 0.0, 1.0);
        float2 mouse = clamp(uniforms.mousePosition, float2(0.0), float2(1.0));
        float aspect = outputSize.x / max(1.0, outputSize.y);
        float2 delta = uv - mouse;
        delta.x *= aspect;
        float dist = length(delta);
        float radius = 0.125;
        float influence = (1.0 - smoothstep(0.0, radius, dist)) * active;

        float2 direction = normalize(delta + float2(0.0001));
        direction.x /= aspect;
        float2 freshDisplacement = direction * influence * influence * 0.022;
        state.xy += freshDisplacement;
        state.xy = clamp(state.xy, float2(-0.045), float2(0.045));
        state.z = max(state.z, influence);

        if (state.z < 0.004) {
            state = float4(0.0);
        }

        nextState.write(float4(state.xyz, 0.0), gid);
    }

    kernel void compute_input_bend(texture2d<float, access::sample> source [[texture(0)]],
                                   texture2d<float, access::write> output [[texture(1)]],
                                   texture2d<float, access::sample> trailState [[texture(2)]],
                                   constant Uniforms& uniforms [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
            return;
        }

        float2 outputSize = float2(float(output.get_width()), float(output.get_height()));
        float2 uv = (float2(gid) + float2(0.5)) / outputSize;
        float2 mouse = clamp(uniforms.mousePosition, float2(0.0), float2(1.0));
        float active = clamp(uniforms.mouseActive, 0.0, 1.0);
        float trailCount = uniforms.mousePadding;

        float2 displacement = inputBendDisplacement(uv, mouse, active, 1.0, 0.165, outputSize, uniforms.time);
        if (trailCount > 1.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail1, active, 0.90, 0.156, outputSize, uniforms.time - 0.02);
        }
        if (trailCount > 2.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail2, active, 0.74, 0.148, outputSize, uniforms.time - 0.04);
        }
        if (trailCount > 3.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail3, active, 0.56, 0.138, outputSize, uniforms.time - 0.06);
        }
        if (trailCount > 4.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail4, active, 0.38, 0.128, outputSize, uniforms.time - 0.08);
        }
        if (trailCount > 5.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail5, active, 0.24, 0.118, outputSize, uniforms.time - 0.10);
        }
        if (trailCount > 6.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail6, active, 0.14, 0.108, outputSize, uniforms.time - 0.12);
        }
        if (trailCount > 7.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail7, active, 0.08, 0.098, outputSize, uniforms.time - 0.14);
        }
        if (trailCount > 8.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail8, active, 0.055, 0.090, outputSize, uniforms.time - 0.16);
        }
        if (trailCount > 9.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail9, active, 0.040, 0.083, outputSize, uniforms.time - 0.18);
        }
        if (trailCount > 10.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail10, active, 0.030, 0.076, outputSize, uniforms.time - 0.20);
        }
        if (trailCount > 11.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail11, active, 0.022, 0.070, outputSize, uniforms.time - 0.22);
        }
        if (trailCount > 12.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail12, active, 0.016, 0.064, outputSize, uniforms.time - 0.24);
        }
        if (trailCount > 13.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail13, active, 0.011, 0.058, outputSize, uniforms.time - 0.26);
        }
        if (trailCount > 14.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail14, active, 0.007, 0.052, outputSize, uniforms.time - 0.28);
        }
        if (trailCount > 15.5) {
            displacement += inputBendDisplacement(uv, uniforms.mouseTrail15, active, 0.004, 0.047, outputSize, uniforms.time - 0.30);
        }

        float4 feedback = trailState.sample(linearSampler, uv);
        displacement += feedback.xy * clamp(0.70 + feedback.z, 0.0, 1.25);

        float2 sampleUv = clamp(uv - displacement, float2(0.0), float2(1.0));

        float3 color = source.sample(linearSampler, sampleUv).rgb;

        output.write(float4(color, 1.0), gid);
    }

    float2 waterRippleDisplacement(float2 uv, float4 ripple, float2 outputSize, float time, float strength) {
        if (ripple.w < 0.5) {
            return float2(0.0);
        }

        float age = time - ripple.z;
        if (age < 0.0 || age > 2.2) {
            return float2(0.0);
        }

        float aspect = outputSize.x / max(1.0, outputSize.y);
        float2 center = ripple.xy;
        float2 delta = uv - center;
        delta.x *= aspect;
        float dist = length(delta);
        float2 direction = normalize(delta + float2(0.0001));
        direction.x /= aspect;

        float decay = pow(clamp(1.0 - (age / 2.2), 0.0, 1.0), 1.65);
        float waveSpeed = 0.46;
        float width = 0.032 + (age * 0.010);
        float amplitude = 0.0;

        float leadRadius = age * waveSpeed;
        float leadDistance = abs(dist - leadRadius);
        float leadRing = 1.0 - smoothstep(0.0, width, leadDistance);
        amplitude += leadRing * sin((dist - leadRadius) * 118.0) * 0.044;

        float secondRadius = max(0.0, (age - 0.12) * waveSpeed);
        float secondDistance = abs(dist - secondRadius);
        float secondRing = (1.0 - smoothstep(0.0, width * 1.12, secondDistance)) * smoothstep(0.08, 0.22, age);
        amplitude += secondRing * sin((dist - secondRadius) * 108.0) * 0.027;

        float thirdRadius = max(0.0, (age - 0.24) * waveSpeed);
        float thirdDistance = abs(dist - thirdRadius);
        float thirdRing = (1.0 - smoothstep(0.0, width * 1.26, thirdDistance)) * smoothstep(0.18, 0.36, age);
        amplitude += thirdRing * sin((dist - thirdRadius) * 98.0) * 0.017;

        float fourthRadius = max(0.0, (age - 0.38) * waveSpeed);
        float fourthDistance = abs(dist - fourthRadius);
        float fourthRing = (1.0 - smoothstep(0.0, width * 1.42, fourthDistance)) * smoothstep(0.30, 0.52, age);
        amplitude += fourthRing * sin((dist - fourthRadius) * 88.0) * 0.010;

        amplitude *= decay;

        float innerWake = (1.0 - smoothstep(0.0, leadRadius, dist)) *
                          smoothstep(0.0, 0.20, age) *
                          decay * 0.006;
        return direction * (amplitude + innerWake) * strength;
    }

    float2 ambientWaterDisplacement(float2 uv, float2 outputSize, float time) {
        float aspect = outputSize.x / max(1.0, outputSize.y);
        float slowX = sin((uv.y * 19.0) + (time * 0.72));
        float slowY = sin((uv.x * 16.0 * aspect) + (time * 0.58));
        float cross = sin(((uv.x * 10.0 * aspect) + (uv.y * 13.0)) - (time * 0.44));
        return float2(
            (slowX * 0.0012) + (cross * 0.0007),
            (slowY * 0.0009) - (cross * 0.0005)
        );
    }

    float4 automaticWaterRipple(float time, float interval, float phase, float seed) {
        float eventTime = floor((time + phase) / interval);
        float age = fmod(time + phase, interval);
        float2 center = float2(
            0.12 + (hash12(float2(seed, eventTime)) * 0.76),
            0.12 + (hash12(float2(eventTime, seed + 9.37)) * 0.76)
        );
        return float4(center, time - age, 1.0);
    }

    kernel void compute_water_bend(texture2d<float, access::sample> source [[texture(0)]],
                                   texture2d<float, access::write> output [[texture(1)]],
                                   constant Uniforms& uniforms [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
            return;
        }

        float2 outputSize = float2(float(output.get_width()), float(output.get_height()));
        float2 uv = (float2(gid) + float2(0.5)) / outputSize;
        float2 displacement = ambientWaterDisplacement(uv, outputSize, uniforms.time);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple0, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple1, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple2, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple3, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple4, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple5, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple6, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, uniforms.waterRipple7, outputSize, uniforms.time, 1.0);
        displacement += waterRippleDisplacement(uv, automaticWaterRipple(uniforms.time, 4.8, 0.4, 17.0), outputSize, uniforms.time, 0.16);
        displacement += waterRippleDisplacement(uv, automaticWaterRipple(uniforms.time, 6.7, 2.1, 41.0), outputSize, uniforms.time, 0.11);
        displacement += waterRippleDisplacement(uv, automaticWaterRipple(uniforms.time, 8.9, 5.3, 73.0), outputSize, uniforms.time, 0.08);

        float2 sampleUv = clamp(uv - displacement, float2(0.0), float2(1.0));
        float3 color = source.sample(linearSampler, sampleUv).rgb;
        output.write(float4(color, 1.0), gid);
    }

    fragment float4 fragment_ascii(VertexOut in [[stage_in]],
                                  texture2d<float> source [[texture(0)]],
                                  texture2d<float> glyphAtlas [[texture(1)]],
                                  texture2d<uint> cellMap [[texture(2)]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
        float2 uv = clamp(in.uv, float2(0.0), float2(1.0));
        if (uniforms.renderMode == 9 || uniforms.renderMode == 10 || uniforms.renderMode == 11) {
            return float4(source.sample(linearSampler, uv).rgb, clamp(uniforms.opacity, 0.10, 1.0));
        }

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
        float lumTopLeft = luminance(source.sample(linearSampler, clamp(cellUv + float2(-texel.x, -texel.y), float2(0.0), float2(1.0))).rgb);
        float lumTopRight = luminance(source.sample(linearSampler, clamp(cellUv + float2(texel.x, -texel.y), float2(0.0), float2(1.0))).rgb);
        float lumBottomLeft = luminance(source.sample(linearSampler, clamp(cellUv + float2(-texel.x, texel.y), float2(0.0), float2(1.0))).rgb);
        float lumBottomRight = luminance(source.sample(linearSampler, clamp(cellUv + float2(texel.x, texel.y), float2(0.0), float2(1.0))).rgb);
        float localMean = (
            lumTopLeft + lumTop + lumTopRight +
            lumLeft + lum + lumRight +
            lumBottomLeft + lumBottom + lumBottomRight
        ) / 9.0;
        float dogContrast = clamp(abs(lum - localMean) * 4.0, 0.0, 1.0);
        float gradientX = (lumTopRight + (2.0 * lumRight) + lumBottomRight) - (lumTopLeft + (2.0 * lumLeft) + lumBottomLeft);
        float gradientY = (lumBottomLeft + (2.0 * lumBottom) + lumBottomRight) - (lumTopLeft + (2.0 * lumTop) + lumTopRight);
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
        float styleMask = asciiMask;
        if (uniforms.renderMode == 0) {
            styleMask = asciiNormalizedMask;
        } else if (uniforms.renderMode == 7) {
            styleMask = 1.0;
        }

        float3 posterColor = floor((pow(clamp(cellColor, float3(0.0), float3(1.0)), float3(0.9)) * 9.0) + 0.5) / 9.0;
        float grayValue = luminance(posterColor);
        float3 gray = float3(grayValue);
        float2 centeredUv = uv - float2(0.5);
        float vignette = smoothstep(0.78, 0.18, dot(centeredUv, centeredUv));

        float3 classicShadow = float3(0.065, 0.032, 0.008);
        float3 classicAmber = float3(0.96, 0.62, 0.12);
        float3 classicTone = mix(classicShadow, classicAmber, pow(inkAmount, 0.94));
        float3 classicColor = mix(classicShadow, classicTone, styleMask);

        float3 darkShadow = float3(0.016, 0.007, 0.0015);
        float3 darkAmber = float3(0.62, 0.25, 0.030);
        float3 darkTone = mix(darkShadow, darkAmber, pow(inkAmount, 1.06));
        float3 darkColor = mix(darkShadow, darkTone, styleMask);
        darkColor = mix(darkColor, darkColor + float3(0.06, 0.020, 0.002), edgeMask * 0.30);

        float3 crtPalette = mix(gray, posterColor, 0.54);
        crtPalette = pow(clamp(crtPalette * 1.04, float3(0.0), float3(1.0)), float3(0.92));
        crtPalette *= mix(float3(0.76, 0.90, 1.06), float3(1.08, 0.98, 0.82), level);
        float3 crtBase = float3(0.012, 0.020, 0.032);
        float3 crtColor = mix(crtBase, mix(crtBase, crtPalette, inkAmount), styleMask);
        crtColor *= mix(0.80, 1.0, vignette);

        float hash = fract(sin(dot(floor(cell), float2(127.1, 311.7))) * 43758.5453);
        float3 hybridEdge = mix(float3(1.0, 0.74, 0.36), float3(0.94, 0.30, 0.72), step(0.5, hash));
        float3 hybridBase = mix(gray, posterColor, 0.70) * float3(0.90, 0.96, 1.00);
        float3 hybridShadow = float3(0.012, 0.016, 0.024);
        float3 hybridColor = mix(hybridShadow, mix(hybridShadow, hybridBase, inkAmount), styleMask);
        hybridColor = mix(hybridColor, hybridEdge, edgeMask * 0.42);

        float3 invertBase = float3(0.014, 0.014, 0.018);
        float3 invertTone = mix(invertBase, pow(float3(1.0) - posterColor, float3(0.98)), inkAmount);
        float3 invertColor = mix(invertBase, invertTone, styleMask);

        float3 cyberBase = mix(gray, posterColor, 0.42) * float3(0.52, 0.82, 1.10);
        float3 cyberGlow = mix(float3(1.0, 0.12, 0.72), float3(0.72, 0.18, 1.0), step(0.46, hash));
        float3 cyberShadow = float3(0.015, 0.006, 0.032);
        float3 cyberColor = mix(cyberShadow, mix(cyberShadow, cyberBase, inkAmount), styleMask);
        cyberColor = mix(cyberColor, cyberGlow, edgeMask * 0.42);
        cyberColor *= mix(0.82, 1.0, vignette);

        float3 phosphorShadow = float3(0.001, 0.012, 0.006);
        float3 phosphorInk = mix(float3(0.08, 0.30, 0.14), float3(0.58, 0.88, 0.42), level);
        float scanline = 0.88 + (0.12 * sin((uv.y * uniforms.viewportSize.y * 3.14159) + uniforms.time * 8.0));
        float3 phosphorColor = mix(phosphorShadow, mix(phosphorShadow, phosphorInk, inkAmount), styleMask);
        phosphorColor = mix(phosphorColor, phosphorColor + float3(0.06, 0.16, 0.05), edgeMask * 0.34);
        phosphorColor *= scanline * mix(0.84, 1.0, vignette);

        float3 paperBase = float3(0.90, 0.87, 0.78);
        float3 paperFiber = paperBase + ((hash - 0.5) * float3(0.028, 0.024, 0.014));
        float3 inkTone = mix(float3(0.26, 0.19, 0.12), float3(0.028, 0.024, 0.020), inkAmount);
        float3 paperColor = mix(paperFiber, inkTone, clamp(styleMask * inkAmount, 0.0, 1.0));
        paperColor = mix(paperColor, float3(0.06, 0.040, 0.022), edgeMask * 0.56);

        float3 blueprintBase = float3(0.008, 0.042, 0.104);
        float3 blueprintInk = mix(float3(0.16, 0.42, 0.80), float3(0.78, 0.90, 0.98), inkAmount);
        float blueprintGrid = max(
            1.0 - smoothstep(0.015, 0.045, min(local.x, 1.0 - local.x)),
            1.0 - smoothstep(0.015, 0.045, min(local.y, 1.0 - local.y))
        );
        float3 blueprintColor = mix(blueprintBase, blueprintInk, styleMask);
        blueprintColor = mix(blueprintColor, float3(0.34, 0.62, 0.92), blueprintGrid * 0.12);
        blueprintColor = mix(blueprintColor, float3(0.94, 0.92, 0.70), edgeMask * 0.30);

        float3 moonBase = float3(0.008, 0.010, 0.014);
        float3 moonInk = mix(float3(0.14, 0.18, 0.24), float3(0.78, 0.86, 0.96), inkAmount);
        float3 moonColor = mix(moonBase, moonInk, styleMask);
        moonColor = mix(moonColor, float3(0.54, 0.72, 0.96), edgeMask * 0.34);
        moonColor *= mix(0.80, 1.0, vignette);

        float3 thermalCold = float3(0.020, 0.020, 0.070);
        float3 thermalMid = mix(float3(0.05, 0.26, 0.75), float3(0.95, 0.36, 0.10), smoothstep(0.20, 0.78, level));
        float3 thermalHot = mix(thermalMid, float3(1.0, 0.92, 0.30), smoothstep(0.78, 1.0, level));
        float3 thermalColor = mix(thermalCold, thermalHot, styleMask * inkAmount);
        thermalColor = mix(thermalColor, float3(0.05, 0.92, 0.78), edgeMask * 0.44);

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

        if (uniforms.renderMode == 1 || uniforms.renderMode == 8) {
            uint2 blockCellIndex = uint2(
                min(uint(floor(cell.x)), cellMap.get_width() - 1),
                min(uint(floor(cell.y)), cellMap.get_height() - 1)
            );
            uint4 blockCellData = cellMap.read(blockCellIndex);
            float3 blockBase = floor(clamp(cellColor, float3(0.0), float3(1.0)) * 5.0 + 0.5) / 5.0;
            if (uniforms.renderMode == 8) {
                uint packedColor = blockCellData.b;
                blockBase = float3(
                    float(packedColor & 255u),
                    float((packedColor >> 8) & 255u),
                    float((packedColor >> 16) & 255u)
                ) / 255.0;
                blockBase = floor(clamp(blockBase, float3(0.0), float3(1.0)) * 5.0 + 0.5) / 5.0;
            }
            float blockLum = luminance(blockBase);
            float3 blockColor = mix(blockBase, posterColor, 0.35);
            if (uniforms.renderMode == 8) {
                blockColor = blockBase;
            }

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

            if (uniforms.renderMode == 8) {
                uint packedEdge = blockCellData.a;
                uint edgeDirectionCode = packedEdge & 255u;
                float computeEdge = float((packedEdge >> 8) & 255u) / 255.0;
                float edgeDominance = float((packedEdge >> 16) & 255u) / 255.0;

                float trueEdgeHorizontal = rect(local, float2(0.08, 0.66), float2(0.92, 0.88));
                float trueEdgeVertical = rect(local, float2(0.38, 0.08), float2(0.62, 0.92));
                float trueEdgeSlash = 1.0 - smoothstep(0.08, 0.18, abs((local.x + local.y) - 1.0));
                trueEdgeSlash *= rect(local, float2(0.05), float2(0.95));
                float trueEdgeBackslash = 1.0 - smoothstep(0.08, 0.18, abs(local.x - local.y));
                trueEdgeBackslash *= rect(local, float2(0.05), float2(0.95));

                float trueEdgeShape = trueEdgeHorizontal;
                if (edgeDirectionCode == 2u) {
                    trueEdgeShape = trueEdgeVertical;
                } else if (edgeDirectionCode == 3u) {
                    trueEdgeShape = trueEdgeSlash;
                } else if (edgeDirectionCode == 4u) {
                    trueEdgeShape = trueEdgeBackslash;
                }

                float trueEdgeStrength = clamp((computeEdge * 1.35) + (edgeDominance * 0.18), 0.0, 1.0);
                float trueEdgeMask = smoothstep(0.12, 0.74, trueEdgeShape * trueEdgeStrength);
                float3 edgeLight = clamp((blockColor * 1.42) + float3(0.06), float3(0.0), float3(1.0));
                float3 edgeDark = blockColor * 0.34;
                blockColor = mix(blockColor, edgeDark, trueEdgeMask * 0.32);
                blockColor = mix(blockColor, edgeLight, trueEdgeMask * 0.24);
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
            float3 rainSource = pow(clamp(cellColor, float3(0.0), float3(1.0)), float3(0.72));
            rainSource = clamp(((rainSource + 0.10) - 0.5) * 2.00 + 0.5, float3(0.0), float3(1.0));
            float3 rainBase = rainSource * mix(0.62, 0.46, fineGridReadability);
            rainBase += rainSource * (0.12 + (0.08 * fineGridReadability));
            float3 rainNeonA = float3(0.00, 0.88, 1.00);
            float3 rainNeonB = float3(1.00, 0.14, 0.74);
            float3 rainParticle = mix(rainNeonA, rainNeonB, step(0.5, columnHash));
            float particleGlow = max(headMask, trail * glyphBits * mix(0.55, 0.88, fineGridReadability));
            float3 rainInk = clamp(
                (rainBase * 0.55) + (rainParticle * particleGlow * 1.24) + (rainParticle * headMask * 0.32),
                float3(0.0),
                float3(1.0)
            );
            styledColor = mix(rainBase, rainInk, rainMask);
            styledColor = mix(styledColor, styledColor + (rainParticle * 0.22), headMask * 0.40);
            styledColor = mix(styledColor, styledColor + styledColor * 0.34, edgeMask * clamp(uniforms.edgeStrength, 0.0, 2.0) * 0.12);
            styledColor = clamp(((styledColor + 0.04) - 0.5) * 1.18 + 0.5, float3(0.0), float3(1.0));
        }

        if (uniforms.renderMode == 6) {
            float3 cyberSource = clamp(cellColor, float3(0.0), float3(1.0));
            float sweep = smoothstep(0.028, 0.0, abs(fract((uv.y * 0.85) - uniforms.time * 0.08) - 0.5));

            float edgeControl = clamp(uniforms.edgeStrength, 0.0, 2.0);
            float neonEdge = smoothstep(0.10, 0.62, edgeGlyph * coherentEdgeStrength * (0.92 + edgeControl));
            float edgeBloom = smoothstep(0.03, 0.40, edgeGlyph * coherentEdgeStrength * (0.82 + edgeControl));
            float3 neon = float3(1.00, 0.10, 0.74);

            float3 base = cyberSource;
            base += float3(0.0, 0.18, 0.26) * sweep;
            base = mix(base, neon, neonEdge * 0.92);
            base += neon * edgeBloom * 0.34;
            styledColor = clamp(base, float3(0.0), float3(1.0));
        }

        if (uniforms.renderMode == 7) {
            uint2 cellIndex = uint2(
                min(uint(floor(cell.x)), cellMap.get_width() - 1),
                min(uint(floor(cell.y)), cellMap.get_height() - 1)
            );
            uint glyphIndex = cellMap.read(cellIndex).r;
            constexpr float atlasGlyphCount = 25.0;
            float2 glyphUv = float2((float(glyphIndex) + local.x) / atlasGlyphCount, local.y);
            float glyphSample = glyphAtlas.sample(linearSampler, glyphUv).r;
            float glyphAlpha = smoothstep(0.16, 0.76, glyphSample);
            float tinyCellStrength = mix(0.38, 1.0, smoothstep(1.0, 4.0, uniforms.cellSize));
            float trueAsciiMask = clamp(glyphAlpha * tinyCellStrength, 0.0, 1.0);
            float3 background = styledColor * mix(0.22, 0.38, level);
            float3 foreground = clamp(styledColor * mix(1.08, 1.24, level), float3(0.0), float3(1.0));
            styledColor = mix(background, foreground, trueAsciiMask);
        }

        return float4(styledColor, clamp(uniforms.opacity, 0.10, 1.0));
    }
    """
}
