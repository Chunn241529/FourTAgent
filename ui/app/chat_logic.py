# chat_logic.py
# -*- coding: utf-8 -*-
import markdown
import json
from urllib.parse import urlparse
from typing import Optional
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QTextCursor
from PySide6.QtWidgets import QTextEdit
from worker import OllamaWorker
from screenshot_capture import ScreenshotOverlay


class ChatLogic:
    def __init__(self, parent):
        self.parent = parent
        self.ollama_thread: Optional[OllamaWorker] = None
        self.chunk_buffer = ""
        self.thinking_buffer = ""
        self.full_thinking_md = ""
        self.buffer_timer = QTimer()
        self.buffer_timer.setInterval(
            30
        )  # Increased from 5ms to 30ms to reduce CPU usage
        self.buffer_timer.timeout.connect(self._flush_buffer)
        self.parent.user_scrolling = False
        self.last_resize_time = 0
        self.resize_throttle_ms = 100  # Throttle resizing to every 100ms
        self.scroll_animation = None  # Animation for smooth scrolling

    def setup_connections(self) -> None:
        self.parent.ui.send_stop_button.send_clicked.connect(self.send_prompt)
        self.parent.ui.send_stop_button.stop_clicked.connect(self.stop_worker)

    def handle_key_press(self, event) -> None:
        if event.key() == Qt.Key_Return and not event.modifiers() & Qt.ShiftModifier:
            event.accept()
            if self.ollama_thread and self.ollama_thread.isRunning():
                print("Worker is running, ignoring new prompt")
                return
            self.send_prompt()
        else:
            QTextEdit.keyPressEvent(self.parent.ui.input_box, event)

    def send_prompt(self) -> None:
        prompt_text = self.parent.ui.input_box.toPlainText().strip()
        if not prompt_text:
            print("Prompt is empty, ignoring")
            return

        # Handle commands
        if prompt_text.startswith("/"):
            # REMOVED: /deepsearch now works as a tool, not a command
            self.handle_command(prompt_text)
            self.parent.ui.input_box.clear()
            return

        print(f"Sending prompt: {prompt_text}")
        self.parent.ui.scroll_area.setVisible(True)
        self.parent.ui.input_box.setDisabled(True)
        self.parent.full_response_md = ""
        self.full_thinking_md = ""
        self.chunk_buffer = ""
        self.thinking_buffer = ""
        self.parent.ui.response_display.clear()
        self.parent.ui.thinking_display.clear()
        self.parent.ui.thinking_widget.hide()
        self.parent.ui.input_box.setPlaceholderText("AI đang suy nghĩ...")
        self.parent.user_scrolling = False
        self.parent.sources_data = []
        self.parent.waiting_for_response = True
        self.parent.spinner_logic.start_thinking()
        self.parent.ui.send_stop_button.set_running(True)

        image_base64 = self.parent.current_screenshot_base64

        # Clear the screenshot preview after capturing the data
        if image_base64:
            self.parent.ui.delete_screenshot()

        if self.ollama_thread:
            if self.ollama_thread.isRunning():
                print("Waiting for previous thread to finish")
                self.ollama_thread.quit()
                self.ollama_thread.wait()
            self.ollama_thread.deleteLater()
            self.ollama_thread = None

        token = self.parent.token
        # Pass conversation_id if available
        conversation_id = getattr(self.parent, "conversation_id", None)

        # Note: We need to update OllamaWorker to accept conversation_id if we want to continue chat
        # For now, let's assume the backend handles it or we need to pass it.
        # Since OllamaWorker doesn't take conversation_id in __init__ yet, we might need to update it too
        # or just rely on the fact that we are sending a new request.
        # Wait, the backend /send endpoint takes conversation_id.
        # We should update OllamaWorker to accept conversation_id.

        self.ollama_thread = OllamaWorker(
            prompt_text,
            token=token,
            image_base64=image_base64,
            is_thinking=True,
            conversation_id=conversation_id,
        )
        # Inject conversation_id into worker if needed, or update worker init.
        # For this step, let's just stick to command logic.

        self.ollama_thread.chunk_received.connect(self._buffer_chunk)
        self.ollama_thread.thinking_received.connect(self._buffer_thinking)
        self.ollama_thread.search_started.connect(self.on_search_started)
        self.ollama_thread.search_complete.connect(self.on_search_complete)
        self.ollama_thread.search_sources.connect(self.on_search_sources)
        self.ollama_thread.content_started.connect(self.on_content_started)
        self.ollama_thread.image_processing.connect(self.on_image_processing)
        self.ollama_thread.image_description.connect(self.on_image_description)
        self.ollama_thread.error_received.connect(self.handle_error)
        self.ollama_thread.finished.connect(self.on_generation_finished)
        self.ollama_thread.conversation_id_received.connect(
            self.on_conversation_id_received
        )
        self.ollama_thread.deep_search_received.connect(self.on_deep_search_received)
        self.ollama_thread.start()
        print("OllamaWorker started")

    def on_conversation_id_received(self, conversation_id: int):
        print(f"Received conversation_id: {conversation_id}")
        self.parent.conversation_id = conversation_id

    def handle_command(self, command_text: str):
        parts = command_text.split(" ", 1)
        cmd = parts[0]
        args = parts[1].strip() if len(parts) > 1 else ""

        chat_display = self.parent.ui.response_display

        if cmd == "/help":
            chat_display.clear()
            help_text = """
            <h3>📚 HƯỚNG DẪN SỬ DỤNG Lumina AI</h3>
            <ul>
                <li><b>/new</b>: Bắt đầu cuộc hội thoại mới</li>
                <li><b>/history</b>: Xem lịch sử hội thoại</li>
                <li><b>/load &lt;id&gt;</b>: Tải lại cuộc hội thoại</li>
                <li><b>/file &lt;path&gt;</b>: Đính kèm file</li>
                <li><b>/clearfile</b>: Gỡ file đính kèm</li>
                <li><b>/clear</b>: Xóa màn hình chat</li>
                <li><b>/delete</b>: Xóa cuộc hội thoại hiện tại</li>
                <li><b>/delete_all</b>: Xóa tất cả hội thoại</li>
                <li><b>/logout</b>: Đăng xuất</li>
            </ul>
            """
            chat_display.append(help_text)

        elif cmd == "/clear":
            chat_display.clear()

        elif cmd == "/new":
            self.parent.conversation_id = None
            chat_display.clear()
            chat_display.append("<i>Đã bắt đầu cuộc hội thoại mới.</i>")

        elif cmd == "/logout":
            import os
            import sys  # Added import for sys

            if os.path.exists("token.txt"):
                os.remove("token.txt")
            sys.exit(0)

        elif cmd == "/file":
            import os  # Added import for os

            if os.path.exists(args):
                # Logic to attach file (needs implementation in parent or here)
                # For now just show message
                chat_display.append(
                    f"<i>Đã đính kèm file: {args} (Chưa hỗ trợ gửi file qua command này trong UI)</i>"
                )
            else:
                chat_display.append(
                    f"<span style='color:red'>File không tồn tại: {args}</span>"
                )

        elif cmd == "/history":
            chat_display.clear()
            self.start_command_worker("history")

        elif cmd == "/load":
            chat_display.clear()
            if args.isdigit():
                self.start_command_worker("load", conversation_id=int(args))
            else:
                chat_display.append("<span style='color:red'>ID không hợp lệ.</span>")

        elif cmd == "/delete":
            if getattr(self.parent, "conversation_id", None):
                self.start_command_worker(
                    "delete", conversation_id=self.parent.conversation_id
                )
            else:
                chat_display.append(
                    "<span style='color:yellow'>Chưa có cuộc hội thoại nào để xóa.</span>"
                )

        elif cmd == "/delete_all":
            self.start_command_worker("delete_all")

        elif cmd == "/deepsearch":
            if not args:
                chat_display.append(
                    "<span style='color:yellow'>Vui lòng nhập chủ đề: /deepsearch &lt;topic&gt;</span>"
                )
            else:
                # Send as a regular prompt but with /deepsearch prefix, which the backend now handles
                # We need to bypass the command handling and send it via send_prompt logic
                # But send_prompt reads from input_box.
                # So we can just let it fall through if we didn't clear input_box?
                # Actually, handle_command is called from send_prompt.
                # If we return here, send_prompt continues? No, send_prompt returns after handle_command if it was a command.

                # We want to treat this as a message sent to backend, but maybe with special UI state?
                # For now, let's just send it.

                # We need to set the input box text back to the full command so send_prompt can send it?
                # Or better, just call the worker directly or modify send_prompt to not treat /deepsearch as a client-side command only.

                # Let's change how send_prompt handles commands.
                # If it's /deepsearch, we want to proceed to sending it to backend.
                pass  # Fall through to "Lệnh không xác định" is not what we want.

                # Actually, the cleanest way is to NOT handle /deepsearch here if we want it to go to backend.
                # But we want to show help for it.

                # Let's modify send_prompt to check for /deepsearch specifically and NOT call handle_command,
                # OR, we can just send it from here.

                # But send_prompt logic sets up UI state (spinner, etc).
                # So, let's remove /deepsearch from here and let it pass through?
                # But send_prompt checks `if prompt_text.startswith("/"): handle_command... return`

                # So we MUST handle it here or change send_prompt.
                # Let's change send_prompt to allow /deepsearch to pass through.
                pass

        else:
            chat_display.append(
                f"<span style='color:yellow'>Lệnh không xác định: {cmd}</span>"
            )

        # Maximize height for commands
        self.parent.ui.adjust_window_height(staged=False)

    def start_command_worker(self, command, **kwargs):
        from command_worker import CommandWorker

        if (
            hasattr(self, "cmd_worker")
            and self.cmd_worker
            and self.cmd_worker.isRunning()
        ):
            self.cmd_worker.quit()
            self.cmd_worker.wait()

        token = self.parent.token
        base_url = (
            # "https://living-tortoise-polite.ngrok-free.app"  # ngrok disabled
            "https://api.fourt.io.vn"  # Production URL
        )

        self.cmd_worker = CommandWorker(command, base_url, token, **kwargs)
        self.cmd_worker.result_ready.connect(self.handle_command_result)
        self.cmd_worker.error_occurred.connect(self.handle_command_error)
        self.cmd_worker.start()

    def handle_command_result(self, result):
        chat_display = self.parent.ui.response_display

        if result["type"] == "history":
            data = result["data"]
            if not data:
                chat_display.append("<i>Chưa có cuộc hội thoại nào.</i>")
            else:
                html = "<b>Danh sách cuộc hội thoại:</b><br>"
                for conv in data:
                    html += f"- ID: {conv['id']} (Tạo lúc: {conv['created_at']})<br>"
                chat_display.append(html)

        elif result["type"] == "load":
            data = result["data"]
            conv_id = result["conversation_id"]
            self.parent.conversation_id = conv_id
            chat_display.clear()
            chat_display.append(f"<i>Đang xem cuộc hội thoại #{conv_id}</i><br>")
            for msg in data:
                role = msg.get("role", "unknown")
                content = msg.get("content", "")
                thinking = msg.get("thinking", "")
                tool_calls = msg.get("tool_calls", [])
                code_executions = msg.get("code_executions", [])
                generated_images = msg.get("generated_images", [])

                print(f"Loading message: role={role}, content_length={len(content)}")

                if role == "user":
                    chat_display.append(
                        f"<br><div style='color: #4ec9b0; margin-top: 10px;'><b>👤 Bạn:</b> {content}</div><br>"
                    )
                elif role == "assistant" or role == "tool":
                    header = (
                        "🤖 <b>Lumin AI:</b><br>"
                        if role == "assistant"
                        else "🔧 <b>Tool:</b><br>"
                    )
                    chat_display.append(header)

                    # 1. Render Thinking
                    if thinking:
                        thinking_html = markdown.markdown(
                            thinking, extensions=["fenced_code", "tables", "codehilite"]
                        )
                        chat_display.append(
                            f"<div style='margin-left: 10px; border-left: 3px solid #858585; padding-left: 10px; color: #858585; font-size: 13px;'>"
                            f"<i>🤔 Suy nghĩ:</i><br>{thinking_html}</div><br>"
                        )

                    # 2. Render Tool Calls
                    if tool_calls and isinstance(tool_calls, list):
                        for tc in tool_calls:
                            func = tc.get("function", {})
                            name = func.get("name", "Unknown Tool")
                            args = func.get("arguments", "{}")

                            # Custom styling for common tools
                            emoji = "🔧"
                            if name == "web_search":
                                emoji = "🔍"
                            elif "file" in name:
                                emoji = "📄"
                            elif "canvas" in name:
                                emoji = "🎨"
                            elif "music" in name:
                                emoji = "🎵"

                            chat_display.append(
                                f"<div style='background: #252526; padding: 10px; border-radius: 8px; border: 1px solid #3e3e42; margin-bottom: 5px; color: #4ec9b0;'>"
                                f"<b>{emoji} Đã sử dụng {name}</b><br>"
                                f"<span style='color: #ce9178; font-family: monospace; font-size: 12px;'>{args}</span>"
                                f"</div>"
                            )

                    # 3. Render Code Executions
                    if code_executions and isinstance(code_executions, list):
                        for ce in code_executions:
                            code = ce.get("code", "")
                            out = ce.get("output", "")
                            chat_display.append(
                                f"<div style='background: #1e1e1e; padding: 10px; border-radius: 8px; border: 1px solid #333; margin-bottom: 5px;'>"
                                f"<b style='color: #dcdcaa;'>📟 Code Execution:</b><br>"
                                f"<pre style='color: #9cdcfe;'>{code}</pre>"
                                f"<b style='color: #4ec9b0;'>&gt; Kết quả:</b><br>"
                                f"<pre style='color: #ce9178;'>{out}</pre>"
                                f"</div>"
                            )

                    # 4. Render Markdown Content
                    if content:
                        html_content = markdown.markdown(
                            content, extensions=["fenced_code", "tables", "codehilite"]
                        )
                        chat_display.append(
                            f"<div style='padding: 5px 0;'>{html_content}</div>"
                        )

                    # 5. Render Images
                    if generated_images and isinstance(generated_images, list):
                        for img_base64 in generated_images:
                            chat_display.append(
                                f"<div style='margin-top: 10px;'><img src='data:image/jpeg;base64,{img_base64}' width='300'></div><br>"
                            )
                else:
                    # Fallback
                    html_content = markdown.markdown(
                        content, extensions=["fenced_code", "tables", "codehilite"]
                    )
                    chat_display.append(f"{html_content}<br>")

        elif result["type"] == "delete":
            self.parent.conversation_id = None
            chat_display.clear()
            chat_display.append("<i>Đã xóa cuộc hội thoại hiện tại.</i>")

        elif result["type"] == "delete_all":
            self.parent.conversation_id = None
            chat_display.clear()
            chat_display.append("<i>Đã xóa tất cả cuộc hội thoại.</i>")

        # Maximize height after command result
        self.parent.ui.adjust_window_height(staged=False)

    def handle_command_error(self, error_msg):
        self.parent.ui.response_display.append(
            f"<span style='color:red'>{error_msg}</span>"
        )

    def stop_worker(self):
        if self.ollama_thread and self.ollama_thread.isRunning():
            print("Stopping OllamaWorker")
            self.ollama_thread.stop()
            self.ollama_thread.wait()
            self.ollama_thread.deleteLater()
            self.ollama_thread = None
        self.parent.waiting_for_response = False
        self.parent.ui.send_stop_button.set_running(False)
        self.parent.spinner_logic.reset_to_idle()
        self.parent.ui.input_box.setEnabled(True)
        self.parent.ui.input_box.setPlaceholderText("Nhập tin nhắn hoặc /help...")
        self.parent.ui.thinking_widget.hide()
        self.parent.ui.response_display.append("\n[Đã dừng phản hồi]")

    def extract_image_from_input(self):
        return None

    def _buffer_chunk(self, chunk: str) -> None:
        self.chunk_buffer += chunk
        if not self.buffer_timer.isActive():
            self.buffer_timer.start()

    def _buffer_thinking(self, thinking: str) -> None:
        if thinking and thinking.strip():
            # Loại bỏ dòng trống và thêm xuống dòng nếu cần
            thinking = thinking.strip()
            if self.thinking_buffer and not self.thinking_buffer.endswith("\n"):
                self.thinking_buffer += "\n"
            self.thinking_buffer += thinking + "\n"
            if not self.buffer_timer.isActive():
                self.buffer_timer.start()

    def _flush_buffer(self) -> None:
        if not self.chunk_buffer and not self.thinking_buffer:
            return

        self.parent.spinner_logic.start_responding()

        if self.thinking_buffer:
            self.full_thinking_md += self.thinking_buffer
            if self.full_thinking_md.strip():
                self.parent.ui.thinking_widget.show()
                html_content = markdown.markdown(
                    self.full_thinking_md,
                    extensions=["fenced_code", "tables", "codehilite"],
                )
                self.parent.ui.thinking_display.setHtml(
                    f'<div style="padding: 10px;">{html_content}</div>'
                )
                # Cuộn tự động đến cuối
                cursor = self.parent.ui.thinking_display.textCursor()
                cursor.movePosition(QTextCursor.End)
                self.parent.ui.thinking_display.setTextCursor(cursor)
                self.parent.ui.thinking_display.ensureCursorVisible()
                # Chỉ toggle nếu thinking_display chưa mở
                if self.parent.ui.thinking_display.height() == 0:
                    self.parent.ui.toggle_thinking(show_full_content=False)
            else:
                self.parent.ui.thinking_widget.hide()

        if self.chunk_buffer:
            self.parent.full_response_md += self.chunk_buffer
            html_content = markdown.markdown(
                self.parent.full_response_md,
                extensions=["fenced_code", "tables", "codehilite"],
            )
            wrapped_html = f'<div style="padding: 15px 10px;">{html_content}</div>'
            self.parent.ui.response_display.setHtml(wrapped_html)

            if not self.parent.user_scrolling and self.parent.full_response_md:
                cursor = self.parent.ui.response_display.textCursor()
                cursor.movePosition(QTextCursor.End)
                self.parent.ui.response_display.setTextCursor(cursor)
                self.parent.ui.response_display.ensureCursorVisible()

        self.chunk_buffer = ""
        self.thinking_buffer = ""

        # Throttle window resizing during streaming
        import time

        current_time = time.time() * 1000
        if current_time - self.last_resize_time > self.resize_throttle_ms:
            self.parent.ui.adjust_window_height(staged=True)
            self.last_resize_time = current_time

    def on_search_started(self, query: str):
        """Display search started message in-line with conversation"""
        if query:
            # Stop spinner to prevent overlap with search box
            self.parent.spinner_logic._hide_spinner()

            # Check if query already contains a formatted message (e.g., from deep_search)
            if query.startswith("🔬") or query.startswith("🔍"):
                # Already formatted, use as-is
                display_text = query
            else:
                # Format for web_search
                display_text = f"🔍 Đang tìm kiếm: {query.strip()}..."

            # Create HTML box for search status
            search_box_html = (
                f'\n\n<div style="'
                f"background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); "
                f"color: white; "
                f"font-weight: bold; "
                f"padding: 15px 20px; "
                f"border: 1px solid rgba(255, 255, 255, 0.2); "
                f"border-bottom: 4px solid rgba(0, 0, 0, 0.5); "
                f"border-radius: 12px; "
                f"margin: 15px 0; "
                f'font-size: 14px;">'
                f"{display_text}"
                f"</div>\n\n"
            )

            # Append to full_response_md (markdown allows raw HTML)
            self.parent.full_response_md += search_box_html

            # Trigger immediate render
            html_content = markdown.markdown(
                self.parent.full_response_md,
                extensions=["fenced_code", "tables", "codehilite"],
            )
            wrapped_html = f'<div style="padding: 15px 10px;">{html_content}</div>'
            self.parent.ui.response_display.setHtml(wrapped_html)

            # Scroll to bottom
            if not self.parent.user_scrolling:
                cursor = self.parent.ui.response_display.textCursor()
                cursor.movePosition(QTextCursor.End)
                self.parent.ui.response_display.setTextCursor(cursor)
                self.parent.ui.response_display.ensureCursorVisible()

    def on_search_complete(self, data: dict):
        """Called when search completes"""
        # Search status is already in markdown, no action needed
        pass

    def on_search_sources(self, sources_json: str):
        try:
            self.parent.sources_data = json.loads(sources_json)

            # Styled container for search results
            sources_html = (
                '<div style="margin: 15px 0 10px 0; padding: 12px; '
                'background-color: #252526; border-radius: 8px; border: 1px solid #3e3e42;">'
                '<div style="font-weight: bold; color: #4ec9b0; margin-bottom: 8px; '
                'font-size: 13px; font-family: Segoe UI, sans-serif;">'
                "🔍 KẾT QUẢ TÌM KIẾM"
                "</div>"
                '<table style="width: 100%; border-collapse: collapse;">'
            )

            for source in self.parent.sources_data:
                try:
                    domain = urlparse(source["url"]).netloc
                except Exception:
                    domain = "External Link"

                sources_html += (
                    f"<tr><td style='padding: 6px 0; border-bottom: 1px solid #333333;'>"
                    f"<a href='{source['url']}' style='color: #ce9178; text-decoration: none; "
                    f"font-weight: 600; font-size: 13px;'>{source['title']}</a>"
                    f"<div style='font-size: 11px; color: #858585; margin-top: 2px;'>🔗 {domain}</div>"
                    f"</td></tr>"
                )
            sources_html += "</table></div>"

            current_html = self.parent.ui.response_display.toHtml()
            body_start = current_html.find("<body>")
            body_end = current_html.find("</body>")
            if body_start != -1 and body_end != -1:
                body_content = current_html[body_start + 6 : body_end]
                new_html = (
                    current_html[: body_start + 6]
                    + sources_html
                    + body_content
                    + current_html[body_end:]
                )
                self.parent.ui.response_display.setHtml(new_html)
                print("Sources HTML appended")
                if not self.parent.user_scrolling:
                    cursor = self.parent.ui.response_display.textCursor()
                    cursor.movePosition(QTextCursor.End)
                    self.parent.ui.response_display.setTextCursor(cursor)
                    self.parent.ui.response_display.ensureCursorVisible()
            else:
                print("Could not find <body> tags in current HTML")
        except json.JSONDecodeError as e:
            print(f"Error parsing sources JSON: {e}")
        except Exception as e:
            print(f"Error processing sources: {e}")

    def on_deep_search_received(self, data: dict):
        """Handle deep search updates"""
        status = data.get("status")
        message = data.get("message")

        # Show widget if hidden
        if not self.parent.ui.deep_search_widget.isVisible():
            self.parent.ui.deep_search_widget.show()
            self.parent.ui.adjust_window_height(staged=True)

        # # Icons
        # status_icons = {
        #     "started": "🚀",
        #     "searching": "🔍",
        #     "summarizing": "📝",
        #     "reflecting": "🤔",
        #     "planning": "📅",
        #     "synthesizing": "✨",
        #     "info": "ℹ️",
        #     "warning": "⚠️",
        #     "error": "❌",
        # }
        # icon = status_icons.get(status, "🔹")

        # Format HTML
        html_msg = (
            f"<div style='margin-bottom: 5px;'>"
            f"<span style='color: #4ec9b0; font-weight: bold;'>{status}:</span> "
            f"<span style='color: #e0e0e0;'>{message}</span>"
            f"</div>"
        )

        self.parent.ui.deep_search_display.append(html_msg)

        # Scroll to bottom
        cursor = self.parent.ui.deep_search_display.textCursor()
        cursor.movePosition(QTextCursor.End)
        self.parent.ui.deep_search_display.setTextCursor(cursor)

    def on_content_started(self):
        self.parent.spinner_logic.start_thinking()

    def on_image_processing(self):
        self.parent.spinner_logic.start_thinking()

    def on_image_description(self, description: str):
        self.parent.spinner_logic.start_thinking()

    def on_scroll_changed(self, value: int) -> None:
        scroll_bar = self.parent.ui.scroll_area.verticalScrollBar()
        max_value = scroll_bar.maximum()
        scroll_threshold = max(20, self.parent.ui.scroll_area.height() // 4)
        self.parent.user_scrolling = max_value - value > scroll_threshold
        print(
            f"Scroll changed, user_scrolling: {self.parent.user_scrolling}, value: {value}, max: {max_value}"
        )
        self.parent.last_scroll_value = value

    def on_screenshot_clicked(self):
        print("Bắt đầu chụp hình")
        self.parent.hide()
        self.screenshot_overlay = ScreenshotOverlay()
        self.screenshot_overlay.screenshot_captured.connect(self.on_screenshot_captured)
        self.screenshot_overlay.cancelled.connect(self.on_screenshot_cancelled)
        self.screenshot_overlay.show()

    def on_screenshot_captured(self, pixmap):
        print("Screenshot đã được chụp")
        self.parent.show()
        self.parent.raise_()
        self.parent.activateWindow()
        self.parent.show_screenshot_preview(pixmap)

    def on_screenshot_cancelled(self):
        print("Chụp hình bị hủy")
        self.parent.show()
        self.parent.raise_()
        self.parent.activateWindow()

    def handle_error(self, error_message):
        self.parent.ui.input_box.setEnabled(True)
        self.parent.ui.input_box.setPlaceholderText("Nhập tin nhắn hoặc /help...")
        self.parent.waiting_for_response = False
        self.parent.spinner_logic.reset_to_idle()
        self.parent.ui.response_display.setHtml(
            f'<div style="padding: 15px 10px; color: #f44336;">{error_message}</div>'
        )
        self.parent.ui.thinking_widget.hide()
        if self.ollama_thread:
            if self.ollama_thread.isRunning():
                self.ollama_thread.quit()
                self.ollama_thread.wait()
            self.ollama_thread.deleteLater()
            self.ollama_thread = None
        self.parent.ui.send_stop_button.set_running(False)

    def on_generation_finished(self):
        print("Generation finished")
        self.parent.ui.input_box.setEnabled(True)
        self.parent.ui.input_box.setPlaceholderText("Nhập tin nhắn hoặc /help...")
        self.parent.ui.input_box.clear()
        self.parent.waiting_for_response = False
        self.parent.spinner_logic.reset_to_idle()
        # Mở thinking widget hoàn toàn sau khi generation finished
        if self.parent.ui.thinking_widget.isVisible() and self.full_thinking_md.strip():
            self.parent.ui.toggle_thinking(show_full_content=True)
        else:
            self.parent.ui.thinking_widget.hide()

        # Hide deep search widget on finish
        self.parent.ui.deep_search_widget.hide()
        self.parent.ui.deep_search_display.clear()

        # Cuộn lên đầu TRƯỚC KHI maximize để user thấy phần đầu response
        from PySide6.QtCore import QPropertyAnimation, QEasingCurve

        # Scroll response_display, không phải scroll_area
        scroll_bar = self.parent.ui.response_display.verticalScrollBar()
        current_value = scroll_bar.value()
        max_value = scroll_bar.maximum()

        print(
            f"Before maximize - scroll position: current={current_value}, max={max_value}"
        )

        # Reset user_scrolling flag to allow auto-scroll
        self.parent.user_scrolling = False

        # Scroll to top first (if needed), then maximize
        if max_value > 0 and current_value > 0:
            # Stop any existing scroll animation
            if (
                self.scroll_animation
                and self.scroll_animation.state() == QPropertyAnimation.Running
            ):
                self.scroll_animation.stop()

            # Create smooth scroll animation
            self.scroll_animation = QPropertyAnimation(scroll_bar, b"value")
            self.scroll_animation.setDuration(800)  # 800ms for smooth scroll
            self.scroll_animation.setStartValue(current_value)
            self.scroll_animation.setEndValue(0)  # Scroll to top
            self.scroll_animation.setEasingCurve(QEasingCurve.InOutQuad)

            # Maximize window AFTER scroll animation completes
            def on_scroll_finished():
                print("Scroll animation completed, now maximizing window")
                self.parent.ui.adjust_window_height(staged=False)

            self.scroll_animation.finished.connect(on_scroll_finished)
            self.scroll_animation.start()
            print(f"Scroll animation started from {current_value} to 0")
        else:
            # No scroll needed, just maximize
            print(f"No scroll needed, maximizing directly")
            self.parent.ui.adjust_window_height(staged=False)

        if self.ollama_thread:
            if self.ollama_thread.isRunning():
                self.ollama_thread.quit()
                self.ollama_thread.wait()
            self.ollama_thread.deleteLater()
            self.ollama_thread = None
        self.parent.ui.send_stop_button.set_running(False)
