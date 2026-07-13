#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3

//====================================================
//   NEUROMATIC EXPORT
//====================================================
//
// Exports Patchliner data to NeuroMatic-compatible folder
// structure inside Igor's local memory.
//
// Entry point : ExportChannelToNM()
// Helpers     : NMExport_CopyWaves(), NMExport_InitFolder()
// Shared utils : ListSubfolders() (Analysis_Utils.ipf)
//
// Folder mapping (one NM folder per experiment):
//   chan_1/exp_Y/Trace/ → NM channel A  ({prefix}A0, A1, ...)
//   chan_2/exp_Y/Trace/ → NM channel B  ({prefix}B0, B1, ...)
//   chan_3/exp_Y/Trace/ → NM channel C  ({prefix}C0, C1, ...)
//   chan_4/exp_Y/Trace/ → NM channel D  ({prefix}D0, D1, ...)
//
// Stimulus export is pending — requires reconstruction of the
// voltage command waveform from _Amp/_Dur segment pairs.
//
// All waves are COPIED — source folder structure is preserved.
// Experiments within each channel are sorted alphabetically
// so sequence numbers are stable across runs.
//
// References:
//   Rothman & Silver 2018 Front. Neuroinformatics — NeuroMatic
//   Wave naming convention: {prefix}{chanLetter}{seqNum}
//====================================================


// ------------------------------------------------------------
// Function: ExportChannelToNM
// Purpose : Entry point. Exports all chan_X folders from the
//           current data folder into a single NeuroMatic-
//           compatible folder at root level.
//           chan_1 → NM channel A, chan_2 → B, etc.
// Inputs  : Operates on the currently active data folder.
//           No user prompt — all channels exported automatically.
// Outputs : New NM folder at root: nm_{expName}
// Notes   : Resolves Wave_prefix from Packages subfolder of
//           the current folder (R1 convention).
//           Channel letter assigned by sort order of chan_X
//           folder names (alphabetical).
//           Calls NMExport_InitFolder() and NMExport_CopyWaves().
// ------------------------------------------------------------
Function ExportChannelToNM()

    String current_folder = GetDataFolder(1)

    // Resolve Wave_prefix from Packages subfolder
    String pkg_path = current_folder + "Packages:Wave_prefix"
    SVAR/Z w_prefix = $pkg_path
    if (!SVAR_Exists(w_prefix))
        LogError("ExportChannelToNM: Wave_prefix not found in " + pkg_path)
        return 0
    endif
    String nm_prefix = w_prefix

    // Build sorted list of chan_X subfolders
    String chan_list = ListSubfolders(current_folder, "chan_")
    chan_list = SortList(chan_list, ";", 16)    // alphabetical → stable letter assignment
    Variable nChans = ItemsInList(chan_list)
    if (nChans == 0)
        LogError("ExportChannelToNM: no chan_X folders found in " + current_folder)
        return 0
    endif

    // NM supports up to 26 channels — warn if exceeded
    if (nChans > 26)
        LogError("ExportChannelToNM: too many channels (" + num2str(nChans) + "), max 26.")
        return 0
    endif

    // Build NM destination folder name: nm_{expName}
    String exp_name  = FolderNameFromPath(RemoveEnding(current_folder, ":"))
    String nm_folder = "root:nm_" + exp_name

    // Create NM folder with one ChanX subfolder per Patchliner channel
    NMExport_InitFolder(nm_folder, nm_prefix, nChans)

    // Export each chan_X into its corresponding NM channel letter
    // chan letter = A + i via num2char/char2num (cross-platform)
    Variable i
    for (i = 0; i < nChans; i += 1)
        String chan_name   = StringFromList(i, chan_list)
        String chan_path   = current_folder + chan_name + ":"
        String chan_letter = num2char(char2num("A") + i)

        Variable nWaves = NMExport_CopyWaves(chan_path, nm_folder, nm_prefix, "Trace", chan_letter)
        LogInfo("ExportChannelToNM: " + chan_name + " → Chan" + chan_letter + \
                " (" + num2str(nWaves) + " waves)")
    endfor

    LogInfo("ExportChannelToNM: done → " + nm_folder)
    // TODO: export reconstructed voltage command as additional NM channel
    //   requires NMExport_ReconstructStim() from _Amp/_Dur segment pairs

    SetDataFolder current_folder
End


// ------------------------------------------------------------
// Function: NMExport_InitFolder
// Purpose : Creates a NeuroMatic-compatible data folder with
//           the minimum required variables and subfolders.
// Inputs  : nm_folder - full path to new NM folder (root:nm_...)
//           nm_prefix - wave prefix string
//           nChans    - number of channels to create (1–26)
// Outputs : none (side-effect: folder structure created at root)
// Notes   : Minimum NM requirements per Rothman & Silver 2018:
//             - String variable CurrentPrefix = nm_prefix
//             - Subfolder NMPrefix_{prefix}
//             - Subfolder NMPrefix_{prefix}:Chan{X} per channel
//           If the folder already exists it is killed and
//           recreated to avoid stale wave references.
// ------------------------------------------------------------
Function NMExport_InitFolder(nm_folder, nm_prefix, nChans)
    String nm_folder, nm_prefix
    Variable nChans

    // Kill and recreate if exists to avoid stale contents
    if (DataFolderExists(nm_folder))
        LogWarn("NMExport_InitFolder: folder exists, overwriting: " + nm_folder)
        KillDataFolder/Z $nm_folder
    endif
    NewDataFolder/O $nm_folder

    // Required NM string variable: CurrentPrefix
    String/G $(nm_folder + ":CurrentPrefix") = nm_prefix

    // Required NM subfolder: NMPrefix_{prefix}
    String prefix_df = nm_folder + ":NMPrefix_" + nm_prefix
    NewDataFolder/O $prefix_df

    // One ChanX subfolder per Patchliner channel
    Variable i
    for (i = 0; i < nChans; i += 1)
        String chan_letter = num2char(char2num("A") + i)
        NewDataFolder/O $(prefix_df + ":Chan" + chan_letter)
    endfor

    LogInfo("NMExport_InitFolder: created " + nm_folder + " with " + num2str(nChans) + " channels")
End


// ------------------------------------------------------------
// Function: NMExport_CopyWaves
// Purpose : Copies waves from all exp_Y subfolders of a chan_X
//           folder into an NM destination folder, renaming them
//           to the NM convention: {prefix}{chanLetter}{seqNum}.
// Inputs  : chan_path   - full path to chan_X folder (with ":")
//           nm_folder   - full path to destination NM folder
//           nm_prefix   - wave prefix string
//           src_type    - "Trace", "Stim_Amp", or "Stim_Dur"
//           chan_letter  - NM channel letter ("A", "B", "C", "D")
// Outputs : total number of waves copied (Variable)
// Notes   : Experiments are sorted alphabetically before copying
//           so sequence numbers are stable across runs.
//           Wave scale (x-axis) is preserved from the source.
//           Uses Duplicate/O — source waves are not moved.
//           Stim_Amp / Stim_Dur support retained for future use
//           when voltage command reconstruction is implemented.
// ------------------------------------------------------------
Function NMExport_CopyWaves(chan_path, nm_folder, nm_prefix, src_type, chan_letter)
    String chan_path, nm_folder, nm_prefix, src_type, chan_letter

    // Build sorted experiment list
    String exp_list = ListSubfolders(chan_path, "exp_")
    exp_list = SortList(exp_list, ";", 16)    // 16 = alphabetical ascending
    Variable nExp = ItemsInList(exp_list)
    if (nExp == 0)
        LogWarn("NMExport_CopyWaves: no exp_X folders in " + chan_path)
        return 0
    endif

    Variable seq = 0    // global sequence counter — continuous across experiments
    Variable i, j

    for (i = 0; i < nExp; i += 1)

        String exp_name = StringFromList(i, exp_list)
        String exp_path = chan_path + exp_name + ":"

        // Resolve source subfolder and wave pattern from src_type
        String src_folder, wave_pattern
        strswitch(src_type)
            case "Trace":
                src_folder   = exp_path + "Trace:"
                wave_pattern = "*"
                break
            case "Stim_Amp":
                src_folder   = exp_path + "Stim:"
                wave_pattern = "*_Amp"
                break
            case "Stim_Dur":
                src_folder   = exp_path + "Stim:"
                wave_pattern = "*_Dur"
                break
            default:
                LogError("NMExport_CopyWaves: unknown src_type: " + src_type)
                return 0
        endswitch

        if (!DataFolderExists(RemoveEnding(src_folder, ":")))
            LogWarn("NMExport_CopyWaves: folder not found, skipping: " + src_folder)
            continue
        endif

        SetDataFolder src_folder
        String wave_list = WaveList(wave_pattern, ";", "")
        wave_list = SortList(wave_list, ";", 16)    // stable sort within experiment
        Variable nWaves = ItemsInList(wave_list)

        for (j = 0; j < nWaves; j += 1)
            String src_name  = StringFromList(j, wave_list)
            String dest_name = nm_prefix + chan_letter + num2str(seq)
            String dest_path = nm_folder + ":" + dest_name

            Wave src_w = $(src_folder + src_name)
            Duplicate/O src_w, $dest_path

            LogInfo("NMExport_CopyWaves: " + src_name + " → " + dest_name)
            seq += 1
        endfor

    endfor

    SetDataFolder $chan_path
    return seq
End
