import 'package:flutter/material.dart';
import '../models/canvas_model.dart';
import '../services/api_service.dart';

class CanvasProvider extends ChangeNotifier {
  List<CanvasModel> _canvases = [];
  bool _isLoading = false;
  String? _error;
  CanvasModel? _currentCanvas;

  List<CanvasModel> get canvases => _canvases;
  bool get isLoading => _isLoading;
  String? get error => _error;
  CanvasModel? get currentCanvas => _currentCanvas;

  Future<void> loadCanvases() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.get('/canvas/');
      final List<dynamic> data = ApiService.parseResponse(response);
      _canvases = data.map((json) => CanvasModel.fromJson(json)).toList();
      
      // Sort by updated_at desc
      _canvases.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createCanvas({required String title, required String content, String type = 'markdown'}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.post('/canvas/', body: {
        'title': title,
        'content': content,
        'type': type,
      });
      final data = ApiService.parseResponse(response);
      final newCanvas = CanvasModel.fromJson(data);
      _canvases.insert(0, newCanvas);
      _currentCanvas = newCanvas;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateCanvas(int id, {String? title, String? content}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.put('/canvas/$id', body: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
      });
      final data = ApiService.parseResponse(response);
      final updatedCanvas = CanvasModel.fromJson(data);
      
      final index = _canvases.indexWhere((c) => c.id == id);
      if (index != -1) {
        _canvases[index] = updatedCanvas;
      }
      
      if (_currentCanvas?.id == id) {
        _currentCanvas = updatedCanvas;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteCanvas(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.delete('/canvas/$id');
      _canvases.removeWhere((c) => c.id == id);
      if (_currentCanvas?.id == id) {
        _currentCanvas = null;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectCanvas(CanvasModel? canvas) {
    _currentCanvas = canvas;
    notifyListeners();
  }

  Future<void> fetchAndSelectCanvas(int id) async {
    try {
      final response = await ApiService.get('/canvas/$id');
      final data = ApiService.parseResponse(response);
      final canvas = CanvasModel.fromJson(data);
      
      // Update list if exists, else add to top
      final index = _canvases.indexWhere((c) => c.id == id);
      if (index != -1) {
        _canvases[index] = canvas;
      } else {
        _canvases.insert(0, canvas);
      }
      
      _currentCanvas = canvas;
      notifyListeners();
    } catch (e) {
      print('Error fetching canvas $id: $e');
    }
  }
}
