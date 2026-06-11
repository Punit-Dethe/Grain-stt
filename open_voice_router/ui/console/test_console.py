"""Test launcher for the new Console UI.

This script launches the modular console window standalone for testing.
Run: python -m open_voice_router.ui.console.test_console
"""

import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication

from open_voice_router.ui.console.console_viewmodel import ConsoleViewModel


def main():
    """Launch the console window for testing."""
    print("Starting Grain Console...")
    
    app = QApplication(sys.argv)
    app.setApplicationName("Grain Console")
    app.setOrganizationName("Grain")
    
    print("Creating view model...")
    # Create view model
    view_model = ConsoleViewModel()
    
    print("Setting up QML engine...")
    # Set up QML engine
    engine = QQmlApplicationEngine()
    
    # Expose console view model to QML
    engine.rootContext().setContextProperty("consoleViewModel", view_model)
    
    # Load the console window
    console_qml = Path(__file__).parent / "ConsoleWindow.qml"
    print(f"Loading QML from: {console_qml}")
    
    engine.load(QUrl.fromLocalFile(str(console_qml)))
    
    if not engine.rootObjects():
        print("ERROR: Failed to load ConsoleWindow.qml")
        print("Root objects:", engine.rootObjects())
        return 1
    
    print("Console window loaded successfully!")
    print("Window should be visible now...")
    
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
