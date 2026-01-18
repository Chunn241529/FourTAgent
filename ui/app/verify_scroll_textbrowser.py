import sys
from PySide6.QtWidgets import QApplication, QScrollArea, QVBoxLayout, QWidget
from PySide6.QtCore import Qt, QPoint, QEvent
from PySide6.QtGui import QWheelEvent
from ui_components import HorizontalScrollTextBrowser


def test_horizontal_scroll_textbrowser():
    app = QApplication(sys.argv)

    # Create the text browser
    text_browser = HorizontalScrollTextBrowser(None)
    text_browser.resize(200, 200)

    # Add wide content
    text_browser.setLineWrapMode(HorizontalScrollTextBrowser.NoWrap)
    text_browser.setText("Very long line " * 50)

    text_browser.show()

    # Set initial scroll value
    h_bar = text_browser.horizontalScrollBar()
    h_bar.setValue(100)
    initial_value = h_bar.value()
    print(f"Initial horizontal scroll value: {initial_value}")

    # Simulate Shift + Scroll
    angle_delta = QPoint(0, -120)
    pixel_delta = QPoint(0, -120)

    event = QWheelEvent(
        QPoint(100, 100),
        QPoint(100, 100),
        pixel_delta,
        angle_delta,
        Qt.NoButton,
        Qt.ShiftModifier,
        Qt.NoScrollPhase,
        False,
    )

    # Send event to viewport (since it's a scroll area internally)
    QApplication.sendEvent(text_browser.viewport(), event)

    final_value = h_bar.value()
    print(f"Final horizontal scroll value: {final_value}")

    if final_value > initial_value:
        print("SUCCESS: Horizontal scroll value increased (scrolled right).")
    else:
        print("FAILURE: Horizontal scroll value did not increase.")

    text_browser.close()


if __name__ == "__main__":
    test_horizontal_scroll_textbrowser()
