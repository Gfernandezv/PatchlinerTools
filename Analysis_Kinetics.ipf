#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

//====================================================
//   KINETICS ANALYSIS — UNDER DEVELOPMENT
//====================================================
//
// This module contains temperature-dependent kinetics
// analysis functions.
//
// Status:
//   Q10_calculator      — functional, under review
//   Arrhenius_calculator — functional, under review
//
// References:
//   Zgrablic et al. 2020 Bioengineering — patch clamp with
//     temperature control on Patchliner
//
//====================================================


// ------------------------------------------------------------
// Function: Q10_calculator
// Purpose : Calculates Q10 temperature coefficients for each
//           cell in the Include table across temperature intervals.
// Inputs  : TempC      - 1D wave of temperatures (°C)
//           Include    - text wave: [][0]=wave name, [][1]=exclusion code (0=include)
//           col_index  - column index in data waves to analyze
// Outputs : Wave Q10_cells (nCells x nPairs)
// ------------------------------------------------------------
Function Q10_calculator(TempC, Include, col_index)
    Wave TempC
    Wave/T Include
    Variable col_index

    Variable nCells = DimSize(Include, 0)
    Variable nT     = DimSize(TempC, 0)
    Variable nPairs = nT - 1

    Variable i, p, Ti, Tj, Ai, Aj, Q10
    Variable useCell
    String wName

    // Output wave: rows = T intervals, columns = cells
    Make/O/N=(nCells, nPairs) Q10_cells
    Q10_cells = NaN

    for (i = 0; i < nCells; i += 1)

        useCell = str2num(Include[i][1])
        wName   = Include[i][0]

        if (useCell != 0)
            LogWarn("Q10: skipping cell: " + wName + " reason: " + num2str(useCell))
            continue
        endif

        Wave w = $wName
        LogInfo("Q10: processing: " + wName)

        // Calculate Q10 for each temperature interval
        for (p = 0; p < nPairs; p += 1)
            Ti = TempC[p]
            Tj = TempC[p+1]
            Ai = w[p][col_index]
            Aj = w[p+1][col_index]

            if (Ai > 0 && Aj > 0)
                Q10 = (Aj/Ai)^(10/(Tj - Ti))
                Q10_cells[i][p] = Q10
            else
                Q10_cells[i][p] = NaN
            endif
        endfor

    endfor

End


// ------------------------------------------------------------
// Function: Arrhenius_calculator
// Purpose : Fits an Arrhenius model (ln(A) vs 1/T) for each
//           cell to extract activation energy (Ea) and R².
// Inputs  : TempC     - 1D wave of temperatures (°C)
//           Include   - text wave: [][0]=wave name, [][1]=exclusion code (0=include)
//           col_index - column index in data waves to analyze
// Outputs : Waves Ea_kJmol, R2_cells, slope_b, intercept_a
// Notes   : Ea (kJ/mol) = -slope * R; R = 8.314 J/(mol·K)
//           Fit range is hardcoded to indices [2,4] — review
//           before applying to datasets with different T ranges.
// ------------------------------------------------------------
Function Arrhenius_calculator(TempC, Include, col_index)
    Wave TempC
    Wave/T Include
    Variable col_index

    Variable nCells = DimSize(Include, 0)
    Variable nT     = DimSize(TempC, 0)

    Make/O/N=(nT) Tk, invTk
    Tk    = TempC + 273.15
    invTk = 1 / Tk

    Make/O/N=(nCells) Ea_kJmol, R2_cells, slope_b, intercept_a
    Ea_kJmol    = NaN
    R2_cells    = NaN
    slope_b     = NaN
    intercept_a = NaN

    Make/O/N=(nT) lnA, fitWave
    Make/O/N=2 coeff

    Variable i, j, nValid
    Variable R = 8.314
    Variable reason, ymean, SS_tot, SS_res
    String wName, out_wname

    for (i = 0; i < nCells; i += 1)

        reason = str2num(Include[i][1])
        wName  = Include[i][0]

        if (reason != 0)
            LogWarn("Skipping cell: " + wName + " reason: " + num2str(reason))
            continue
        endif

        Wave w = $wName

        // Build lnA wave, marking invalid points as NaN
        for (j = 0; j < nT; j += 1)
            if (numtype(w[j]) == 0 && w[j] > 0)
                lnA[j] = ln(w[j][col_index])
            else
                lnA[j] = NaN
            endif
        endfor

        // Count valid points
        nValid = 0
        for (j = 0; j < nT; j += 1)
            if (numtype(lnA[j]) == 0)
                nValid += 1
            endif
        endfor

        if (nValid < 3)
            LogWarn("Arrhenius: " + wName + " insufficient valid points (" + num2str(nValid) + ")")
            continue
        endif

        out_wname = "ln_" + wName
        Make/O/N=(nT) $out_wname = lnA

        // Linear fit (CurveFit ignores NaNs)
        // TODO: replace hardcoded index range [2,4] with dynamic range
        CurveFit/Q line, lnA[2,4] /X=invTk[2,4] /D=fitWave
        Wave W_coef
        intercept_a[i] = W_coef[0]
        slope_b[i]     = W_coef[1]
        Ea_kJmol[i]    = -W_coef[1] * R / 1000    // Ea (kJ/mol) = -slope * R; R = 8.314 J/(mol·K)

        // Calculate R² using valid points only
        ymean = 0
        for (j = 0; j < nT; j += 1)
            if (numtype(lnA[j]) == 0)
                ymean += lnA[j]
            endif
        endfor
        ymean /= nValid

        SS_tot = 0
        SS_res = 0
        for (j = 0; j < nT; j += 1)
            if (numtype(lnA[j]) == 0 && numtype(fitWave[j]) == 0)
                SS_tot += (lnA[j] - ymean)^2
                SS_res += (lnA[j] - fitWave[j])^2
            endif
        endfor

        if (SS_tot > 0)
            R2_cells[i] = 1 - SS_res/SS_tot
        else
            R2_cells[i] = NaN
        endif

        LogInfo("Arrhenius: " + wName + " Ea(kJ/mol)=" + num2str(Ea_kJmol[i]) + " R2=" + num2str(R2_cells[i]))

    endfor
    KillWaves/Z lnA, fitWave, coeff, Tk, invTk

End
