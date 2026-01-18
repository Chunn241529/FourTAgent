import sys
from PySide6.QtWidgets import (
    QApplication,
    QScrollArea,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)
from PySide6.QtCore import Qt, QEvent


class MyTextBrowser(QTextBrowser):
    def wheelEvent(self, event):
        print("MyTextBrowser received wheelEvent")
        super().wheelEvent(event)


class MyScrollArea(QScrollArea):
    def wheelEvent(self, event):
        print("MyScrollArea received wheelEvent")
        super().wheelEvent(event)


def test_event_propagation():
    app = QApplication(sys.argv)

    scroll_area = MyScrollArea()
    scroll_area.resize(300, 200)

    text_browser = MyTextBrowser()
    text_browser.setText("Line 1\n" * 20 + "Very long line " * 20)
    # text_browser.setLineWrapMode(QTextBrowser.NoWrap) # Ensure horizontal scroll is possible

    scroll_area.setWidget(text_browser)
    scroll_area.setWidgetResizable(True)

    scroll_area.show()

    print("Please scroll over the text browser window...")

    # We can also simulate event
    from PySide6.QtGui import QWheelEvent
    from PySide6.QtCore import QPoint

    event = QWheelEvent(
        QPoint(100, 100),
        QPoint(100, 100),
        QPoint(0, 0),
        QPoint(0, -120),
        Qt.NoButton,
        Qt.ShiftModifier,
        Qt.NoScrollPhase,
        False,
    )

    print("Simulating Shift+Scroll on TextBrowser viewport...")
    QApplication.sendEvent(text_browser.viewport(), event)

    # app.exec()


if __name__ == "__main__":
    test_event_propagation()
