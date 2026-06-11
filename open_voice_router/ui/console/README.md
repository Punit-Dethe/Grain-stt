# Grain Console UI

A modular Eurorack-inspired console interface for the Grain STT application.

## Overview

This is a **completely separate UI** from the existing `SettingsWindow`. It lives alongside the original UI as an alternative interface, keeping the original settings window intact as a backup.

## Architecture

### Directory Structure

```
console/
├── __init__.py                    # Package exports
├── console_viewmodel.py           # View model (inherits from SettingsViewModel)
├── ConsoleWindow.qml              # Main window with header, modules, drawer
├── ModuleA.qml                    # Configuration module
├── ModuleB.qml                    # Transcription module  
├── ModuleC.qml                    # Processing module
├── Jack.qml                       # Eurorack-style jack socket component
├── MechanicalToggle.qml           # Hardware-style toggle switch
├── KnurledDial.qml                # Rotary knob control
├── DotMatrixDisplay.qml           # Animated LED matrix display
├── ConfigurationPanel.qml         # Drawer panel for Module A
├── TranscriptionPanel.qml         # Drawer panel for Module B
├── ProcessingPanel.qml            # Drawer panel for Module C
├── test_console.py                # Standalone test launcher
└── README.md                      # This file
```

### Design Features

**Hardware-Inspired Aesthetic:**
- Travertine (#ECE5DA) module surfaces with metal-grain texture
- Dark carbon pocket (#0c0b0a) inset areas for controls
- Three signal colors: orange (#FF5D1E), green (#10B981), purple (#8B5CF6)
- Eurorack-style jack sockets with pulsing active indicators
- Mechanical toggle switches with smooth animations
- Knurled rotary dials for precise value adjustment
- Animated dot matrix LED display

**Three Modular Sections:**
- **Module A (Configuration):** Hotkeys, microphone, system settings
- **Module B (Transcription):** STT provider selection, routing, real-time settings
- **Module C (Processing):** LLM provider selection, prompt management

**Sliding Tablet Drawer:**
- Slides up from bottom when module navigation buttons are clicked
- Contains detailed configuration panels for each module
- Modules compress (hide-on-squish) when drawer is open

## Backend Integration

The console uses `ConsoleViewModel`, which **inherits directly from `SettingsViewModel`**. This means:

✅ **Same backend:** Uses the exact same settings storage and business logic  
✅ **Same data:** Reads and writes to the same settings files  
✅ **No duplication:** No need to maintain separate backend code  
✅ **Full compatibility:** Works with all existing providers, prompts, and configurations

## Testing

To test the console UI standalone:

```bash
cd "c:\Projects\Grain STT"
python -m open_voice_router.ui.console.test_console
```

This launches just the console window with a fully functional backend.

## Integration with Main Application

To integrate the console into the main application:

### Option 1: Replace SettingsWindow (main.py)

```python
# In main.py, replace:
from open_voice_router.ui.settings import SettingsViewModel, SettingsWindow

# With:
from open_voice_router.ui.console import ConsoleViewModel
from open_voice_router.ui.console.ConsoleWindow import ConsoleWindow  # If needed

# Then use consoleViewModel instead of settingsViewModel
```

### Option 2: Add as Alternative Window

Keep both UIs available and let users choose:

```python
from open_voice_router.ui.settings import SettingsViewModel
from open_voice_router.ui.console import ConsoleViewModel

# Expose both to QML or create menu to switch between them
```

## Current Limitations

This initial version includes:

✅ Full UI layout with all three modules  
✅ Animated components (dot matrix, toggles, dials, jacks)  
✅ Sliding tablet drawer with three panels  
✅ Backend integration through ConsoleViewModel  
✅ Responsive layout with hide-on-squish animations  

Still placeholder/future work:

⏳ Patch cable drawing between jacks (canvas rendering)  
⏳ Full provider CRUD in drawer panels (currently shown in original settings)  
⏳ Full prompt management in drawer (currently shown in original settings)  
⏳ Live microphone device enumeration  
⏳ Real backend integration for local STT/LLM model management  

The console is **fully functional** for viewing and editing basic settings (hotkeys, toggles, selections). For advanced operations like adding providers or editing prompts, users can fall back to the original `SettingsWindow`.

## Design Philosophy

**Hardware-Inspired UX:**
The interface mimics physical modular synthesizer panels, making digital controls feel tactile and immediate. Visual signal routing (jacks and cables) helps users understand the data flow conceptually.

**Separation of Concerns:**
- Original `SettingsWindow` remains unchanged as a stable fallback
- New console UI can be developed and tested independently
- Same backend ensures data consistency

**Progressive Enhancement:**
Start with the core UI and working interactions, then progressively add advanced features like provider/prompt management directly in the console.

## Credits

Design inspired by Eurorack modular synthesizers and the HTML prototype `grain_modular_console(2).html`.
