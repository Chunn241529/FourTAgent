# Verification Report: Deep Search Fixes

## 1. Deep Search Indicator UI Logic

- **Regression Fix**: Updated `_getCurrentStage` in `deep_search_indicator.dart` to prevent backward step progression. Added logic to treat 'planning' as a later stage (Synthesizing preparation) if reflection has already occurred.
- **Plan Integration**: Updated `DeepSearchMetadata` and `DeepSearchStepData` to include `planContent`. The "Lập kế hoạch" step now displays the research plan when expanded.
- **Cleanup**: Removed the standalone `PlanIndicator` widget from `message_bubble.dart` to avoid duplication.

## 2. Backend Logic: Image Generation Guard

- **Issue**: The LLM was occasionally hallucinating `generate_image` calls when the user performed a web search, because the guard logic was too strict (context mismatch) or too loose (generic keywords).
- **Fix**: Updated `app/services/chat_service.py` to use a refined guard logic:
  - **Keywords**: Expanded strong keywords (e.g., "draw", "sketch", "create image").
  - **Regex**: Added a regex pattern `(generate|create|make|produce|design).*(image|picture|photo|art|drawing)` to capture intent like "generate an image" while ignoring "search for images".
- **Verification**: Ran `verify_guard_logic.py` with various test cases.
  - **Result**: PASSED. The logic correctly distinguishes between search intent ("Find image"), generation intent ("Generate image"), and comments ("Picture is nice").

## 3. Code Integrity

- **Python**: Verified syntax of `chat_service.py` using `py_compile`.
- **Dart**: Manually verified class definitions and widget structure. Added missing `planContent` field to `DeepSearchStepData`.

## 4. How to Test Manually

1. **Deep Search**: Ask a complex question (e.g., "Lên kế hoạch du lịch Nhật Bản 5 ngày"). Verify that the "Lập kế hoạch" step appears and contains the plan text. Verify steps progress from Plan -> Search -> Reflect -> Synthesize.
2. **Image Guard**:
   - Ask "Tìm hình ảnh xe Ford Mustang" -> Should trigger **Web Search**, NOT Image Generation.
   - Ask "Vẽ xe Ford Mustang" -> Should trigger **Image Generation**.
   - Ask "Generate an image of a city" -> Should trigger **Image Generation**.
